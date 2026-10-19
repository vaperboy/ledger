import Foundation

/// Where a company is in its life. Original: `co.st`.
public enum CompanyStatus: String, Sendable {
    case setup, open, closed, sold, bust
    public var isLive: Bool { self != .sold && self != .bust }
}

/// Which legal form. Original: `co.form`. ENK = sole trader (the owner is personally liable), AS = limited company.
public enum LegalForm: String, Sendable {
    case soleTrader = "ENK"
    case limited = "AS"
}

/// Category totals for a company's books: this week, this month, this year, last year and since the start.
/// Categories: rev, cogs, wages, rent, mkt, ins, oth, dep, int, fine, loss, acc, tax.
public struct Books: Equatable, Sendable {
    public var week: [String: Double] = [:]
    public var month: [String: Double] = [:]
    public var year: [String: Double] = [:]
    public var lastYear: [String: Double] = [:]
    public var total: [String: Double] = [:]

    public init() {}
    init(json: JSONValue) {
        func d(_ k: String) -> [String: Double] { json[k].object.mapValues { $0.double } }
        week = d("w"); month = d("m"); year = d("y"); lastYear = d("ly"); total = d("t")
    }
    var json: JSONValue {
        func v(_ d: [String: Double]) -> JSONValue { .object(d.mapValues { .number($0) }) }
        return .object(["w": v(week), "m": v(month), "y": v(year), "ly": v(lastYear), "t": v(total)])
    }

    /// Book an amount in a category in every period. Original: `bk(co, cat, amt)`.
    public mutating func add(_ category: String, _ amount: Double) {
        week[category, default: 0] += amount
        month[category, default: 0] += amount
        year[category, default: 0] += amount
        total[category, default: 0] += amount
    }

    /// Total costs of a period. Original: `sumExp(b)`.
    public static func expenses(_ b: [String: Double]) -> Double {
        ["cogs", "wages", "rent", "mkt", "ins", "oth", "dep", "int", "fine", "loss", "acc"].reduce(0) { $0 + (b[$1] ?? 0) }
    }
    public static func profit(_ b: [String: Double]) -> Double { (b["rev"] ?? 0) - expenses(b) }
}

