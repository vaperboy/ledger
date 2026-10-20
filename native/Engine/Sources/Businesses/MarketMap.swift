import Foundation
import GameCore
import Countries

/// The market map: your share of each market you are in, worked out from sales against what each rival sells there (banks, insurers
/// and funds against the whole country). What you SEE depends on who is looking: nobody (only a feeling, in words), a head-office
/// data analyst (ranges, sharper with experience) or a market analyst in the company (close numbers, a report every month).
/// Original: features/world/market_map_and_reviews.js (`markets`, `truthOf`, `know`, `est`, `snap`, `reportLines`).
/// Not ported: the analyst roles are not hireable in the native game yet, so everyone is at the first level for now; the economy
/// "weight" block (share of business loans, jobs, regulator attention).
public enum MarketMap {
    public enum Kind: String { case local, national }

    public struct Market: Identifiable, Equatable {
        public var id: String            // the market key
        public var kind: Kind
        public var type: String
        public var cityID: String
        public var countryCode: String
        public var companyIDs: [Int]
    }

    public struct Player: Identifiable, Equatable {
        public var id: String
        public var name: String
        public var revenue: Double
        public var share: Double
        public var rivalID: Int?         // nil for national players, who are only names
    }

    public struct Truth: Equatable {
        public var mine: Double, total: Double, share: Double
        public var players: [Player]
    }

    static let national: [String: (label: String, noun: String, base: Double, word: String)] = [
        "bank": ("Bank deposits", "deposits", 450_000, "Bank"), "insco": ("Insurance", "premiums", 14_000, "Insurance"), "fund": ("Fund assets", "fund assets", 300_000, "Asset Management"),
    ]

    // MARK: Which markets

    public static func markets(_ s: GameState, data: GameData) -> [Market] {
        var by: [String: Market] = [:], order: [String] = []
        for co in s.companies where co.status == .open {
            guard let bd = data.catalog[co.type] else { continue }
            let k: String, kind: Kind
            if RivalGroups.localFamilies.contains(bd.family), bd.normalDemand > 0 { k = Rivals.key(co); kind = .local }
            else if national[co.type] != nil { k = "fin|\(co.type)|\(co.countryCode)"; kind = .national }
            else { continue }
            if by[k] == nil { by[k] = Market(id: k, kind: kind, type: co.type, cityID: co.cityID, countryCode: co.countryCode, companyIDs: []); order.append(k) }
            by[k]!.companyIDs.append(co.id)
        }
        return order.compactMap { by[$0] }
    }

    public static func market(of co: Company, _ s: GameState, data: GameData) -> Market? { markets(s, data: data).first { $0.companyIDs.contains(co.id) } }

    public static func label(_ m: Market, data: GameData, withCity: Bool) -> String {
        if m.kind == .national { return national[m.type]?.label ?? m.type }
        let city = data.countries.city(m.cityID, preferring: m.countryCode)?.city.name ?? m.cityID
        return (data.catalog[m.type]?.name ?? m.type) + (withCity ? " · " + city : "")
    }

    // MARK: Sales

    /// A company's sales in a year, from the last weeks. Original: `annRev`.
    public static func annualRevenue(_ co: Company) -> Double {
        let L = co.value("rv26").array
        if L.count >= 2 { return L.reduce(0) { $0 + $1.double } / Double(L.count) * 52 }
        let h = co.monthlyHistory.suffix(3)
        if !h.isEmpty { return h.reduce(0) { $0 + $1.revenue } / Double(h.count) * 12 }
        return co.lastWeekRevenue * 52
    }

    static func nationalTotal(_ m: Market, data: GameData) -> Double {
        let c = data.countries[m.countryCode] ?? data.countries.countries[0]
        return max(1, c.populationMillions * 1e6 * (national[m.type]?.base ?? 100_000) * pow(c.marketStrength, 2) * c.priceLevel)
    }

    static func size(_ co: Company) -> Double {
        let fm = co.value("fm")
        return co.type == "bank" ? fm["dep"].double : co.type == "fund" ? fm["aum"].double : annualRevenue(co)
    }

