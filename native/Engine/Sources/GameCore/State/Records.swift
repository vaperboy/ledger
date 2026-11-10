import Foundation

public struct Loan: JSONRecord, Identifiable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var id: Int { get { int("id") } set { set("id", newValue) } }
    public var kind: String { get { str("kind") } set { set("kind", newValue) } }
    public var name: String { get { str("name") } set { set("name", newValue) } }
    public var balance: Double { get { num("bal") } set { set("bal", newValue) } }
    public var originalAmount: Double { get { num("amt0") } set { set("amt0", newValue) } }
    public var margin: Double { get { num("margin") } set { set("margin", newValue) } }
    public var monthlyPayment: Double { get { num("pay") } set { set("pay", newValue) } }
    public var termMonths: Int { get { int("termM") } set { set("termM", newValue) } }
    public var companyID: Int { get { int("co") } set { set("co", newValue) } }
    public var startWeek: Int { get { int("w0") } set { set("w0", newValue) } }
    public var isGuaranteed: Bool { get { flag("guar") } set { set("guar", newValue) } }
    public var bankCompanyID: Int { get { int("bank") } set { set("bank", newValue) } }
    public var graceUntilWeek: Int { get { int("graceW") } set { set("graceW", newValue) } }
}

public struct Economy: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var phase: String { get { str("phase", "steady") } set { set("phase", newValue) } }
    public var weeksLeftInPhase: Int { get { int("left") } set { set("left", newValue) } }
    public var demand: Double { get { num("dem", 1) } set { set("dem", newValue) } }
    public var inflation: Double { get { num("infl", 0.03) } set { set("infl", newValue) } }
    public var inflationIndex: Double { get { num("ix", 1) } set { set("ix", newValue) } }
    public var fuel: Double { get { num("fuel", 1) } set { set("fuel", newValue) } }
    public var materials: Double { get { num("mat", 1) } set { set("mat", newValue) } }
    public var power: Double { get { num("power", 1) } set { set("power", newValue) } }
    public var oil: Double { get { num("oil", 1) } set { set("oil", newValue) } }
    public var housing: Double { get { num("housing", 1) } set { set("housing", newValue) } }
    public var policyRate: Double { get { num("rate", 0.0375) } set { set("rate", newValue) } }
    public var freight: Double { get { num("freight", 1) } set { set("freight", newValue) } }
    public var salmon: Double { get { num("salmon", 1) } set { set("salmon", newValue) } }
}

public struct PersonalTaxYear: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var salary: Double { get { num("wage") } set { set("wage", newValue) } }
    public var withheld: Double { get { num("withheld") } set { set("withheld", newValue) } }
    public var dividends: Double { get { num("ytdDiv") } set { set("ytdDiv", newValue) } }
    public var gains: Double { get { num("gain") } set { set("gain", newValue) } }
    public var interest: Double { get { num("int") } set { set("int", newValue) } }
    public var dividendShield: Double { get { num("shield") } set { set("shield", newValue) } }
    public var pending: Double { get { num("pending") } set { set("pending", newValue) } }
    public var paidDividend: Double { get { num("pDiv") } set { set("pDiv", newValue) } }
    public var paidGains: Double { get { num("pGain") } set { set("pGain", newValue) } }
    public var paidInterest: Double { get { num("pInt") } set { set("pInt", newValue) } }
    public var paidWealth: Double { get { num("pWealth") } set { set("pWealth", newValue) } }
}

public struct GameStats: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var peakNetWorth: Double { get { num("peak") } set { set("peak", newValue) } }
    public var bankruptcies: Int { get { int("bankrupt") } set { set("bankrupt", newValue) } }
    public var yearsPlayed: Int { get { int("years") } set { set("years", newValue) } }
    public var companiesSold: Int { get { int("sold") } set { set("sold", newValue) } }
    public var dividendsReceived: Double { get { num("dividends") } set { set("dividends", newValue) } }
    public var taxPaid: Double { get { num("taxPaid") } set { set("taxPaid", newValue) } }
    public var wagesPaid: Double { get { num("wagesPaid") } set { set("wagesPaid", newValue) } }
    public var interestPaid: Double { get { num("interest") } set { set("interest", newValue) } }
}

