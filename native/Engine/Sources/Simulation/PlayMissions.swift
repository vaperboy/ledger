import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Daily, weekly and monthly missions. Each player gets their own draw from long pools, seeded by player and server day,
/// so two players differ and one player gets the same set all day. Progress is read straight from the game's own books and counters.
public enum PlayMissions {
    public enum Period: String, CaseIterable, Sendable {
        case day, week, season

        public var days: Int { self == .day ? 1 : (self == .week ? 7 : 30) }
        public var easyCount: Int { self == .day ? 4 : (self == .week ? 3 : 2) }
        public var hardCount: Int { 1 }
        var storeKey: String { self == .day ? "d" : (self == .week ? "w" : "s") }
        var poolKey: String { self == .day ? "daily" : (self == .week ? "weekly" : "season") }
        public var label: String { self == .day ? "Today" : (self == .week ? "This week" : "This month") }
        /// Missions that are done and not yet claimed stay claimable this many sets back.
        static let carryLimit = 12
    }

    public enum Tier: String, Sendable { case easy, hard }

    struct Def: Equatable {
        var id: String
        var tier: Tier
        var metric: String
        var scope: String
        var target: Double
        var days: Double
        var minutes: Int
        var title: String
        var trades: [String]
        var families: [String]
        var features: [String]
        var states: [String]
    }

    static let file: JSONValue = ContentFile.load("season", "mission_pool")

    static func parse(_ e: JSONValue) -> Def? {
        guard let tier = Tier(rawValue: e["tier"].string), !e["id"].string.isEmpty else { return nil }
        func list(_ k: String) -> [String] { e["needs"][k].array.map { (v: JSONValue) -> String in v.string } }
        return Def(id: e["id"].string, tier: tier, metric: e["metric"].string, scope: e["scope"].string.isEmpty ? "all" : e["scope"].string,
                   target: e["target"].double, days: e["days"].double, minutes: max(1, e["minutes"].int), title: e["title"].string,
                   trades: list("trade"), families: list("family"), features: list("feature"), states: list("state"))
    }

    static let pools: [Period: [Def]] = {
        var out: [Period: [Def]] = [:]
        for p in Period.allCases { out[p] = file[p.poolKey].array.compactMap { (e: JSONValue) -> Def? in PlayMissions.parse(e) } }
        return out
    }()

    static func pool(_ p: Period) -> [Def] { pools[p] ?? [] }
    public static func poolSize(_ p: Period) -> Int { pool(p).count }

    // MARK: Rewards, scaled by how long the mission should take

    public static func rewardXP(minutes: Int) -> Int { 10 + Int((Double(minutes) * 1.2).rounded()) }
    public static func rewardGold(minutes: Int) -> Int { max(1, minutes / 30) }
    public static func rewardCash(minutes: Int, _ cur: Currency) -> Double { jsRound(cur.scaledPrice(150 + Double(minutes) * 25)) }

    // MARK: Readings

    static let downMetrics: Set<String> = ["loans", "recv", "cmp"]

    static func openCompanies(_ s: GameState) -> [Company] { s.companies.filter { (c: Company) -> Bool in c.status == .open } }

    static func scoped(_ s: GameState, _ data: GameData, _ scope: String) -> [Company] {
        let all: [Company] = openCompanies(s)
        if scope.hasPrefix("trade:") {
            let id: String = String(scope.dropFirst(6))
            return all.filter { (c: Company) -> Bool in c.type == id }
        }
        if scope.hasPrefix("family:") {
            let f: String = String(scope.dropFirst(7))
            return all.filter { (c: Company) -> Bool in data.catalog[c.type]?.family == f }
        }
        return all
    }

    static func daysTrading(_ s: GameState, _ c: Company) -> Double {
        let from: Int = c.openedWeek ?? c.foundedWeek
        return Double(max(0, s.week - from) * 7 + s.day)
    }

    /// What one normal day brings in for these companies: their own average once they have traded a week, a plain guess before that.
    static func dailyTakings(_ s: GameState, _ data: GameData, _ scope: String) -> Double {
        var sum: Double = 0
        for c in scoped(s, data, scope) {
            let d: Double = daysTrading(s, c)
            let rev: Double = c.books.total["rev"] ?? 0
            if d >= 7, rev > 0 { sum += rev / d } else { sum += (data.catalog[c.type]?.ticket ?? 0) * 6 }
        }
        return sum
    }

    static func dailyProfit(_ s: GameState, _ data: GameData, _ scope: String) -> Double {
        var sum: Double = 0
        for c in scoped(s, data, scope) {
            let d: Double = daysTrading(s, c)
            if d >= 7 { sum += Books.profit(c.books.total) / d }
        }
        return sum
    }