    /// The true picture of one market. Original: `truthOf`.
    public static func truth(_ s: GameState, _ m: Market, data: GameData) -> Truth {
        let cos = m.companyIDs.compactMap { s.company($0) }
        guard let co = cos.first else { return Truth(mine: 0, total: 1, share: 0, players: []) }
        let w = World(state: s, data: data)
        if m.kind == .local, let bd = w.trade(co) {
            let my = cos.reduce(0) { $0 + annualRevenue($1) }
            let riv = Rivals.rivals(s, for: co).map { r in Player(id: "r\(r.id)", name: r.name, revenue: Rivals.yearlyRevenue(bd, r, w, co), share: 0, rivalID: r.id) }
            let tot = my + riv.reduce(0) { $0 + $1.revenue }
            return Truth(mine: my, total: tot, share: tot > 0 ? my / tot : 0, players: riv.map { var p = $0; p.share = tot > 0 ? p.revenue / tot : 0; return p }.sorted { $0.revenue > $1.revenue })
        }
        let tot = nationalTotal(m, data: data)
        let my = min(tot * 0.95, cos.reduce(0) { $0 + size($1) })
        let c = data.countries[m.countryCode] ?? data.countries.countries[0]
        let rest = max(0, 1 - my / tot)
        let base = [0.31, 0.21, 0.14, 0.09]
        var players: [Player] = []
        for i in 0..<4 {
            var h = HashedRandom("\(s.seed):26f:\(m.type):\(m.countryCode):\(i)")
            var r = DeterministicRandom(seed: Int(h.next() * 1_000_000_000))
            let root = RivalGroups.brandRoot(c, family: "fin", &r)
            let sh = base[i] * (0.8 + h.next() * 0.4) * rest
            players.append(Player(id: "f\(m.type)\(m.countryCode)\(i)", name: root + " " + (national[m.type]?.word ?? "Group"), revenue: sh * tot, share: sh, rivalID: nil))
        }
        return Truth(mine: my, total: tot, share: my / tot, players: players)
    }

    /// Has a big player noticed you? A newcomer is invisible until it takes a real share. Original: `noticed`, `coShare`.
    static func noticed(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World) -> Bool {
        guard co.status == .open else { return false }
        let mine = annualRevenue(co)
        let theirs = Rivals.rivals(s, for: co).reduce(0) { $0 + Rivals.yearlyRevenue(bd, $1, w, co) }
        let sh = mine > 0 ? mine / (mine + theirs) : 0
        let age = s.week - (co.openedWeek ?? co.foundedWeek)
        return (age >= 26 && sh >= 0.12) || sh >= 0.22 || !co.value("flags")["pw"].isNull
    }

    // MARK: Who is looking

    public struct Knowledge: Equatable {
        public enum Level: Int { case feeling = 0, dataAnalyst = 1, marketAnalyst = 2 }
        public var level: Level
        public var skill: Double
        public var name: String
        public var id: String
        public init(level: Level, skill: Double, name: String, id: String) { self.level = level; self.skill = skill; self.name = name; self.id = id }
        /// Nobody is measuring: only a feeling.
        public static let nobody = Knowledge(level: .feeling, skill: 0, name: "", id: "me")
    }

    /// A market analyst in one of the companies, else the head office's data analyst, else only a feeling. Original: `know`, `mktanOf`.
    public static func knowledge(_ s: GameState, _ m: Market) -> Knowledge {
        for id in m.companyIDs {
            if let co = s.company(id), let st = co.staff.first(where: { $0.role == "mktan" }) {
                let p = s.people[st.id]
                return Knowledge(level: .marketAnalyst, skill: clamp((p?.value("skill").double ?? 55) / 100, 0.2, 0.98), name: p?.name ?? "Your market analyst", id: String(st.id))
            }
        }
        return dataAnalyst(s) ?? .nobody
    }

    /// The head office's data analyst, if there is one. Original: `anaInfo`.
    public static func dataAnalyst(_ s: GameState) -> Knowledge? {
        guard let st = (s.rest["office"]?["staff"].array ?? []).first(where: { $0["role"].string == "ana" }) else { return nil }
        let p = s.people[st["id"].int]
        return Knowledge(level: .dataAnalyst, skill: clamp((p?.value("skill").double ?? 55) / 100 + (p?.value("exp").double ?? 0) * 0.01, 0.2, 0.98), name: p?.name ?? "Your data analyst", id: String(st["id"].int))
    }

    public struct Estimate: Equatable {
        public var level: Knowledge.Level
        public var center: Double, low: Double, high: Double
    }

    /// A share (0...1) as the person looking sees it this month. Original: `est`.
    public static func estimate(_ v: Double, key: String, _ k: Knowledge, seed: Int, week: Int) -> Estimate {
        let mi = week / 4
        let a = HashedRandom.first("\(seed):26:\(key):\(mi):\(k.id)"), b = HashedRandom.first("\(seed):26:\(key)b:\(mi):\(k.id)")
        switch k.level {
        case .marketAnalyst:
            let c = v * (1 + (a - 0.5) * 0.06 * (1 - k.skill)), w = max(0.002, v * (0.015 + (1 - k.skill) * 0.05))
            return Estimate(level: .marketAnalyst, center: c, low: max(0, c - w), high: min(1, c + w))
        case .dataAnalyst:
            let u = min(0.01, v * 0.3 + 0.0004)
            var w: Double, c: Double
            if k.skill >= 0.65 { w = v * (0.06 + (1 - k.skill) * 0.12) + u; c = v * (1 + (a - 0.5) * 0.05) }
            else if b < 0.5 { w = v * 0.08 + u; c = v * (1 + (a - 0.5) * 0.28) }
            else { w = v * 0.55 + u * 4; c = v }
            return Estimate(level: .dataAnalyst, center: c, low: max(0, c - w / 2), high: min(1, c + w / 2))
        case .feeling:
            let c = clamp(v * (0.6 + a * 0.8), 0, 1)
            return Estimate(level: .feeling, center: c, low: c, high: c)
        }
    }

