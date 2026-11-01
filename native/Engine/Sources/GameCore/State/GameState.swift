import Foundation

/// Everything that makes up one game in progress. Original: the global `S`.
///
/// The Swift game owns the parts it has been rewritten for (typed properties below). Everything else in a
/// save, for example features that are not rewritten yet, lives in `rest` and is written back untouched, so a
/// save always round-trips without losing a field.
public struct GameState: Codable, Equatable, Sendable {
    /// Save format version of the ORIGINAL game this state follows (its `VERSION`).
    public static let legacyVersion = 5

    public var version: Int
    public var seed: Int
    public var random: DeterministicRandom
    /// Counter for unique ids of companies, people, loans ... Original: `uid`.
    public var nextID: Int
    public var week: Int
    /// Day within the week, 0 = Monday ... 6 = Sunday. Original: `day`.
    public var day: Int
    public var homeCountryCode: String
    public var player: Player
    /// The player's private current account. Never change directly: use `Ledger.move`.
    public var cash: Double
    /// The starting loan amount; the ledger check compares against it. Original: `cash0`.
    public var openingCash: Double
    /// Sum of everything booked to each cash holder ("me", "co<id>"). Lets tests prove cash equals what was booked.
    public var cashFlow: [String: Double]
    public var savings: Double
    public var loans: [Loan]
    /// 0-100 credit score.
    public var credit: Double
    public var overdraftLimit: Double
    public var companies: [Company]
    /// People on the labour market and on payrolls, by id. Original: `npcs`.
    public var people: [Int: Person]
    public var inbox: [Message]
    public var economy: Economy
    public var tax: PersonalTaxYear
    public var stats: GameStats
    public var statement: [StatementLine]
    public var exchangeRates: ExchangeDrift
    public var netWorthHistory: [Double]
    public var gameOver: JSONValue
    /// Values that exist only while the game runs and are never saved.
    public var transient = Transient()
    /// Everything else in the save, untouched.
    public var rest: [String: JSONValue]

    public struct Transient: Equatable, Sendable {
        /// True while a whole week is being worked out (monthly bills then build up instead of being paid at once).
        public var simulatingWeek = false
        /// While set, the player's payments wait here and land on their own day of the week. Original: `S.stage`.
        public var stagedPlayerLines: [StatementLine]? = nil
        public init() {}
    }

    public struct ExchangeDrift: Equatable, Sendable {
        public var values: [String: Double]
        public init(_ values: [String: Double] = [:]) { self.values = values }
    }

    // MARK: Codable (legacy key names)

    public init(from decoder: Decoder) throws {
        var o = try decoder.singleValueContainer().decode([String: JSONValue].self)
        func take(_ k: String) -> JSONValue { o.removeValue(forKey: k) ?? .null }
        version = take("v").int
        seed = take("seed").int
        random = DeterministicRandom(state: Int32(truncatingIfNeeded: take("rs").int))
        nextID = take("uid").int
        week = take("week").int
        day = take("day").int
        homeCountryCode = take("country").string
        player = Player(raw: take("player").object)
        cash = take("cash").double
        openingCash = take("cash0").double
        cashFlow = take("flow").object.mapValues { $0.double }
        savings = take("sav")["bal"].double
        loans = take("loans").array.map { Loan(raw: $0.object) }
        credit = take("credit").double
        overdraftLimit = take("overdraftLimit").double
        companies = take("cos").array.map { Company(raw: $0.object) }
        var ppl: [Int: Person] = [:]
        for (k, v) in take("npcs").object { if let id = Int(k) { ppl[id] = Person(raw: v.object) } }
        people = ppl
        inbox = take("inbox").array.map { Message(raw: $0.object) }
        economy = Economy(raw: take("econ").object)
        tax = PersonalTaxYear(raw: take("tax").object)
        stats = GameStats(raw: take("stats").object)
        statement = take("log").array.map { StatementLine(raw: $0.object) }
        exchangeRates = ExchangeDrift(take("fxd").object.mapValues { $0.double })
        netWorthHistory = take("hist")["nw"].array.map { $0.double }
        let histRest = take("hist").object.filter { $0.key != "nw" }
        gameOver = take("over")
        rest = o
        if !histRest.isEmpty { rest["hist"] = .object(histRest) }
    }

    public func encode(to encoder: Encoder) throws {
        var o = rest
        var hist = o["hist"]?.object ?? [:]
        hist["nw"] = .array(netWorthHistory.map { .number($0) })
        if hist["cash"] == nil { hist["cash"] = .array([]) }
        o["hist"] = .object(hist)
        o["v"] = .number(Double(version))
        o["seed"] = .number(Double(seed))
        o["rs"] = .number(Double(random.state))
        o["uid"] = .number(Double(nextID))
        o["week"] = .number(Double(week))
        o["day"] = .number(Double(day))
        o["country"] = .string(homeCountryCode)
        o["player"] = .object(player.raw)
        o["cash"] = .number(cash)
        o["cash0"] = .number(openingCash)
        o["flow"] = .object(cashFlow.mapValues { .number($0) })
        o["sav"] = .object(["bal": .number(savings)])
        o["loans"] = .array(loans.map { .object($0.raw) })
        o["credit"] = .number(credit)
        o["overdraftLimit"] = .number(overdraftLimit)
        o["cos"] = .array(companies.map { .object($0.raw) })
        var ppl: [String: JSONValue] = [:]
        for (k, v) in people { ppl[String(k)] = .object(v.raw) }
        o["npcs"] = .object(ppl)
        o["inbox"] = .array(inbox.map { .object($0.raw) })
        o["econ"] = .object(economy.raw)
        o["tax"] = .object(tax.raw)
        o["stats"] = .object(stats.raw)
        o["log"] = .array(statement.map { .object($0.raw) })
        o["fxd"] = .object(exchangeRates.values.mapValues { .number($0) })
        o["over"] = gameOver
        var c = encoder.singleValueContainer()
        try c.encode(o)
    }

    // MARK: Helpers

    public func company(_ id: Int) -> Company? { companies.first { $0.id == id } }
    public func companyIndex(_ id: Int) -> Int? { companies.firstIndex { $0.id == id } }
    public var liveCompanies: [Company] { companies.filter { $0.status.isLive } }

    /// A fresh unique id. Original: `uid()`.
    public mutating func makeID() -> Int {
        nextID += 1
        return nextID
    }

    public var isGameOver: Bool { !gameOver.isNull }

    /// The game is played day by day (the normal way): recurring costs are billed monthly. Original: `S.dmode`.
    public var dayMode: Bool {
        get { rest["dmode"]?.bool ?? false }
        set { rest["dmode"] = .number(newValue ? 1 : 0) }
    }

    public var exchangeRatesValue: [String: Double] { exchangeRates.values }
}
