import Foundation
import GameCore
import Countries
import Employees
import Finance

/// The employment contract of one team member as ONE read: the type (full time, part time, seasonal, temporary, hourly, fixed monthly salary), the
/// working percentage, real start and end dates, the notice the country's labour data sets, the renewal question and the history of every change.
/// Nothing is stored twice: the percentage is the contracted hours over the full week (`StaffMember.weeklyHours`), the end of a temporary or seasonal
/// contract is the existing `ft` week (`FixedTerm`), the season is `seas`. Old records (a part-timer on 20 hours, a seasonal worker on 25) read as the
/// equivalent percentage and lose nothing.
public enum EmploymentContract {
    public struct Summary: Equatable, Sendable {
        public var personID: Int
        /// "Full time", "Part time", "Seasonal", "Temporary": every label that applies, in this order.
        public var typeLabels: [String]
        /// The labels as one line, e.g. "Seasonal, part time".
        public var typeLabel: String
        /// "hour" (paid by the hour), "fix" (a fixed monthly salary), with the commission plan, if any, in `payPlan`.
        public var payBasis: String
        public var payBasisLabel: String
        public var payPlan: String?
        /// The share of a full week, as a percentage 0-100 (a person on 20 hours of a 37.5 hour week works 53.3).
        public var workingPercent: Double
        public var contractedHoursPerWeek: Double
        public var expectedHoursPerMonth: Double
        public var startWeek: Int
        public var startDate: GameCalendar.Date
        /// The end of a temporary or seasonal contract; nil for a permanent one.
        public var endWeek: Int?
        public var endDate: GameCalendar.Date?
        public var isPermanent: Bool
        /// Seasonal: the months (1-12), whether the person is on season now, and the next start and end of the season.
        public var seasonMonths: [Int]
        public var seasonText: String
        public var onSeason: Bool
        public var nextSeasonStartWeek: Int?
        public var nextSeasonEndWeek: Int?
        /// Notice the employee works if they resign, and what the labour data requires of the employer for a dismissal without cause and for the end of a term.
        public var resignationNoticeWeeks: Int
        public var employerNoticeWeeks: Double
        public var termEndNoticeWeeks: Double
        /// The week the owner is asked whether to renew (a few weeks before the end), nil for a permanent contract.
        public var renewalQuestionWeek: Int?
        public var renewals: Int
        /// The most hours a week this person can work (one in four candidates studies), nil when nothing limits it.
        public var hoursLimit: Double?
        public var history: [ContractHistory.Entry]
    }

    /// Contracted hours a week (a full-timer works the full week).
    public static func hours(_ m: StaffMember) -> Double { m.weeklyHours ?? StaffModel.fullWeekHours }
    /// Working percentage, 0-100.
    public static func percent(_ m: StaffMember) -> Double { (hours(m) / StaffModel.fullWeekHours * 100 * 100).rounded() / 100 }

    public static func isSeasonal(_ m: StaffMember) -> Bool { !m.value("seas").isNull }
    public static func isTemporary(_ m: StaffMember) -> Bool { FixedTerm.isFixed(m) && !isSeasonal(m) }
    public static func isPartTime(_ m: StaffMember) -> Bool { hours(m) < StaffModel.fullWeekHours - 1e-9 }

    public static func typeLabels(_ m: StaffMember) -> [String] {
        var out: [String] = []
        if isSeasonal(m) { out.append("Seasonal") }
        if isTemporary(m) { out.append("Temporary") }
        out.append(isPartTime(m) ? "Part time" : "Full time")
        return out
    }

    public static func payBasisLabel(_ m: StaffMember) -> String {
        switch m.commissionMode {
        case "com": return "Commission only"
        case "mix": return "Salary and commission"
        default: return m.payBasis == "fix" ? "Fixed monthly salary" : "Hourly"
        }
    }

