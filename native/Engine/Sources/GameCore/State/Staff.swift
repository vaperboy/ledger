import Foundation

/// A person working in a company. Original: `co.staff` entries (the person's CV lives in `GameState.people`).
public struct StaffMember: JSONRecord, Identifiable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var id: Int { get { int("id") } set { set("id", newValue) } }
    public var role: String { get { str("role") } set { set("role", newValue) } }
    /// Monthly pay for a full week (hourly staff: monthly pay for their hours). Original: `wage`.
    public var monthlyWage: Double { get { num("wage") } set { set("wage", newValue) } }
    public var hiredWeek: Int { get { int("w0") } set { set("w0", newValue) } }
    public var lastRaiseWeek: Int { get { int("lr") } set { set("lr", newValue) } }
    /// "hour" (paid for hours worked) or "fix" (fixed salary).
    public var payBasis: String { get { str("basis", "hour") } set { set("basis", newValue) } }
    public var skillGain: Double { get { num("skillGain") } set { set("skillGain", newValue) } }
    /// Share of a full week (part-timers). Original: `pt`.
    public var partTimeShare: Double { get { num("pt", 1) } set { set("pt", newValue) } }
    public var weeklyHours: Double? { get { value("hrs").isNull ? nil : num("hrs") } set { raw["hrs"] = newValue.map { .number($0) } ?? .null } }
    public var tiredness: Double { get { num("tired") } set { set("tired", newValue) } }
    /// Week until which the person is off sick, if any.
    public var sickUntilWeek: Int? { get { value("sick").isNull ? nil : int("sick") } set { raw["sick"] = newValue.map { .number(Double($0)) } ?? .null } }
    public var isOffSeason: Bool { flag("off") }
    public var noticeWeeks: Int { get { int("notice") } set { set("notice", newValue) } }
    /// Commission plan for sales roles: m = "fix" / "mix" / "com", rate = share of sales. Original: `pay`.
    public var commissionMode: String? { value("pay").isNull ? nil : value("pay")["m"].string }
    public var commissionRate: Double { value("pay")["rate"].double }
    public var happyUntilWeek: Int { get { int("happy") } set { set("happy", newValue) } }
}

/// A person on the labour market or on someone's payroll: their real skill, and what they claim. Original: `S.npcs`.
public struct Person: JSONRecord, Identifiable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var id: Int { get { int("id") } set { set("id", newValue) } }
    public var name: String { get { str("name") } set { set("name", newValue) } }
    public var age: Int { get { int("age") } set { set("age", newValue) } }
    public var role: String { get { str("role") } set { set("role", newValue) } }
    /// True skill 0-100 (the player only sees `claimedSkill` until they check references or trial the person).
    public var skill: Double { get { num("skill") } set { set("skill", newValue) } }
    public var claimedSkill: Double { get { num("claimSkill") } set { set("claimSkill", newValue) } }
    public var askingMonthlyWage: Double { get { num("ask") } set { set("ask", newValue) } }
    /// Id of the company that employs the person, 0 if free.
    public var employerID: Int { get { int("hired") } set { set("hired", newValue) } }
    public var potential: Double? { get { value("pot").isNull ? nil : num("pot") } set { raw["pot"] = newValue.map { .number($0) } ?? .null } }
    public var trait: String? { value("trait").isNull ? nil : str("trait") }
}
