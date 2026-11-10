import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum StaffProfile {
    public static func band(_ v: Double) -> String { v >= 80 ? "Outstanding" : v >= 65 ? "Strong" : v >= 45 ? "Capable" : v >= 28 ? "Developing" : "Entry level" }

    public static let problemText: [String: String] = [
        "late": "is often late", "lazy": "is under-performing", "conflict": "is causing conflict", "sick": "has high sick leave", "theft": "is suspected of stealing"]

    public struct Mood: Equatable, Sendable {
        public var word: String
        public var good: [String]
        public var bad: [String]
    }

    public struct Profile: Equatable, Sendable {
        public var staffID: Int
        public var name: String
        public var age: Int
        public var role: String
        public var roleName: String
        public var monthlyWage: Double
        public var payBasis: String
        public var hoursPerWeek: Double
        public var skillGainedSinceStart: Bool
        public var feedback: WorkLog.Feedback
        public var disengaged: Bool
        public var contract: EmploymentContract.Summary?
        public var weeksWithYou: Int
        public var lastRaiseWeek: Int?
        public var noticeWeeks: Int
        public var problem: String?
        public var mood: Mood
        public var lateThisQuarter: Int
        public var complaintsThisQuarter: Int
        public var warnings: Int
        public var underpaid: Bool
        public var newInRole: Bool
        public var dismissalDocumented: Bool
        public var severance: Double
        public var compensationRange: ClosedRange<Double>
        public var courses: [Course]
        public var commissionMode: String?
        public var commissionRate: Double
        public var isSalesRole: Bool
        public var perks: [String] = []
        public var perksWorth = 0.0
        public var bonusPlan: String? = nil
        public var bonusPaidThisYear = 0.0
        public var bonusMonthlyAverage = 0.0
        public var expenses: [String] = []
    }

    public struct Course: Equatable, Sendable {
        public var id: String; public var name: String; public var cost: Double
        public var benefit: String
        var maxGain: Double
    }

    static func marketPay(_ s: GameState, _ co: Company, _ m: StaffMember, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let base = data.catalog.tables.roles[m.role]?.baseMonthlyWage ?? 40000
        let market = w.city(co).map { Wages.market(baseMonthlyWage: base, country: w.country(co), city: $0, economy: s.economy, rates: w.rates) } ?? base
        return market * m.partTimeShare
    }

    public static func courses(_ co: Company, data: GameData) -> [Course] {
        guard let bd = data.catalog[co.type] else { return [] }
        let cur = Currency(country: data.countries[co.countryCode] ?? data.countries.countries[0], rates: ExchangeRates())
        return bd.raw["crs"].array.map { Course(id: $0[0].string, name: $0[1].string, cost: cur.scaledPrice($0[2].double), benefit: $0[4].double >= 10 ? "A large boost to what they can do, if it takes." : $0[4].double >= 5 ? "A solid boost to what they can do, if it takes." : "A modest boost to what they can do, if it takes.", maxGain: $0[4].double) }
    }

    public static func mood(_ s: GameState, companyID: Int, staffID: Int, data: GameData) -> Mood? {
        guard let co = s.company(companyID), let m = co.staff.first(where: { $0.id == staffID }), let n = s.people[staffID] else { return nil }
        var good: [String] = [], bad: [String] = []
        let market = marketPay(s, co, m, data: data)
        let perkList = StaffPerks.perks(for: m, in: co)
        let perkWorth = StaffPerks.worthMonthly(co, m, currency: World(state: s, data: data).currency(co))
        let eff = m.monthlyWage + ((m.commissionMode != nil && m.commissionMode != "fix") ? m.num("commEma") * 52 / 12 : 0) + m.num("bnEma") + perkWorth
        let gap = (market * (0.7 + n.skill / 160) - eff) / max(1, market)
        let lr = m.raw["lr"].map { $0.isNull ? m.hiredWeek : $0.int } ?? m.hiredWeek
        if m.happyUntilWeek != 0 && s.week < m.happyUntilWeek { good.append("pleased with a recent raise or their pay") }
        let fit = StaffWeek.fit(staff: m, tradeID: co.type)
        if fit <= 0.3 { good.append("really likes this kind of work") } else if fit >= 2 { bad.append("this job is not really for them") }
        if let plan = WorkerBonus.level(of: m) { good.append("on the \(plan.name.lowercased())" + (m.num("bnEma") > 0 ? ": bonuses have been paid lately" : "")) }
        if !perkList.isEmpty { good.append("looked after: \(perkList.map { $0.name }.joined(separator: ", "))") }
        if gap > 0.1 { bad.append("paid less than the job usually pays") }
        let denied = m.int("denied")
        if denied != 0 && s.week - denied < 26 { bad.append("was turned down for a raise \(s.week - denied) weeks ago") }
        else if s.week - lr >= 52 { bad.append("no raise for over a year") }
        if m.tiredness >= 40 { bad.append("tired from long weeks") }
        if StaffPromises.letDown(m, week: s.week) { bad.append("was promised something that did not happen") }
        else if StaffPromises.promises(s, personID: staffID).contains(where: { $0.status == .fulfilled && s.week - ($0.resolvedWeek ?? 0) < 52 }) { good.append("what was promised to them was kept") }
        if StaffBehaviour.isDisengaged(m) { bad.append("has lost interest in the work") }
        if !m.value("flag").isNull { bad.append("there is a problem to sort out") }
        if !co.value("mood").isNull {
            if co.num("mood") < 40 { bad.append("the mood in the team is low") } else if co.num("mood") >= 75 { good.append("the team gets on well") }
        }
        let word = m.noticeWeeks > 0 ? "Leaving" : (bad.count >= 2 || (!bad.isEmpty && good.isEmpty && gap > 0.1)) ? "Unhappy" : (!good.isEmpty && bad.isEmpty) ? "Happy" : !bad.isEmpty ? "Mixed" : "Content"
        return Mood(word: word, good: good, bad: bad)
    }

    public static func profile(_ s: GameState, companyID: Int, staffID: Int, data: GameData) -> Profile? {
        guard let co = s.company(companyID), let m = co.staff.first(where: { $0.id == staffID }), let n = s.people[staffID],
              let mood = mood(s, companyID: companyID, staffID: staffID, data: data) else { return nil }
        let t = data.catalog.tables
        let sev = Dismissal.quote(s, companyID: companyID, staffID: staffID, data: data)?.total ?? 0
        let market = marketPay(s, co, m, data: data)
        let gap = (market * (0.7 + n.skill / 160) - m.monthlyWage) / max(1, m.monthlyWage)
        let hours = m.weeklyHours ?? StaffModel.fullWeekHours
        return Profile(staffID: staffID, name: n.name, age: n.age, role: m.role, roleName: t.roles[m.role]?.name ?? m.role, monthlyWage: m.monthlyWage, payBasis: m.payBasis,
                       hoursPerWeek: hours, skillGainedSinceStart: m.skillGain >= 3, feedback: WorkLog.feedback(m, week: s.week), disengaged: StaffBehaviour.isDisengaged(m),
                       contract: EmploymentContract.summary(s, companyID: companyID, personID: staffID, data: data), weeksWithYou: max(0, s.week - m.hiredWeek),
                       lastRaiseWeek: m.raw["lr"].flatMap { $0.isNull ? nil : $0.int }, noticeWeeks: m.noticeWeeks,
                       problem: m.value("flag").isNull ? nil : m.str("flag"), mood: mood, lateThisQuarter: m.int("late"), complaintsThisQuarter: m.int("cmp"),
                       warnings: m.int("warn"), underpaid: gap > 0.1, newInRole: m.num("nr") > 0, dismissalDocumented: isDocumented(m),
                       severance: sev, compensationRange: (m.monthlyWage * 2)...(m.monthlyWage * 4), courses: courses(co, data: data),
                       commissionMode: m.commissionMode, commissionRate: m.commissionRate, isSalesRole: PayPlans.eligible(role: m.role, trade: co.type, salesRoles: t.salesRoles),
                       perks: StaffPerks.perks(for: m, in: co).map { $0.name }, perksWorth: StaffPerks.worthMonthly(co, m, currency: World(state: s, data: data).currency(co)),
                       bonusPlan: WorkerBonus.level(of: m)?.name, bonusPaidThisYear: m.num("bnYtd"), bonusMonthlyAverage: m.num("bnEma"),
                       expenses: StaffExpenses.on(m).map { $0.name })
    }

    static func isDocumented(_ m: StaffMember) -> Bool { m.int("warn") >= 2 || m.str("flag") == "theft" }

    public enum CourseResult: Equatable, Sendable { case none, cash, done(String) }

    public static func takeCourse(_ s: inout GameState, companyID: Int, staffID: Int?, courseID: String, data: GameData) -> CourseResult {
        guard let i = s.companyIndex(companyID), let c = courses(s.companies[i], data: data).first(where: { $0.id == courseID }) else { return .none }
        if let id = staffID, !s.companies[i].staff.contains(where: { $0.id == id }) { return .none }
        if !Payments.companyPays(&s, companyID: companyID, amount: c.cost, category: "oth", label: "Course: \(c.name)") { return .cash }
        let roll = s.random.next()
        var gain = 0.0, msg = "No noticeable change"
        if roll < 0.18 { msg = "Nothing sticks. Wasted money." }
        else if roll < 0.34 { gain = c.maxGain * 0.4; msg = "Small gain" }
        else if roll < 0.9 { gain = c.maxGain; msg = "Solid gain" }
        else { gain = c.maxGain * 1.8; msg = "Great result" }
        let poach = staffID != nil && roll > 0.9 && s.random.chance(0.3)
        let name: String
        if let id = staffID, let k = s.companies[i].staff.firstIndex(where: { $0.id == id }) {
            var st = s.companies[i].staff; st[k].skillGain = clamp(st[k].skillGain + gain, -10, 70); st[k].set("crsN", st[k].int("crsN") + 1); s.companies[i].staff = st
            StaffPromises.noticeChange(&s, companyID: companyID)
            name = s.people[id]?.name ?? "A team member"
            MarketEvents.log(&s, .recognition, title: "\(name) finished a course", detail: msg, companyID: companyID, tone: "good", employeeID: id)
        } else {
            s.companies[i].ownerSkill = clamp(s.companies[i].ownerSkill + gain, 0, 100)
            name = s.player.name
        }
        s.note("\(name) attended \"\(c.name)\" at \(s.companies[i].name): \(msg).", tone: gain > 0 ? "good" : "n", companyID: companyID)
        if poach, let id = staffID {
            s.note("\(name) was poached by a competitor after the course.", tone: "bad", companyID: companyID)
            Dismissal.dismiss(&s, companyID: companyID, staffID: id, reason: .resignation, data: data)
        }
        return .done(msg)
    }

    public static func talk(_ s: inout GameState, companyID: Int, staffID: Int) -> Bool? {
        guard let i = s.companyIndex(companyID), let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }) else { return nil }
        var st = s.companies[i].staff
        let ok = s.random.chance(0.5)
        if ok { st[k].set("flag", JSONValue.null) } else { st[k].set("warn", st[k].int("warn") + 1) }
        s.companies[i].staff = st
        return ok
    }

    public static func warn(_ s: inout GameState, companyID: Int, staffID: Int) -> Bool? {
        guard let i = s.companyIndex(companyID), let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }) else { return nil }
        var st = s.companies[i].staff
        st[k].set("warn", st[k].int("warn") + 1)
        st[k].set("warnW", s.week)
        var worked = false
        if !st[k].value("flag").isNull && s.random.chance(0.35) { st[k].set("flag", JSONValue.null); worked = true }
        s.companies[i].staff = st
        return worked
    }

    public struct DismissResult: Equatable, Sendable { public var severance: Double; public var claimedUnfairDismissal: Bool; public var compensation: Double }

    @discardableResult
    public static func dismiss(_ s: inout GameState, companyID: Int, staffID: Int, data: GameData) -> DismissResult? {
        guard let o = Dismissal.dismiss(&s, companyID: companyID, staffID: staffID, data: data) else { return nil }
        return DismissResult(severance: o.paid, claimedUnfairDismissal: o.claimedUnfairDismissal, compensation: o.compensation)
    }

    @discardableResult
    public static func layOff(_ s: inout GameState, companyID: Int, count n: Int, data: GameData) -> [Int] {
        guard let i = s.companyIndex(companyID), !s.companies[i].staff.isEmpty else { return [] }
        let t = data.catalog.tables
        let ranked = s.companies[i].staff.sorted { StaffModel.skill($0, person: s.people[$0.id], salesRoles: t.salesRoles) < StaffModel.skill($1, person: s.people[$1.id], salesRoles: t.salesRoles) }
        let gone = ranked.prefix(max(0, n)).map { $0.id }
        for id in gone { Dismissal.dismiss(&s, companyID: companyID, staffID: id, reason: .redundancy, data: data) }
        s.companies[i].set("mood", max(0, (s.companies[i].value("mood").isNull ? 60 : s.companies[i].num("mood")) - 6))
        s.note("\(s.companies[i].name) laid off \(gone.count) \(gone.count == 1 ? "person" : "people").", companyID: companyID)
        return gone
    }

    public static func layoffPreview(_ s: GameState, companyID: Int, count n: Int, data: GameData) -> (names: [String], savesPerMonth: Double, severance: Double) {
        guard let co = s.company(companyID) else { return ([], 0, 0) }
        let t = data.catalog.tables
        let k = World(state: s, data: data).country(co)
        let pick = co.staff.sorted { StaffModel.skill($0, person: s.people[$0.id], salesRoles: t.salesRoles) < StaffModel.skill($1, person: s.people[$1.id], salesRoles: t.salesRoles) }.prefix(max(0, n))
        let saves = pick.reduce(0) { $0 + EmployerCost.monthly($1, country: k).totalMonthly }
        let sev = Dismissal.quote(s, companyID: companyID, staffIDs: pick.map { $0.id }, reason: .redundancy, data: data)
        return (pick.map { $0.id }.compactMap { s.people[$0]?.name }, saves, sev)
    }

    public enum PayResult: Equatable, Sendable { case changed, resigned, notSales, unknown }

    public static func setPayModel(_ s: inout GameState, companyID: Int, staffID: Int, mode: String, data: GameData) -> PayResult {
        guard let i = s.companyIndex(companyID), let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }), let n = s.people[staffID] else { return .unknown }
        let salesRoles = data.catalog.tables.salesRoles, role = s.companies[i].staff[k].role
        guard PayPlans.eligible(role: role, trade: s.companies[i].type, salesRoles: salesRoles), ["fix", "mix", "com"].contains(mode) else { return .notSales }
        if mode == "com" && n.num("sec") > 0.65 && s.random.chance(0.6) {
            s.note("\(n.name) will not work on commission only and resigns.", tone: "bad", companyID: companyID)
            Dismissal.dismiss(&s, companyID: companyID, staffID: staffID, reason: .resignation, data: data)
            return .resigned
        }
        let rate = PayPlans.mode(mode)?.defaultRate ?? 0
        let co = s.companies[i]
        let cur = World(state: s, data: data).currency(co)
        let mk = cur.roundedStep(marketPay(s, co, co.staff[k], data: data) * (0.7 + n.skill / 160), about: 100)
        let floor = World(state: s, data: data).minimumWage(co, hours: co.staff[k].weeklyHours ?? StaffModel.fullWeekHours).rounded(.up)
        var st = co.staff
        st[k].monthlyWage = mode == "com" ? 0 : max(floor, mode == "fix" ? max(st[k].monthlyWage, cur.roundedStep(mk * 0.95, about: 100)) : cur.roundedStep(mk * (PayPlans.mode("mix")?.baseShare ?? 0.6), about: 100))
        st[k].set("pay", .object(["m": .string(mode), "rate": .number(rate)]))
        if PayPlans.isExtra(role: role, trade: s.companies[i].type, salesRoles: salesRoles) { if mode == "fix" { st[k].raw.removeValue(forKey: "ppx") } else { st[k].set("ppx", 1) } }
        st[k].set("commEma", 0)
        s.companies[i].staff = st
        return .changed
    }

    @discardableResult
    public static func setCommissionRate(_ s: inout GameState, companyID: Int, staffID: Int, rate: Double) -> Bool {
        guard let i = s.companyIndex(companyID), let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }), s.companies[i].staff[k].commissionMode != nil else { return false }
        var st = s.companies[i].staff
        var pay = st[k].value("pay"); pay["rate"] = .number(rate); st[k].set("pay", pay)
        s.companies[i].staff = st
        return true
    }

    public static func trackWeek(_ s: inout GameState) {
        for i in s.companies.indices where s.companies[i].status == .open {
            let q4 = s.week / 13
            var st = s.companies[i].staff
            var changed = false
            for k in st.indices {
                changed = true
                if st[k].raw["qtr"].map({ $0.int }) != q4 || st[k].raw["qtr"] == nil { st[k].set("qtr", q4); st[k].set("late", 0); st[k].set("cmp", 0) }
                let flag = st[k].str("flag")
                if s.random.chance(flag == "late" ? 0.45 : 0.01) { st[k].set("late", st[k].int("late") + 1); WorkLog.note(&st[k], week: s.week, late: 1) }
                if ["conflict", "lazy", "theft"].contains(flag) && s.random.chance(0.18) { st[k].set("cmp", st[k].int("cmp") + 1); WorkLog.note(&st[k], week: s.week, complaints: 1) }
                if !flag.isEmpty, st[k].int("warnW") != 0, s.week - st[k].int("warnW") <= 8, s.random.chance(0.05) {
                    st[k].set("flag", JSONValue.null)
                    if let n = s.people[st[k].id] { s.note("\(n.name) has improved after the warning.", tone: "good", companyID: s.companies[i].id) }
                }
            }
            if changed { s.companies[i].staff = st }
        }
    }
}
