import Foundation

public struct GameState: Codable, Equatable, Sendable {
    public static let legacyVersion = 5

    public var version: Int
    public var seed: Int
    public var random: DeterministicRandom
    public var nextID: Int
    public var week: Int
    public var day: Int
    public var homeCountryCode: String
    public var player: Player
    public package(set) var cash: Double { didSet { if cash != oldValue { mirrorCash() } } }
    public var openingCash: Double
    public var cashFlow: [String: Double]
    public var loans: [Loan]
    public var credit: Double
    public var overdraftLimit: Double
    public var companies: [Company]
    public var people: [Int: Person]
    public var inbox: [Message]
    public var economy: Economy
    public var tax: PersonalTaxYear
    public var stats: GameStats
    public var statement: [StatementLine]
    public var exchangeRates: ExchangeDrift
    public var netWorthHistory: [Double]
    public var gameOver: JSONValue
    public var transient = Transient()
    public var rest: [String: JSONValue]

    public struct Transient: Equatable, Sendable {
        public var simulatingWeek = false
        public var stagedPlayerLines: [StatementLine]? = nil
        public init() {}
    }

    public struct ExchangeDrift: Equatable, Sendable {
        public var values: [String: Double]
        public init(_ values: [String: Double] = [:]) { self.values = values }
    }

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
        // Older saves keep an unrelated object under "pool"; only the flag written by encode marks a one-account save.
        let pooled = take("pool") == .bool(true)
        // Savings were a second pocket once; a balance still sitting in an old save is paid into the account.
        let oldSavings = max(0, take("sav")["bal"].double)
        var playerRaw: [String: JSONValue] = take("player").object
        playerRaw.removeValue(forKey: "age")
        player = Player(raw: playerRaw)
        cash = take("cash").double
        openingCash = take("cash0").double
        cashFlow = take("flow").object.mapValues { $0.double }
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
        if !pooled { cash += companies.reduce(0) { $0 + $1.cash } }
        if oldSavings > 0 { cash += oldSavings; openingCash += oldSavings }
        dissolveHoldings()
        dropFinanceManagers()
        mirrorCash()
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
        o["pool"] = .bool(true)
        o["cash0"] = .number(openingCash)
        o["flow"] = .object(cashFlow.mapValues { .number($0) })
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

    package mutating func mirrorCash() {
        for i in companies.indices { companies[i].cash = cash }
    }

    public func company(_ id: Int) -> Company? { companies.first { $0.id == id } }
    public func companyIndex(_ id: Int) -> Int? { companies.firstIndex { $0.id == id } }
    public var liveCompanies: [Company] { companies.filter { $0.status.isLive } }
    public func chainStores(of co: Company) -> [Company] {
        let id = co.value("chain")
        guard !id.isNull, (rest["chains"]?.array ?? []).contains(where: { $0["id"].int == id.int }) else { return [] }
        return companies.filter { $0.status.isLive && !$0.value("chain").isNull && $0.value("chain").int == id.int }
    }
    public func isBranch(_ co: Company) -> Bool { chainStores(of: co).count >= 2 }

    public mutating func makeID() -> Int {
        nextID += 1
        return nextID
    }

    public var isGameOver: Bool { !gameOver.isNull }

    public var dayMode: Bool {
        get { rest["dmode"]?.bool ?? false }
        set { rest["dmode"] = .number(newValue ? 1 : 0) }
    }

    public var exchangeRatesValue: [String: Double] { exchangeRates.values }
}