    static func percent(_ x: Double) -> String {
        x < 0.001 ? "under 0.1%" : x < 0.1 ? String(format: "%.1f%%", (x * 1000).rounded() / 10) : "\(Int(jsRound(x * 100)))%"
    }

    /// An estimate in words or numbers, by who is looking. Original: `shTxt`, `guessW`.
    public static func text(_ e: Estimate) -> String {
        switch e.level {
        case .marketAnalyst: return percent(e.center)
        case .dataAnalyst:
            func f(_ x: Double) -> String { x < 0.1 ? String(format: "%.1f", (x * 1000).rounded() / 10) : "\(Int(jsRound(x * 100)))" }
            return f(e.low) == f(e.high) ? f(e.low) + "%" : f(e.low) + "–" + f(e.high) + "%"
        case .feeling:
            let g = e.center
            return g < 0.04 ? "A tiny slice" : g < 0.1 ? "A small slice" : g < 0.2 ? "A fair slice" : g < 0.35 ? "One of the big ones" : "The biggest, I think"
        }
    }

    public static func sizeComparison(rival rev: Double, mine: Double) -> String {
        mine <= 0 ? "Bigger than you" : rev > mine * 1.3 ? "Bigger than you" : rev < mine * 0.75 ? "Smaller than you" : "About your size"
    }

    // MARK: History and reports

    public static func history(_ s: GameState, key: String) -> [(month: Int, share: Double, total: Double)] {
        (s.rest["ms26"]?[key].array ?? []).map { ($0["m"].int, $0["s"].double, $0["tot"].double) }
    }

    /// One point a month per market, weekly sales per company, and a monthly report where a market analyst works. Original: `snap`, `sendReport`.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open {
            var L = s.companies[i].value("rv26").array
            L.append(.number(jsRound(s.companies[i].value("lastW")["rev"].double)))
            if L.count > 13 { L.removeFirst(L.count - 13) }
            s.companies[i].set("rv26", .array(L))
        }
        guard GameCalendar.isMonthEnd(week: s.week) else { return }
        let mi = s.week / 4
        var snaps = s.rest["ms26"] ?? .object([:])
        for m in markets(s, data: data) {
            let t = truth(s, m, data: data)
            var L = snaps[m.id].array
            if let last = L.last, last["m"].int == mi { L.removeLast() }
            L.append(.object(["m": .number(Double(mi)), "s": .number(jsRound(t.share * 10000) / 10000), "tot": .number(jsRound(t.total))]))
            if L.count > 24 { L.removeFirst(L.count - 24) }
            snaps[m.id] = .array(L)
        }
        s.rest["ms26"] = snaps
        for m in markets(s, data: data) {
            let k = knowledge(s, m)
            guard k.level == .marketAnalyst, let first = m.companyIDs.first else { continue }
            s.addMessage(from: k.name, title: "Market report: \(label(m, data: data, withCity: true))", body: report(s, m, k, data: data).joined(separator: " "), companyID: first)
        }
    }

    /// The lines of a market report. Original: `reportLines`.
    public static func report(_ s: GameState, _ m: Market, _ k: Knowledge, data: GameData) -> [String] {
        let t = truth(s, m, data: data), L = history(s, key: m.id)
        let e = estimate(t.share, key: "my" + m.id, k, seed: s.seed, week: s.week)
        var out: [String] = []
        let what = m.kind == .national ? "\(national[m.type]?.noun ?? "business") in \(data.countries[m.countryCode]?.name ?? m.countryCode)"
            : "\((data.catalog[m.type]?.name ?? m.type).lowercased()) sales in \(data.countries.city(m.cityID, preferring: m.countryCode)?.city.name ?? m.cityID)"
        var s1 = "Our share of \(what) is \(k.level == .marketAnalyst ? "about " : "")\(text(e))"
        if L.count >= 2, k.level == .marketAnalyst {
            let d = (t.share - L[L.count - 2].share) * 100
            s1 += abs(d) < 0.15 ? ", about the same as last month" : ", \(d > 0 ? "up" : "down") \(abs(d) < 1 ? String(format: "%.1f", abs(d)) : "\(Int(jsRound(abs(d))))") points on last month"
        }
        out.append(s1 + ".")
        if let big = t.players.first {
            out.append("Biggest rival: \(big.name) with \(text(estimate(big.share, key: "rv" + big.id, k, seed: s.seed, week: s.week))).")
        }
        if L.count >= 3, k.level == .marketAnalyst {
            let a = L[L.count - 3].share, b = L[L.count - 2].share, c = t.share
            if c < b - 0.003, b < a - 0.003 { out.append("Two months of lost ground in a row. Worth a look at prices, marketing and reviews.") }
            else if c > b + 0.003, b > a + 0.003 { out.append("Two months of growth in a row.") }
        }
        return out
    }
}
