import Foundation
import GameCore
import Countries
import Employees
import Finance

/// A company's people in a week: tiredness and sickness, quitting, problems, and learning on the job.
/// Original: `staffWeek` and `handleStaffEvent` (engine/people/people.js, engine/company/model.js).
public enum StaffRoutine {
    /// Test hook: called with (pay gap, quit odds, tiredness, fit) for every person every week.
    nonisolated(unsafe) public static var probe: ((Double, Double, Double, Double, Double) -> Void)? = nil

    public static func weekly(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData, utilisation util: Double) {
        StaffTalks.seasonsTurn(&s, companyIndex: i)
        let w = World(state: s, data: data)
        var co = s.companies[i]
        let people = s.people
        let tables = data.catalog.tables
        var events: [StaffEvent] = []
        var payGap = 0.0
        var staff = co.staff
        let bottleneckIsPeople: Bool = {
            let bo = co.value("dbg")["botObj"]
            return bo.isNull || bo["kind"].string == "staff" || bo["kind"].string.isEmpty
        }()
        let hasLead = staff.contains { $0.role == "lead" }
        let country = w.country(co)
        var extras: [StaffExtras.Outcome] = []
        var goneIDs: [Int] = []
        var changedPeople: [Int: Person] = [:]
        let utilisationLast: Double? = co.value("lastW")["util"].isNull ? nil : co.value("lastW")["util"].double
        for idx in staff.indices {
            var m = staff[idx]
            guard let n = people[m.id] else { continue }
            if m.num("nr") > 0 { m.set("nr", m.num("nr") - 1) }
            if m.noticeWeeks > 0 {
                m.noticeWeeks -= 1
                if m.noticeWeeks <= 0 { events.append(.leave(staffID: m.id)) }
                staff[idx] = m
                continue
            }
            // Paperwork inspections, commission mishaps, hidden talent (original: staffExtra)
            var person = n
            let extra = StaffExtras.week(&m, person: &person, week: s.week, random: &s.random, companyUtilisation: utilisationLast,
                                         hasManager: co.managerID != nil, managerLearned: co.value("flags")["onbAll"].bool)
            if person.raw != n.raw { changedPeople[m.id] = person }
            extras.append(extra)
            if extra.left { goneIDs.append(m.id); var p2 = person; p2.employerID = 0; changedPeople[m.id] = p2; staff[idx] = m; continue }
            if StaffWeek.tire(&m, hoursWorked: StaffWeek.hoursWorked(m, utilisation: util, limitedByPeople: bottleneckIsPeople), week: s.week, random: &s.random) {
                events.append(.sick(staffID: m.id))
            }
            if m.isOffSeason { staff[idx] = m; continue }
            let base = tables.roles[m.role]?.baseMonthlyWage ?? 40000
            let market = (w.city(co).map { Wages.market(baseMonthlyWage: base, country: country, city: $0, economy: s.economy, week: s.week, rates: w.rates) } ?? base) * m.partTimeShare
            let effectivePay = m.monthlyWage + ((m.commissionMode != nil && m.commissionMode != "fix") ? m.num("commEma") * 52 / 12 : 0)
            let gap = clamp((market * (0.7 + n.skill / 160) - effectivePay) / market, -0.2, 0.4)
            payGap = max(payGap, gap)
            let tenure = Double(s.week - (m.raw["w0"].map { $0.isNull ? s.week : $0.int } ?? s.week))
            let odds = StaffWeek.quitOdds(family: bd.family, tradeID: co.type, staff: m, person: n, payGap: gap, tenure: tenure,
                                          week: s.week, hasHRManager: s.hasHeadOffice("hr"), hasTeamLead: hasLead)
            if let talk = StaffTalks.nextTalk(m, n, company: co, gap: gap, tenure: tenure, week: s.week, salesRoles: tables.salesRoles) { events.append(talk) }
            probe?(gap, odds, m.tiredness, StaffWeek.fit(staff: m, tradeID: co.type), tenure)
            if s.random.chance(odds * (1 - 0.13 * co.value("tm")["hr"].double)) && !co.value("flags")["noquit"].bool { events.append(.quit(staffID: m.id)) }   // an HR manager (ManagerTeam)
            if let trait = n.trait, m.raw["flag"] == nil || m.raw["flag"]!.isNull,
               s.random.chance((s.hasHeadOffice("hr") ? 0.012 : 0.02) * (hasLead ? 0.6 : 1)) {
                m.set("flag", trait)
                events.append(.problem(staffID: m.id, trait: trait))
            }
            staff[idx] = m
        }
        co.staff = staff.filter { !goneIDs.contains($0.id) }
        co.set("payGap", payGap)
        s.companies[i] = co
        for (id, p) in changedPeople { s.people[id] = p }
        applyExtras(&s, companyIndex: i, extras, currency: w.currency(co))
        // Agents who use their own car are paid mileage. Original: vehicle week (features/company/realistic_buying.js).
        let ownCars = co.staff.filter { $0.num("ownCar") != 0 && !$0.isOffSeason }.count
        if ownCars > 0 { Payments.companyPays(&s, companyID: co.id, amount: w.currency(co).scaledPrice(4500) * 12 / 52 * Double(ownCars), category: "oth", label: "Mileage for own cars") }
        for e in events { handle(&s, companyIndex: i, e, data: data) }
        growSkills(&s, companyIndex: i)
    }

