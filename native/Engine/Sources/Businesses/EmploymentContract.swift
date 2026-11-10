import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum EmploymentContract {
    public struct Summary: Equatable, Sendable {
        public var personID: Int
        public var typeLabels: [String]
        public var typeLabel: String
        public var payBasis: String
        public var payBasisLabel: String
        public var payPlan: String?
        public var workingPercent: Double
        public var contractedHoursPerWeek: Double
        public var expectedHoursPerMonth: Double
        public var startWeek: Int
        public var startDate: GameCalendar.Date
        public var endWeek: Int?
        public var endDate: GameCalendar.Date?
        public var isPermanent: Bool
        public var seasonMonths: [Int]
        public var seasonText: String
        public var onSeason: Bool
        public var nextSeasonStartWeek: Int?
        public var nextSeasonEndWeek: Int?
        public var resignationNoticeWeeks: Int
        public var employerNoticeWeeks: Double
        public var termEndNoticeWeeks: Double
        public var renewalQuestionWeek: Int?
        public var renewals: Int
        public var hoursLimit: Double?
        public var history: [ContractHistory.Entry]
    }

    public static func hours(_ m: StaffMember) -> Double { m.weeklyHours ?? StaffModel.fullWeekHours }
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
                       employerNoticeWeeks: lab.termination(tenureWeeks: tenure, reason: .unjustified).noticeWeeks,
                       termEndNoticeWeeks: lab.termination(tenureWeeks: tenure, reason: .expiry).noticeWeeks,
                       renewalQuestionWeek: end.map { $0 - FixedTerm.reviewWindowWeeks(lab) }, renewals: FixedTerm.renewals(m),
                       hoursLimit: m.value("maxH").isNull ? nil : m.num("maxH"), history: ContractHistory.entries(m))
    }
}

public enum ContractHistory {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var week: Int
        public var kind: String
        public var text: String
        public var id: String { "\(week):\(kind):\(text.stableHash)" }
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

    public static func record(_ s: inout GameState, companyID: Int, staffID: Int, kind: String, text: String) {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return }
        var st = s.companies[ci].staff
        append(&st[k], week: s.week, kind: kind, text: text)
        s.companies[ci].staff = st
    }

    struct Snapshot: Equatable {
        var wage: Double, hours: Double, basis: String, plan: String, end: Int?, seasons: [Int], bonus: String, ownCar: Bool, expenses: Int
    }

    static func snapshot(_ m: StaffMember) -> Snapshot {
        Snapshot(wage: m.monthlyWage, hours: EmploymentContract.hours(m), basis: m.payBasis, plan: m.commissionMode ?? "", end: FixedTerm.endWeek(m),
                 seasons: m.value("seas").array.map { $0.int }.sorted(), bonus: m.str("bp"), ownCar: m.flag("ownCar"), expenses: StaffExpenses.on(m).count)
    }

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
    var stableHash: Int { unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff } }
}

extension StaffTalks {
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

    @discardableResult
    public static func setWorkingPercentage(_ s: inout GameState, companyID: Int, staffID: Int, percent: Double) -> OfferResult {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return .unknown }
        guard Hiring.workingPercentRange.contains(percent) else { return .refused }
        let hours = percent / 100 * StaffModel.fullWeekHours
        if hours > s.companies[ci].staff[k].num("maxH", 999) + 1e-9 { return .student }
        var st = s.companies[ci].staff
        if percent >= 100 - 1e-9 {
            if payFollowsHours(st[k]), let h = st[k].weeklyHours { st[k].monthlyWage = st[k].monthlyWage * StaffModel.fullWeekHours / h }
            for key in ["hrs", "pt"] { st[k].raw.removeValue(forKey: key) }
        } else {
            setHours(&st[k], hours)
        }
        s.companies[ci].staff = st
        StaffPromises.noticeChange(&s, companyID: companyID)
        return .ok
    }
}
