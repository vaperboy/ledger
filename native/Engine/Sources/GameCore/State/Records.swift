import Foundation

/// A loan (start-up loan, business loan, mortgage ...). Original: `S.loans` entries.
public struct Loan: JSONRecord, Identifiable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var id: Int { get { int("id") } set { set("id", newValue) } }
    /// "start", "biz", "cons", "mort", "lomb"
    public var kind: String { get { str("kind") } set { set("kind", newValue) } }
    public var name: String { get { str("name") } set { set("name", newValue) } }
    /// Amount still owed.
    public var balance: Double { get { num("bal") } set { set("bal", newValue) } }
    public var originalAmount: Double { get { num("amt0") } set { set("amt0", newValue) } }
    /// Bank margin on top of the central bank's policy rate.
    public var margin: Double { get { num("margin") } set { set("margin", newValue) } }
    /// Monthly payment.
    public var monthlyPayment: Double { get { num("pay") } set { set("pay", newValue) } }
    public var termMonths: Int { get { int("termM") } set { set("termM", newValue) } }
    /// Company the loan belongs to; 0 = the player personally.
    public var companyID: Int { get { int("co") } set { set("co", newValue) } }
    public var startWeek: Int { get { int("w0") } set { set("w0", newValue) } }
    /// The owner has signed a personal guarantee.
    public var isGuaranteed: Bool { get { flag("guar") } set { set("guar", newValue) } }
    public var bankCompanyID: Int { get { int("bank") } set { set("bank", newValue) } }
    public var graceUntilWeek: Int { get { int("graceW") } set { set("graceW", newValue) } }
}

/// The economy: one set of numbers all companies feel. Original: `S.econ`.
public struct Economy: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    /// "boom", "steady", "slowdown" or "recession"
    public var phase: String { get { str("phase", "steady") } set { set("phase", newValue) } }
    public var weeksLeftInPhase: Int { get { int("left") } set { set("left", newValue) } }
    /// Demand index around 1.0. Original: `dem`.
    public var demand: Double { get { num("dem", 1) } set { set("dem", newValue) } }
    public var inflation: Double { get { num("infl", 0.03) } set { set("infl", newValue) } }
    /// Cumulative price level since the game began (1 at the start). Grows every week by the inflation of that week (`WorldWeek.economy`), so
    /// a change in the rate moves prices from then on and never rewrites the past. Every price that follows inflation reads this.
    public var inflationIndex: Double { get { num("ix", 1) } set { set("ix", newValue) } }
    public var fuel: Double { get { num("fuel", 1) } set { set("fuel", newValue) } }
    public var materials: Double { get { num("mat", 1) } set { set("mat", newValue) } }
    public var power: Double { get { num("power", 1) } set { set("power", newValue) } }
    public var oil: Double { get { num("oil", 1) } set { set("oil", newValue) } }
    public var housing: Double { get { num("housing", 1) } set { set("housing", newValue) } }
    /// Central bank policy rate.
    public var policyRate: Double { get { num("rate", 0.0375) } set { set("rate", newValue) } }
    public var freight: Double { get { num("freight", 1) } set { set("freight", newValue) } }
    public var salmon: Double { get { num("salmon", 1) } set { set("salmon", newValue) } }
}

/// The player's personal tax year so far. Original: `S.tax`.
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
    /// Tax already paid this year on dividends, gains, interest and wealth as they arose; the year-end true-up settles the difference.
    public var paidDividend: Double { get { num("pDiv") } set { set("pDiv", newValue) } }
    public var paidGains: Double { get { num("pGain") } set { set("pGain", newValue) } }
    public var paidInterest: Double { get { num("pInt") } set { set("pInt", newValue) } }
    public var paidWealth: Double { get { num("pWealth") } set { set("pWealth", newValue) } }
}

/// Lifetime statistics. Original: `S.stats`.
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

/// The player. Original: `S.player`.
public struct Player: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var name: String { get { str("name", "You") } set { set("name", newValue) } }
    public var cityID: String { get { str("city") } set { set("city", newValue) } }
}

/// One line on the player's private statement. Original: `S.log` entries, newest first.
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

/// An inbox message: news, an alert, or a decision with options. Original: `S.inbox` entries, newest first.
public struct Message: JSONRecord, Identifiable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var id: Int { get { int("id") } set { set("id", newValue) } }
    /// "info" (read-only) or "ask" (needs a decision)
    public var kind: String { get { str("kind", "info") } set { set("kind", newValue) } }
    public var from: String { get { str("from") } set { set("from", newValue) } }
    public var title: String { get { str("title") } set { set("title", newValue) } }
    public var body: String { get { str("body") } set { set("body", newValue) } }
    public var companyID: Int { get { int("co") } set { set("co", newValue) } }
    /// "good", "bad" or "n" (neutral)
    public var tone: String { get { str("tone", "n") } set { set("tone", newValue) } }
    /// "open" (waiting for an answer) or "done"
    public var status: String { get { str("status", "done") } set { set("status", newValue) } }
    public var isRead: Bool { get { flag("read") } set { set("read", newValue) } }
    public var week: Int { get { int("w") } set { set("w", newValue) } }
    /// The week the offer expires, if it does.
    public var expiresWeek: Int? { get { value("exp").isNull ? nil : int("exp") } set { raw["exp"] = newValue.map { .number(Double($0)) } ?? .null } }
    public var actionID: String { get { str("act") } set { set("act", newValue) } }
    /// A red alert (a company about to be force-sold): the app shows it as a see-through red popup that only its button closes.
    /// Who handled it when a hired rank took the decision for the owner ("Mia, manager"); empty when the owner answered or it is still open.
    public var handledBy: String { get { str("by") } set { set("by", newValue) } }
    /// The Phone app (`PhoneApp` raw value) a message with no company opens: atlas, bank, accounting, weather. Empty when it has none. Absent in older saves.
    public var appLink: String { get { str("ap") } set { set("ap", newValue) } }
    public var isAlert: Bool { get { flag("alert") } set { set("alert", newValue) } }
    /// Severity a producer gave (1 routine, 2 attention, 3 decision, 4 critical); 0 when absent (older saves, producers that leave it to the classifier).
    public var sev: Int { get { int("sev") } set { set("sev", newValue) } }
    /// The desk a notice is addressed to: "finance", "hr", "ops", "sales" or "owner". Empty means the owner. Absent in older saves.
    public var audience: String { get { str("aud") } set { set("aud", newValue) } }
    public var isOwnerAddressed: Bool { audience.isEmpty || audience == "owner" }
    /// How serious the message is: a red alert is critical, a producer's own value wins, else an open decision is a 3, bad news a 2 and the rest routine.
    public var severity: Int {
        if isAlert { return 4 }
        if sev > 0 { return sev }
        if (kind == "ask" || kind == "decision") && status == "open" { return 3 }
        return tone == "bad" ? 2 : 1
    }
    public var options: [JSONValue] { value("opts").array }
    /// A structured document (a report, a disclosure result) carried by the message, kind "doc". Absent in older saves. The plain `body` stays as the fallback summary.
    public var doc: InboxDocument? {
        get { let d = value("doc"); return d.isNull ? nil : InboxDocument(json: d) }
        set { raw["doc"] = newValue?.json ?? .null }
    }
}

/// A document delivered to the inbox: title, issuer, date, reference number and sections of lines (each section may carry figure points for a small chart).
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