    static func reading(_ key: String, _ s: GameState, _ data: GameData) -> Double {
        let parts: [String] = key.split(separator: "|", maxSplits: 1).map { (p: Substring) -> String in String(p) }
        let metric: String = parts.first ?? ""
        let scope: String = parts.count > 1 ? parts[1] : "all"
        switch metric {
        case "advance", "decision", "event", "answered": return Double(PassMissions.counters(s)[metric] ?? 0)
        case "weeks": return Double(s.week)
        case "rev": return scoped(s, data, scope).reduce(0) { (n: Double, c: Company) -> Double in n + (c.books.total["rev"] ?? 0) }
        case "profit": return scoped(s, data, scope).reduce(0) { (n: Double, c: Company) -> Double in n + Books.profit(c.books.total) }
        case "mkt": return scoped(s, data, scope).reduce(0) { (n: Double, c: Company) -> Double in n + (c.books.total["mkt"] ?? 0) }
        case "hire": return Double(scoped(s, data, scope).reduce(0) { (n: Int, c: Company) -> Int in n + c.staff.count })
        case "mgr": return Double(openCompanies(s).filter { (c: Company) -> Bool in c.managerID != nil }.count)
        case "cos": return Double(openCompanies(s).count)
        case "loans": return Double(s.loans.count)
        case "recv": return Double(openCompanies(s).reduce(0) { (n: Int, c: Company) -> Int in n + c.receivables.count })
        case "cmp": return Double(PlayerGoals.openComplaints(s))
        case "nw": return Valuation.netWorth(s, trades: data.catalog).total
        default: return 0
        }
    }

    // MARK: What a player can be given

    static func fits(_ d: Def, _ s: GameState, _ data: GameData, live: [Company]) -> Bool {
        if live.isEmpty { return false }
        if !d.trades.isEmpty, !live.contains(where: { (c: Company) -> Bool in d.trades.contains(c.type) }) { return false }
        if !d.families.isEmpty, !live.contains(where: { (c: Company) -> Bool in d.families.contains(data.catalog[c.type]?.family ?? "") }) { return false }
        for f in d.features {
            guard let feature = LevelFeature(rawValue: f), FeatureUnlocks.isUnlocked(feature, s) else { return false }
        }
        for st in d.states {
            switch st {
            case "profit": if dailyProfit(s, data, d.scope) <= 0 { return false }
            case "cmp": if PlayerGoals.openComplaints(s) == 0 { return false }
            case "recv": if reading("recv", s, data) == 0 { return false }
            case "loans": if s.loans.isEmpty { return false }
            case "nw": if Valuation.netWorth(s, trades: data.catalog).total <= 0 { return false }
            default: return false
            }
        }
        return true
    }

    /// Every mission this player could be given today.
    static func available(_ p: Period, _ s: GameState, _ data: GameData) -> [Def] {
        let live: [Company] = openCompanies(s)
        return pool(p).filter { (d: Def) -> Bool in fits(d, s, data, live: live) }
    }

    // MARK: Seeded draw

    struct Rng {
        var x: UInt64
        init(_ text: String) {
            var h: UInt64 = 0xcbf29ce484222325
            for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            x = h
        }
        mutating func next() -> UInt64 {
            x = x &+ 0x9e3779b97f4a7c15
            var z: UInt64 = x
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
    }