public struct Player: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var name: String { get { str("name", "You") } set { set("name", newValue) } }
    public var cityID: String { get { str("city") } set { set("city", newValue) } }
}

public struct StatementLine: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }
    public init(week: Int, day: Int, amount: Double, label: String, companyID: Int, balanceAfter: Double) {
        raw = ["w": .number(Double(week)), "d": .number(Double(day)), "a": .number(amount), "l": .string(label), "co": .number(Double(companyID)), "bal": .number(balanceAfter)]
    }
    public var week: Int { int("w") }
    public var day: Int { int("d") }
    public var amount: Double { num("a") }
    public var label: String { str("l") }
    public var companyID: Int { int("co") }
    public var balanceAfter: Double { num("bal") }
}

public struct Message: JSONRecord, Identifiable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var id: Int { get { int("id") } set { set("id", newValue) } }
    public var kind: String { get { str("kind", "info") } set { set("kind", newValue) } }
    public var from: String { get { str("from") } set { set("from", newValue) } }
    public var title: String { get { str("title") } set { set("title", newValue) } }
    public var body: String { get { str("body") } set { set("body", newValue) } }
    public var companyID: Int { get { int("co") } set { set("co", newValue) } }
    public var tone: String { get { str("tone", "n") } set { set("tone", newValue) } }
    public var status: String { get { str("status", "done") } set { set("status", newValue) } }
    public var isRead: Bool { get { flag("read") } set { set("read", newValue) } }
    public var week: Int { get { int("w") } set { set("w", newValue) } }
    public var expiresWeek: Int? { get { value("exp").isNull ? nil : int("exp") } set { raw["exp"] = newValue.map { .number(Double($0)) } ?? .null } }
    public var actionID: String { get { str("act") } set { set("act", newValue) } }
    public var handledBy: String { get { str("by") } set { set("by", newValue) } }
    public var appLink: String { get { str("ap") } set { set("ap", newValue) } }
    public var isAlert: Bool { get { flag("alert") } set { set("alert", newValue) } }
    public var sev: Int { get { int("sev") } set { set("sev", newValue) } }
    public var audience: String { get { str("aud") } set { set("aud", newValue) } }
    public var isOwnerAddressed: Bool { audience.isEmpty || audience == "owner" }
    public var severity: Int {
        if isAlert { return 4 }
        if sev > 0 { return sev }
        if (kind == "ask" || kind == "decision") && status == "open" { return 3 }
        return tone == "bad" ? 2 : 1
    }
    public var options: [JSONValue] { value("opts").array }
    public var doc: InboxDocument? {
        get { let d = value("doc"); return d.isNull ? nil : InboxDocument(json: d) }
        set { raw["doc"] = newValue?.json ?? .null }
    }
}

public struct InboxDocument: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var label: String
        public var value: Double
        public init(label: String, value: Double) { self.label = label; self.value = value }
    }
    public struct Section: Equatable, Sendable {
        public var heading: String
        public var lines: [String]
        public var points: [Point]
        public init(heading: String, lines: [String], points: [Point] = []) { self.heading = heading; self.lines = lines; self.points = points }
    }
    public var title: String
    public var issuer: String
    public var date: String
    public var reference: String
    public var sections: [Section]
    public init(title: String, issuer: String, date: String, reference: String, sections: [Section]) {
        self.title = title; self.issuer = issuer; self.date = date; self.reference = reference; self.sections = sections
    }
    init(json d: JSONValue) {
        title = d["title"].string; issuer = d["issuer"].string; date = d["date"].string; reference = d["ref"].string
        sections = d["sections"].array.map { sec in
            Section(heading: sec["h"].string, lines: sec["lines"].array.map { $0.string },
                    points: sec["pts"].array.map { Point(label: $0["l"].string, value: $0["v"].double) })
        }
    }
    var json: JSONValue {
        .object(["title": .string(title), "issuer": .string(issuer), "date": .string(date), "ref": .string(reference),
                 "sections": .array(sections.map { sec in
                     var o: [String: JSONValue] = ["h": .string(sec.heading), "lines": .array(sec.lines.map { .string($0) })]
                     if !sec.points.isEmpty { o["pts"] = .array(sec.points.map { .object(["l": .string($0.label), "v": .number($0.value)]) }) }
                     return .object(o)
                 })])
    }
}