/// A company the player owns (or owned). Stored as JSON underneath (see `JSONRecord`); the properties below are
/// the ones the Swift game reads and writes. Every other field of an imported save is kept untouched.
public struct Company: JSONRecord, Identifiable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var id: Int { get { int("id") } set { set("id", newValue) } }
    public var type: String { get { str("type") } set { set("type", newValue) } }
    public var countryCode: String { get { str("country") } set { set("country", newValue) } }
    public var name: String { get { str("name") } set { set("name", newValue) } }
    public var cityID: String { get { str("city") } set { set("city", newValue) } }
    public var form: LegalForm { get { LegalForm(rawValue: str("form")) ?? .soleTrader } set { set("form", newValue.rawValue) } }
    public var size: Double { get { num("size", 1) } set { set("size", newValue) } }
    public var status: CompanyStatus { get { CompanyStatus(rawValue: str("st", "setup")) ?? .setup } set { set("st", newValue.rawValue) } }
    /// Week the company was founded / opened. Original: `w0`, `wOpen`.
    public var foundedWeek: Int { get { int("w0") } set { set("w0", newValue) } }
    public var openedWeek: Int? { get { value("wOpen").isNull ? nil : int("wOpen") } set { raw["wOpen"] = newValue.map { .number(Double($0)) } ?? .null } }
    /// The company's own cash. Never change this directly: use `Ledger.move` so every movement is recorded.
    public var cash: Double { get { num("cash") } set { set("cash", newValue) } }
    /// Percent of the company the player owns. Original: `own`.
    public var ownership: Double { get { num("own", 100) } set { set("own", newValue) } }
    /// Price level, -3 (budget) ... +3 (luxury), may be fractional. Original: `price`.
    public var priceLevel: Double { get { num("price") } set { set("price", newValue) } }
    /// Owner's weekly hours working in the company. Original: `ohrs`.
    public var ownerHours: Double { get { num("ohrs", 40) } set { set("ohrs", newValue) } }
    public var ownerSkill: Double { get { num("oskill", 40) } set { set("oskill", newValue) } }
    public var reputation: Double { get { num("rep", 45) } set { set("rep", newValue) } }
    public var quality: Double { get { num("q", 45) } set { set("q", newValue) } }
    /// How many potential customers know the company, 0-100. Original: `aware`.
    public var awareness: Double { get { num("aware", 25) } set { set("aware", newValue) } }
    /// 0 deferred, 1 normal, 2 thorough maintenance. Original: `maint`.
    public var maintenance: Int { get { int("maint", 1) } set { set("maint", newValue) } }
    /// Stock on hand, at cost. Original: `inv`.
    public var inventory: Double { get { num("inv") } set { set("inv", newValue) } }
    /// VAT collected minus VAT paid, waiting to be settled. Original: `vatAcc`.
    public var vatBalance: Double { get { num("vatAcc") } set { set("vatAcc", newValue) } }
    public var managerID: Int? { get { value("mgr").isNull ? nil : int("mgr") } set { raw["mgr"] = newValue.map { .number(Double($0)) } ?? .null } }
    public var managerMonthlyWage: Double { get { num("mgrWage") } set { set("mgrWage", newValue) } }
    public var managerProfitBonus: Double { get { num("mgrBonus") } set { set("mgrBonus", newValue) } }
    public var ownerMonthlySalary: Double { get { num("ownerSalary") } set { set("ownerSalary", newValue) } }
    public var shareCapital: Double { get { num("capital") } set { set("capital", newValue) } }
    /// Total money the owner has put into a limited company. Original: `inj`.
    public var injectedCapital: Double { get { num("inj") } set { set("inj", newValue) } }
    public var ownerNetFlow: Double { get { num("ownNet") } set { set("ownNet", newValue) } }
    public var distributed: Double { get { num("dist") } set { set("dist", newValue) } }
    public var weeksNegative: Int { get { int("negW") } set { set("negW", newValue) } }
    public var unpaidMonths: Int { get { int("unpaid") } set { set("unpaid", newValue) } }
    public var wageShortfall: Double { get { num("wageShort") } set { set("wageShort", newValue) } }
    public var lossCarryForward: Double { get { num("lossCarry") } set { set("lossCarry", newValue) } }
    public var lossCarryAtYearStart: Double? { get { value("lc0").isNull ? nil : num("lc0") } set { raw["lc0"] = newValue.map { .number($0) } ?? .null } }
    public var yearProfitSoFar: Double { get { num("ytdP") } set { set("ytdP", newValue) } }
    public var taxAccrued: Double { get { num("taxAcc") } set { set("taxAcc", newValue) } }
    public var taxDue: Bool { get { flag("taxDue") } set { set("taxDue", newValue) } }
    public var taxDueWeek: Int { get { int("taxDueW") } set { set("taxDueW", newValue) } }
    public var taxPrevYear: Double { get { num("taxPrev") } set { set("taxPrev", newValue) } }
    public var holdingID: Int { get { int("hold") } set { set("hold", newValue) } }
    public var lastWeekUnits: Double { get { value("lastW")["units"].double } }
    public var lastWeekRevenue: Double { get { value("lastW")["rev"].double } }
    public var lastWages: Double { get { num("lastWages") } set { set("lastWages", newValue) } }

    /// Amounts owed and not yet paid: wages, other bills, rent, tax. Original: `co.pay`.
    public var payables: [String: Double] {
        get { value("pay").object.mapValues { $0.double } }
        set { raw["pay"] = .object(newValue.mapValues { .number($0) }) }
    }
    public mutating func addPayable(_ key: String, _ amount: Double) {
        var p = payables
        p[key, default: 0] += amount
        payables = p
    }

    public var books: Books {
        get { Books(json: value("bk")) }
        set { raw["bk"] = newValue.json }
    }

    public var staff: [StaffMember] {
        get { records("staff") }
        set { setRecords("staff", newValue) }
    }
    public var receivables: [Receivable] {
        get { records("recv") }
        set { setRecords("recv", newValue) }
    }
    public var monthlyHistory: [MonthRecord] {
        get { records("hist") }
        set { setRecords("hist", newValue) }
    }
    public var transactions: [JSONValue] {
        get { value("tx").array }
        set { raw["tx"] = .array(newValue) }
    }
    /// Newest first, capped at 40, like the original's `co.tx`.
    public mutating func addTransaction(week: Int, amount: Double, label: String) {
        var t = transactions
        t.insert(.object(["w": .number(Double(week)), "a": .number(amount), "l": .string(label)]), at: 0)
        if t.count > 40 { t.removeLast(t.count - 40) }
        transactions = t
    }

    public var isOpenOrClosed: Bool { status == .open || status == .closed }
}

/// An unpaid customer invoice (business customers pay after a few weeks). Original: `co.recv` entries.
public struct Receivable: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }
    public init(amount: Double, dueWeek: Int, willDefault: Bool) {
        self.raw = ["a": .number(amount), "due": .number(Double(dueWeek)), "bad": .bool(willDefault)]
    }
    public var amount: Double { get { num("a") } set { set("a", newValue) } }
    public var dueWeek: Int { get { int("due") } set { set("due", newValue) } }
    /// Hidden from the player: this customer will never pay. Original: `bad`.
    public var willDefault: Bool { get { flag("bad") } set { set("bad", newValue) } }
}

/// One line of a company's monthly history. Original: `co.hist` entries.
public struct MonthRecord: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }
    public init(monthIndex: Int, revenue: Double, profit: Double, cash: Double) {
        self.raw = ["m": .number(Double(monthIndex)), "rev": .number(revenue), "profit": .number(profit), "cash": .number(cash)]
    }
    public var monthIndex: Int { get { int("m") } set { set("m", newValue) } }
    public var revenue: Double { get { num("rev") } set { set("rev", newValue) } }
    public var profit: Double { get { num("profit") } set { set("profit", newValue) } }
    public var cash: Double { get { num("cash") } set { set("cash", newValue) } }
}