    public static func summary(_ s: GameState, companyID: Int, personID: Int, data: GameData) -> Summary? {
        guard let co = s.company(companyID), let m = co.staff.first(where: { $0.id == personID }) else { return nil }
        let lab = World(state: s, data: data).labour(co)
        let age = Double(s.people[personID]?.age ?? 35)
        let labels = typeLabels(m)
        let h = hours(m)
        let end = FixedTerm.endWeek(m)
        let months = isSeasonal(m) ? m.value("seas").array.map { $0.int }.sorted() : []
        let onSeason = !months.isEmpty && months.contains(StaffTalks.month1(s.week))
        let nextStart = months.isEmpty ? nil : StaffTalks.nextSeasonStart(months: months, from: s.week)
        let nextEnd = nextStart.flatMap { StaffTalks.seasonEnd(months: months, fromWeek: $0, occurrences: 1) }
        let onSeasonEnd = onSeason ? StaffTalks.seasonEnd(months: months, fromWeek: s.week, occurrences: 1) : nextEnd
        let tenure = Double(s.week - m.hiredWeek)
        return Summary(personID: personID, typeLabels: labels, typeLabel: labels.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }.joined(separator: ", "),
                       payBasis: m.payBasis, payBasisLabel: payBasisLabel(m), payPlan: m.commissionMode, workingPercent: percent(m), contractedHoursPerWeek: h,
                       expectedHoursPerMonth: h * 52 / 12, startWeek: m.hiredWeek, startDate: GameCalendar.date(week: m.hiredWeek), endWeek: end,
                       endDate: end.map { GameCalendar.date(week: $0) }, isPermanent: end == nil,
                       seasonMonths: months, seasonText: months.isEmpty ? "" : StaffTalks.seasonText(months), onSeason: onSeason,
                       nextSeasonStartWeek: onSeason ? nil : nextStart, nextSeasonEndWeek: onSeasonEnd,
                       resignationNoticeWeeks: (m.hiredWeek < s.week - 52 ? 8 : 4) + m.int("nx"),
                       employerNoticeWeeks: lab.termination(tenureWeeks: tenure, reason: .unjustified, age: age).noticeWeeks,
                       termEndNoticeWeeks: lab.termination(tenureWeeks: tenure, reason: .expiry, age: age).noticeWeeks,
                       renewalQuestionWeek: end.map { $0 - FixedTerm.reviewWindowWeeks(lab) }, renewals: FixedTerm.renewals(m),
                       hoursLimit: m.value("maxH").isNull ? nil : m.num("maxH"), history: ContractHistory.entries(m))
    }
}

/// Every change to a contract with its date, kept on the staff record (`chist`, the last 40 entries).
public enum ContractHistory {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var week: Int
        /// "hired", "hours", "pay", "basis", "term", "season", "benefit", "role", "promise", "notice", "move".
        public var kind: String
        public var text: String
        public var id: String { "\(week):\(kind):\(text.hashValueStable)" }
        public var date: GameCalendar.Date { GameCalendar.date(week: week) }
    }

    static let cap = 40
    static let key = "chist"

    public static func entries(_ m: StaffMember) -> [Entry] {
        m.value(key).array.map { Entry(week: $0["w"].int, kind: $0["k"].string, text: $0["t"].string) }
    }

    static func append(_ m: inout StaffMember, week: Int, kind: String, text: String) {
        var l = m.value(key).array
        l.append(.object(["w": .number(Double(week)), "k": .string(kind), "t": .string(text)]))
        if l.count > cap { l.removeFirst(l.count - cap) }
        m.set(key, .array(l))
    }

    /// Write one entry on the person's record.
    public static func record(_ s: inout GameState, companyID: Int, staffID: Int, kind: String, text: String) {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return }
        var st = s.companies[ci].staff
        append(&st[k], week: s.week, kind: kind, text: text)
        s.companies[ci].staff = st
    }

    /// The terms of a job as they stand, to compare before and after a change.
    struct Snapshot: Equatable {
        var wage: Double, hours: Double, basis: String, plan: String, end: Int?, seasons: [Int], bonus: String, ownCar: Bool, expenses: Int
    }

    static func snapshot(_ m: StaffMember) -> Snapshot {
        Snapshot(wage: m.monthlyWage, hours: EmploymentContract.hours(m), basis: m.payBasis, plan: m.commissionMode ?? "", end: FixedTerm.endWeek(m),
                 seasons: m.value("seas").array.map { $0.int }.sorted(), bonus: m.str("bp"), ownCar: m.flag("ownCar"), expenses: StaffExpenses.on(m).count)
    }

    /// What changed between two snapshots, in words (money in the company's currency).
    static func describe(_ a: Snapshot, _ b: Snapshot, currency cur: Currency) -> [(kind: String, text: String)] {
        var out: [(String, String)] = []
        if abs(a.hours - b.hours) > 0.01 {
            out.append(("hours", "Working percentage \(fmt(a.hours / StaffModel.fullWeekHours * 100)) to \(fmt(b.hours / StaffModel.fullWeekHours * 100)) percent (\(fmt(a.hours)) to \(fmt(b.hours)) hours a week)."))
        }
        if abs(a.wage - b.wage) > 0.5 { out.append(("pay", "Monthly pay \(cur.display(a.wage)) to \(cur.display(b.wage)).")) }
        if a.basis != b.basis || a.plan != b.plan {
            out.append(("basis", "Pay basis changed: \(a.plan.isEmpty ? (a.basis == "fix" ? "fixed monthly salary" : "hourly") : a.plan) to \(b.plan.isEmpty ? (b.basis == "fix" ? "fixed monthly salary" : "hourly") : b.plan)."))
        }
        if a.end != b.end { out.append(("term", b.end == nil ? "Contract made permanent." : "Contract ends in week \(b.end ?? 0).")) }
        if a.seasons != b.seasons { out.append(("season", b.seasons.isEmpty ? "No longer seasonal." : "Season: \(StaffTalks.seasonText(b.seasons)).")) }
        if a.bonus != b.bonus { out.append(("benefit", b.bonus.isEmpty ? "Bonus plan removed." : "Bonus plan changed.")) }
        if a.ownCar != b.ownCar { out.append(("benefit", b.ownCar ? "Own car with mileage." : "Company car.")) }
        if a.expenses != b.expenses { out.append(("benefit", "Expense reimbursements changed.")) }
        return out
    }

    static func fmt(_ x: Double) -> String { String(format: "%g", (x * 10).rounded() / 10) }

    /// Record what a change did, given the state before it. Called from the doors that change a contract.
    static func recordChange(_ s: inout GameState, companyID: Int, staffID: Int, before: Snapshot?, extra: String? = nil, data: GameData) {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return }
        let cur = World(state: s, data: data).currency(s.companies[ci])
        var st = s.companies[ci].staff
        var wrote = false
        if let before {
            for (kind, text) in describe(before, snapshot(st[k]), currency: cur) { append(&st[k], week: s.week, kind: kind, text: text); wrote = true }
        }
        if let extra { append(&st[k], week: s.week, kind: "role", text: extra); wrote = true }
        _ = wrote
        s.companies[ci].staff = st
    }
}

