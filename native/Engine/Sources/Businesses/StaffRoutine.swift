import Foundation
import GameCore
import Countries
import Employees

/// A company's people in a week: tiredness and sickness, quitting, problems, and learning on the job.
/// Original: `staffWeek` and `handleStaffEvent` (engine/people/people.js, engine/company/model.js).
public enum StaffRoutine {
    public static func weekly(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData, utilisation util: Double) {
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
            if s.random.chance(odds) && !co.value("flags")["noquit"].bool { events.append(.quit(staffID: m.id)) }
            if let trait = n.trait, m.raw["flag"] == nil || m.raw["flag"]!.isNull,
               s.random.chance((s.hasHeadOffice("hr") ? 0.012 : 0.02) * (hasLead ? 0.6 : 1)) {
                m.set("flag", trait)
                events.append(.problem(staffID: m.id, trait: trait))
            }
            staff[idx] = m
        }
        co.staff = staff
        co.set("payGap", payGap)
        s.companies[i] = co
        for e in events { handle(&s, companyIndex: i, e) }
        growSkills(&s, companyIndex: i)
    }

    static func handle(_ s: inout GameState, companyIndex i: Int, _ e: StaffEvent) {
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
        case .payAsk, .fixedSalaryAsk:
            break  // pay talks arrive with the events module
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