    static func shuffled(_ list: [Def], _ rng: inout Rng) -> [Def] {
        var a: [Def] = list.sorted { (x: Def, y: Def) -> Bool in x.id < y.id }
        if a.count > 1 {
            for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, rng.below(i + 1)) }
        }
        return a
    }

    /// The missions for one period: easy ones first, then the hard one, no two on the same kind of task while there is a choice.
    static func draw(_ p: Period, _ s: GameState, _ data: GameData, index: Int, key: String) -> [Def] {
        var rng = Rng("\(key)|\(p.rawValue)|\(index)")
        let avail: [Def] = available(p, s, data)
        var chosen: [Def] = []
        func take(_ tier: Tier, _ count: Int) {
            let list: [Def] = shuffled(avail.filter { (d: Def) -> Bool in d.tier == tier }, &rng)
            var used: Set<String> = Set(chosen.map { (d: Def) -> String in d.metric })
            var got: Int = 0
            for d in list where got < count && !used.contains(d.metric) {
                chosen.append(d); used.insert(d.metric); got += 1
            }
            for d in list where got < count && !chosen.contains(d) {
                chosen.append(d); got += 1
            }
        }
        take(.easy, p.easyCount)
        take(.hard, p.hardCount)
        return chosen
    }

    static func tidy(_ x: Double) -> Double {
        guard x.isFinite, x > 0 else { return 1 }
        let p: Double = pow(10, floor(log10(x)) - 1)
        return max(1, (x / p).rounded() * p)
    }

    static func entry(_ d: Def, _ s: GameState, _ data: GameData, _ cur: Currency) -> JSONValue {
        let rk: String = d.metric + "|" + d.scope
        var target: Double = d.target
        var title: String = d.title
        switch d.metric {
        case "rev": target = tidy(d.days * dailyTakings(s, data, d.scope))
        case "profit": target = tidy(d.days * dailyProfit(s, data, d.scope) * 0.6)
        case "nw": target = tidy(max(0, Valuation.netWorth(s, trades: data.catalog).total) * d.target / 100)
        default: break
        }
        if title.contains("{amt}") { title = title.replacingOccurrences(of: "{amt}", with: cur.display(target)) }
        return .object(["id": .string(d.id), "t": .string(d.tier.rawValue), "rk": .string(rk), "n": .number(target), "x": .number(0),
                        "b": .number(reading(rk, s, data)), "ti": .string(title), "mn": .number(Double(d.minutes)), "c": .number(0)])
    }

    // MARK: Store

    public static let storeKey = "msn"

    static func isDone(_ e: JSONValue) -> Bool { e["n"].double > 0 && e["x"].double >= e["n"].double }

    /// Draws a new set when the day, week or month has turned, and moves progress forward from the game's readings.
    public static func sync(_ s: inout GameState, data: GameData, currency cur: Currency, today: Int, key: String? = nil, now: Date = Date()) {
        guard Tutorial.isComplete(s), !openCompanies(s).isEmpty else { return }
        var root: JSONValue = s.rest[storeKey] ?? .object([:])
        let who: String = key ?? (root["pk"].string.isEmpty ? String(s.seed) : root["pk"].string)
        if root["pk"].string != who { root["pk"] = .string(who) }
        for p in Period.allCases {
            let idx: Int = today / p.days
            var set: JSONValue = root[p.storeKey]
            if set.isNull || set["i"].int != idx {
                let old: [JSONValue] = set["l"].array + set["k"].array
                let carry: [JSONValue] = old.filter { (e: JSONValue) -> Bool in isDone(e) && e["c"].int == 0 }.suffix(Period.carryLimit).map { (e: JSONValue) -> JSONValue in e }
                let picked: [JSONValue] = draw(p, s, data, index: idx, key: who).map { (d: Def) -> JSONValue in entry(d, s, data, cur) }
                set = .object(["i": .number(Double(idx)), "l": .array(picked), "k": .array(carry)])
            }
            var list: [JSONValue] = set["l"].array
            for i in list.indices where !isDone(list[i]) {
                let rk: String = list[i]["rk"].string
                let r: Double = reading(rk, s, data)
                let metric: String = String(rk.split(separator: "|").first ?? "")
                let delta: Double = downMetrics.contains(metric) ? list[i]["b"].double - r : r - list[i]["b"].double
                let n: Double = list[i]["n"].double
                list[i]["x"] = .number(min(n, max(list[i]["x"].double, delta)))
            }
            set["l"] = .array(list)
            root[p.storeKey] = set
        }
        if root[Period.day.storeKey]["l"].array.filter({ (e: JSONValue) -> Bool in isDone(e) }).count >= streakNeeds { countStreak(&s, now: now) }
        if s.rest[storeKey] != root { s.rest[storeKey] = root }
    }

    /// Daily missions that keep the day streak alive.
    public static let streakNeeds = 2

    static func countStreak(_ s: inout GameState, now: Date) {
        let today: String = GameEngine.dayString(now)
        let yesterday: String = GameEngine.dayString(now.addingTimeInterval(-86400))
        var d: JSONValue = s.rest["dy59"] ?? .object(["streak": 0, "last": ""])
        if d["last"].string == today { return }
        let live = PlayerGoals.streakNow(d, today: today, yesterday: yesterday)
        var streak: Int = live.count
        if live.protected {
            d["prot"] = .number(Double(max(0, d["prot"].int - 1)))
            s.note("Your streak protection kept the \(streak)-day streak alive.", tone: "good")
        }
        streak += 1
        d["streak"] = .number(Double(streak)); d["last"] = .string(today); d["d"] = .string(today); d["got"] = 1; d["cl"] = .string(today)
        if streak > d["best"].int { d["best"] = .number(Double(streak)) }
        PlayerGoals.grantStreakPerks(&s, &d, streak: streak)
        s.rest["dy59"] = d
    }

    // MARK: Reads

    public struct Entry: Equatable, Sendable, Identifiable {
        public var period: Period
        public var missionID: String
        public var tier: Tier
        public var title: String
        public var minutes: Int
        public var progress: Double
        public var target: Double
        public var claimed: Bool
        public var carried: Bool
        public var xp: Int
        public var cash: Double
        public var gold: Int
        public var id: String { period.rawValue + ":" + missionID }
        public var done: Bool { target > 0 && progress >= target }
        public var ready: Bool { done && !claimed }
        public var fraction: Double { target > 0 ? min(1, max(0, progress / target)) : 0 }
    }

    static func view(_ e: JSONValue, _ p: Period, carried: Bool, _ cur: Currency) -> Entry {
        let mins: Int = max(1, e["mn"].int)
        return Entry(period: p, missionID: e["id"].string, tier: Tier(rawValue: e["t"].string) ?? .easy, title: e["ti"].string, minutes: mins,
                     progress: e["x"].double, target: e["n"].double, claimed: e["c"].int != 0, carried: carried,
                     xp: rewardXP(minutes: mins), cash: rewardCash(minutes: mins, cur), gold: rewardGold(minutes: mins))
    }

    /// This period's missions (easy first, then hard), preceded by finished ones from earlier sets that were never claimed.
    public static func entries(_ s: GameState, _ p: Period, today: Int, currency cur: Currency) -> [Entry] {
        let set: JSONValue = (s.rest[storeKey] ?? .null)[p.storeKey]
        guard !set.isNull else { return [] }
        let carried: [Entry] = set["k"].array.filter { (e: JSONValue) -> Bool in e["c"].int == 0 }.map { (e: JSONValue) -> Entry in view(e, p, carried: true, cur) }
        guard set["i"].int == today / p.days else { return carried }
        return carried + set["l"].array.map { (e: JSONValue) -> Entry in view(e, p, carried: false, cur) }
    }

    public static func ready(_ s: GameState, today: Int, currency cur: Currency) -> [Entry] {
        Period.allCases.flatMap { (p: Period) -> [Entry] in entries(s, p, today: today, currency: cur).filter { (e: Entry) -> Bool in e.ready } }
    }

    // MARK: Claim

    public enum Result: Equatable, Sendable {
        case claimed(title: String, xp: Int, cash: Double, gold: Int)
        case notReady
    }

    /// Pays a finished mission once: level XP, cash into the one account, and the gold amount for the app to credit.
    @discardableResult
    public static func claim(_ s: inout GameState, period p: Period, id: String, currency cur: Currency) -> Result {
        var root: JSONValue = s.rest[storeKey] ?? .null
        var set: JSONValue = root[p.storeKey]
        for field in ["l", "k"] {
            var list: [JSONValue] = set[field].array
            guard let i = list.firstIndex(where: { (e: JSONValue) -> Bool in e["id"].string == id }) else { continue }
            guard isDone(list[i]), list[i]["c"].int == 0 else { return .notReady }
            let mins: Int = max(1, list[i]["mn"].int)
            let title: String = list[i]["ti"].string
            list[i]["c"] = .number(1)
            set[field] = .array(list)
            root[p.storeKey] = set
            s.rest[storeKey] = root
            let xp: Int = rewardXP(minutes: mins)
            PlayerLevel.award(&s, xp)
            let cash: Double = rewardCash(minutes: mins, cur)
            if cash > 0 { Ledger.move(&s, .me, cash, why: "Mission reward: " + title) }
            return .claimed(title: title, xp: xp, cash: cash, gold: rewardGold(minutes: mins))
        }
        return .notReady
    }
}

public extension GameEngine {
    /// Draws today's missions when they are due and updates progress. Safe to call as often as needed.
    mutating func syncMissions(key: String? = nil, now: Date = Date()) {
        let day: Int = SeasonCatalog.today()
        update { s, d, ctx in PlayMissions.sync(&s, data: d, currency: ctx.homeCurrency(s), today: day, key: key, now: now) }
    }

    func missionEntries(_ p: PlayMissions.Period) -> [PlayMissions.Entry] {
        PlayMissions.entries(state, p, today: SeasonCatalog.today(), currency: homeCurrency)
    }

    var missionsReady: [PlayMissions.Entry] { PlayMissions.ready(state, today: SeasonCatalog.today(), currency: homeCurrency) }

    @discardableResult
    mutating func claimMission(_ p: PlayMissions.Period, id: String) -> PlayMissions.Result {
        var r: PlayMissions.Result = .notReady
        update { s, _, ctx in r = PlayMissions.claim(&s, period: p, id: id, currency: ctx.homeCurrency(s)) }
        return r
    }
}