extension String {
    /// A stable small hash for ids (Swift's `hashValue` differs between runs).
    var hashValueStable: Int { unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff } }
}

// MARK: Seasons with real dates

extension StaffTalks {
    /// The first week that is outside the season after `occurrences` seasons have run, counting a season already under way as the first.
    /// `months` are 1-12. nil if the months are empty or cover the whole year.
    static func seasonEnd(months: [Int], fromWeek: Int, occurrences: Int) -> Int? {
        let set = Set(months)
        guard !set.isEmpty, set.count < 12, occurrences > 0 else { return nil }
        var w = fromWeek, seen = 0
        var inSeason = set.contains(month1(w))
        for _ in 0..<(52 * 6) {
            w += 1
            let now = set.contains(month1(w))
            if inSeason && !now { seen += 1; if seen == occurrences { return w } }
            inSeason = now
        }
        return nil
    }

    /// The week the next season begins (the first week in a season month after one outside it); nil for all-year months.
    static func nextSeasonStart(months: [Int], from: Int) -> Int? {
        let set = Set(months)
        guard !set.isEmpty, set.count < 12 else { return nil }
        var w = from
        for _ in 0..<(52 * 2) {
            w += 1
            if set.contains(month1(w)) && !set.contains(month1(w - 1)) { return w }
        }
        return nil
    }

    /// Bring a seasonal worker back for one more season: the contract runs to the end of the next season (or of the one now running when none follows).
    @discardableResult
    static func renewSeason(_ s: inout GameState, companyID: Int, staffID: Int) -> Bool {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }), FixedTerm.isFixed(s.companies[ci].staff[k]) else { return false }
        let months = s.companies[ci].staff[k].value("seas").array.map { $0.int }
        guard let end = FixedTerm.endWeek(s.companies[ci].staff[k]), let newEnd = seasonEnd(months: months, fromWeek: end + 1, occurrences: 1) ?? seasonEnd(months: months, fromWeek: end + 1, occurrences: 2) else { return false }
        var st = s.companies[ci].staff
        let renewed = FixedTerm.renewals(st[k]) + 1
        st[k].set("ft", newEnd); st[k].set("ftl", max(1, newEnd - end)); st[k].set("ftr", renewed)
        st[k].raw.removeValue(forKey: "ftn"); st[k].raw.removeValue(forKey: "ftd")
        s.companies[ci].staff = st
        return true
    }

    /// Set the working percentage (10-100) of a worker: the hours a week follow, and so do pay for people paid by the hour, employer cost, expected
    /// hours, capacity and productivity. Nothing is clipped silently: a limit on the person's hours (`Hiring.maxHoursPerWeek`) answers `.student`.
    @discardableResult
    public static func setWorkingPercentage(_ s: inout GameState, companyID: Int, staffID: Int, percent: Double) -> OfferResult {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return .unknown }
        guard Hiring.workingPercentRange.contains(percent) else { return .refused }
        let hours = percent / 100 * StaffModel.fullWeekHours
        if hours > s.companies[ci].staff[k].num("maxH", 999) + 1e-9 { return .student }
        var st = s.companies[ci].staff
        if percent >= 100 - 1e-9 {
            // full time: the pay of an hourly worker returns to a full week
            if payFollowsHours(st[k]), let h = st[k].weeklyHours { st[k].monthlyWage = st[k].monthlyWage * StaffModel.fullWeekHours / h }
            for key in ["hrs", "pt"] { st[k].raw.removeValue(forKey: key) }
        } else {
            setHours(&st[k], hours)
        }
        s.companies[ci].staff = st
        return .ok
    }
}