    /// Book what the paperwork and commission checks found: fines, lost reputation, and the notes.
    static func applyExtras(_ s: inout GameState, companyIndex i: Int, _ list: [StaffExtras.Outcome], currency cur: Currency) {
        for x in list {
            let co = s.companies[i]
            for f in x.fines {
                let label = f.note.hasPrefix("Inspectors") ? "Paperwork fine" : "Mis-selling complaint"
                let fine = cur.scaledPrice(f.amount)   // fines are written at the reference price level
                Payments.companyPays(&s, companyID: co.id, amount: fine, category: "fine", label: label)
                s.note(f.note.replacingOccurrences(of: "{co}", with: co.name).replacingOccurrences(of: "{fine}", with: cur.display(fine)), tone: "bad", companyID: co.id)
            }
            if x.reputationLoss > 0 { s.companies[i].reputation = clamp(s.companies[i].reputation - x.reputationLoss, 0, 100) }
            if x.managerLearnsPaperwork {
                var flags = s.companies[i].value("flags"); flags["onbAll"] = 1; s.companies[i].set("flags", flags)
                if let mid = s.companies[i].managerID, let mn = s.people[mid] {
                    s.note("\(mn.name) got the fine at \(co.name) and now completes all staff paperwork straight away.", tone: "n", companyID: co.id)
                }
            }
            for n in x.notes { s.note(n.text.replacingOccurrences(of: "{co}", with: co.name), tone: n.tone, companyID: co.id) }
        }
    }

    static func handle(_ s: inout GameState, companyIndex i: Int, _ e: StaffEvent, data: GameData) {
        var co = s.companies[i]
        func name(_ id: Int) -> String { s.people[id]?.name ?? "A team member" }
        func role(_ m: StaffMember) -> String { m.role }
        switch e {
        case .quit(let id):
            guard var m = co.staff.first(where: { $0.id == id }), m.noticeWeeks == 0 else { return }
            m.noticeWeeks = m.hiredWeek < s.week - 52 ? 8 : 4
            co.staff = co.staff.map { $0.id == id ? m : $0 }
            s.companies[i] = co
            s.note("\(name(id)) handed in notice at \(co.name) and leaves in \(m.noticeWeeks) weeks.", tone: "bad", companyID: co.id)
        case .sick(let id):
            s.note("\(name(id)) is off sick this week at \(co.name).", tone: "bad", companyID: co.id)
        case .leave(let id):
            s.note("\(name(id)) has left \(co.name).", tone: "bad", companyID: co.id)
            co.staff = co.staff.filter { $0.id != id }
            s.companies[i] = co
            if var p = s.people[id] { p.employerID = 0; s.people[id] = p }
        case .problem(let id, let trait):
            let labels = ["late": "is often late", "lazy": "is under-performing", "conflict": "is causing conflict in the team",
                          "sick": "has high sick leave", "theft": "is suspected of stealing"]
            s.note("PROBLEM at \(co.name): \(name(id)) \(labels[trait] ?? "is a concern"). See the team list.", tone: "bad", companyID: co.id)
            if trait == "theft" {
                var flags = co.value("flags"); flags["shrinkUp"] = .number(flags["shrinkUp"].double + 0.4)
                co.set("flags", flags); s.companies[i] = co
            }
        case .payAsk(let id):
            StaffTalks.ask(&s, companyIndex: i, staffID: id, fixed: false, data: data)
        case .fixedSalaryAsk(let id):
            StaffTalks.ask(&s, companyIndex: i, staffID: id, fixed: true, data: data)
        }
    }

    /// People learn on the job towards their potential, quickly when young. Original: part of `weekEnd`.
    static func growSkills(_ s: inout GameState, companyIndex i: Int) {
        var co = s.companies[i]
        var staff = co.staff
        for idx in staff.indices {
            var m = staff[idx]
            guard var n = s.people[m.id] else { continue }
            if n.potential == nil {
                let r = HashedRandom.first("\(s.seed):pot:\(m.id)")
                n.potential = clamp(jsRound(n.skill + 16 + r * 30), n.skill + 8, 98)
                s.people[m.id] = n
            }
            let cur = n.skill + m.skillGain
            let hired = m.raw["w0"].map { $0.isNull ? s.week : $0.int } ?? s.week
            let age = n.age + (s.week - hired) / 52
            let ageF: Double = age < 25 ? 1.35 : age < 35 ? 1.1 : age < 50 ? 0.85 : age < 60 ? 0.6 : 0.35
            m.skillGain = clamp(m.skillGain + max(0, (n.potential ?? n.skill) - cur) * 0.0065 * ageF, -10, max(30, (n.potential ?? n.skill) - n.skill))
            staff[idx] = m
        }
        co.staff = staff
        s.companies[i] = co
    }
}
