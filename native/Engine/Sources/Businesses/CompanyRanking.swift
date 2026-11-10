import Foundation
import GameCore
import Countries
import Finance

public enum CompanyRanking {
    public enum Metric: String, CaseIterable, Sendable {
        case revenue, profit, value, growth
        public var title: String { switch self { case .revenue: return "Sales"; case .profit: return "Profit"; case .value: return "Value"; case .growth: return "Growth" } }
    }
    public enum Scope: String, CaseIterable, Sendable { case industries, country, world }

    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var countryCode: String
        public var countries: [String]
        public var trades: [String]
        public var revenue: Double, profit: Double, value: Double, growth: Double
        public var previousRevenue: Double, previousProfit: Double, previousValue: Double
        public var isYou = false
        public var groupID: String?
        public var rivalCompanyID: Int?, rivalID: Int?
        public var companyCount = 0
        public var rank = 0, previousRank = 0

        public func figure(_ m: Metric) -> Double { switch m { case .revenue: return revenue; case .profit: return profit; case .value: return value; case .growth: return growth } }
        func before(_ m: Metric) -> Double { switch m { case .revenue: return previousRevenue; case .profit: return previousProfit; case .value: return previousValue; case .growth: return growth } }
        public var movement: Int { previousRank - rank }
    }

    public struct Board: Equatable, Sendable {
        public var entries: [Entry]
        public var total: Int
        public var you: Entry? { entries.first { $0.isYou } }
    }

    static func figures(_ s: GameState, _ id: String) -> (prev: (Double, Double, Double)?, history: [Double]) {
        let p = s.rest["rk27"]?["prev"][id] ?? .null
        return (p.isNull ? nil : (p["rev"].double, p["profit"].double, p["val"].double), (s.rest["rk27"]?["rh"][id].array ?? []).map { $0.double })
    }

    static func yourEntry(_ s: GameState, data: GameData) -> Entry? {
        let cos = s.companies.filter { $0.status == .open || $0.status == .closed }
        guard !cos.isEmpty else { return nil }
        var rev = 0.0, profit = 0.0, val = 0.0
        for c in cos {
            let f = c.ownership / 100
            rev += MarketMap.annualRevenue(c) * f
            profit += CompanyFigures.yearlyProfitEstimate(c, currentWeek: s.week) * f
            val += max(0, Valuation.companyValue(c, state: s, trades: data.catalog)) * f
        }
        var cs: [String] = []
        for c in cos where !cs.contains(c.countryCode) { cs.append(c.countryCode) }
        var types: [String] = []
        for c in cos where !types.contains(c.type) { types.append(c.type) }
        let (prev, hist) = figures(s, "me")
        let gr = hist.count >= 13 && hist[hist.count - 13] > 0 ? rev / hist[hist.count - 13] - 1 : 0
        return Entry(id: "me", name: s.player.name, countryCode: s.homeCountryCode, countries: cs, trades: types, revenue: rev, profit: profit, value: val, growth: gr,
                     previousRevenue: prev?.0 ?? rev, previousProfit: prev?.1 ?? profit, previousValue: prev?.2 ?? val, isYou: true, companyCount: cos.count)
    }

    static func groupEntries(_ s: GameState) -> [Entry] {
        RivalGroups.all(s).filter { !$0["gone"].bool }.map { g in
            let id = g["id"].string
            let st = RivalGroups.strategy(g["strat"].string)
            let profit = RivalGroups.profit(g, s)
            let mult: Double = g["strat"].string == "premium" ? 11 : g["strat"].string == "cautious" ? 10 : 8
            let val = max(0, profit * mult + g["cash"].double - g["debt"].double * 0.5)
            let (prev, hist) = figures(s, id)
            let rev = g["rev"].double
            let gr = hist.count >= 13 && hist[hist.count - 13] > 0 ? rev / hist[hist.count - 13] - 1 : st.growth * 12
            return Entry(id: id, name: g["name"].string, countryCode: g["cc"].string, countries: g["cs"].array.map { $0.string }, trades: g["types"].array.map { $0.string },
                         revenue: rev, profit: profit, value: val, growth: gr, previousRevenue: prev?.0 ?? rev, previousProfit: prev?.1 ?? profit, previousValue: prev?.2 ?? val,
                         groupID: id, companyCount: g["br"].int)
        }
    }

    static func rivalEntries(_ s: GameState, data: GameData) -> [Entry] {
        let w = World(state: s, data: data)
        var out: [Entry] = [], seen = Set<Int>()
        for co in s.companies where co.status == .open {
            guard let bd = data.catalog[co.type], RivalGroups.localFamilies.contains(bd.family) else { continue }
            for r in Rivals.rivals(s, for: co) where (r.groupID ?? "").isEmpty || r.groupID == "0" {
                if seen.contains(r.id) { continue }
                seen.insert(r.id)
                var h = HashedRandom("\(s.seed):lr:\(r.id)")
                let rev = Rivals.yearlyRevenue(bd, r, w, co), val = Rivals.value(bd, r, w, co)
                let profit = rev * Rivals.margin(bd, r, seed: s.seed)
                let gr = (h.next() - 0.45) * 0.1
                let prevRev = rev * (1 - (h.next() - 0.5) * 0.04)
                out.append(Entry(id: "lr\(r.id)", name: r.name, countryCode: co.countryCode, countries: [co.countryCode], trades: [co.type], revenue: rev, profit: profit, value: val,
                                 growth: gr, previousRevenue: prevRev, previousProfit: profit, previousValue: val, rivalCompanyID: co.id, rivalID: r.id))
            }
        }
        return out
    }

    static func playerEntries(_ s: GameState, data: GameData, skipping names: Set<String>) -> [Entry] {
        guard let list = s.rest["real"]?.array, !list.isEmpty else { return [] }
        var out: [Entry] = []
        for j in list {
            let name = j["name"].string, cc = j["cc"].string
            guard !names.contains(name), let c = data.countries[cc],
                  let bd = data.catalog.order.compactMap({ data.catalog[$0] }).first(where: { $0.name.lowercased() == j["trade"].string.lowercased() }) else { continue }
            let demand = c.cities.first { $0.name.lowercased() == j["city"].string.lowercased() }?.demand ?? 1
            let size = j["size"].double > 0 ? j["size"].double : 1
            let rev = (bd.normalDemand == 0 ? 1 : bd.normalDemand) * bd.ticket * demand * size * 0.9 * 52 * c.priceLevel
            let profit = rev * clamp(bd.margin, -0.12, 0.45)
            let val = (rev * (max(0.04, bd.margin) * 4.5 + 0.15) / 1000).rounded() * 1000
            var h = HashedRandom("\(s.seed):pr:\(name)")
            out.append(Entry(id: "pr:\(name)", name: name, countryCode: cc, countries: [cc], trades: [bd.id], revenue: rev, profit: profit, value: val,
                             growth: (h.next() - 0.45) * 0.1, previousRevenue: rev, previousProfit: profit, previousValue: val, companyCount: 1))
        }
        return out
    }

    struct Bucket { var cc: String, trade: String, n: Double, ur: Double, m: Double }

    static func buckets(data: GameData) -> [Bucket] {
        var out: [Bucket] = []
        let types = data.catalog.order.filter { id in data.catalog[id].map { RivalGroups.localFamilies.contains($0.family) && $0.normalDemand > 0 } ?? false }
        for c in data.countries.countries {
            for t in types {
                guard let bd = data.catalog[t] else { continue }
                let ur = RivalGroups.tradeRevenue(bd, c)
                guard ur > 0 else { continue }
                let n = max(6, min(1500, (c.populationMillions * 1e6 / (8000 * (max(1, bd.ticket) / 100).squareRoot())).rounded()))
                out.append(Bucket(cc: c.code, trade: t, n: n, ur: ur, m: max(0.03, bd.margin)))
            }
        }
        return out
    }

    static func phi(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }

    static func above(_ b: Bucket, _ x: Double, _ metric: Metric) -> Double {
        if metric == .growth {
            if x >= 0.8 { return 0 }
            if x < -0.5 { return b.n }
            return b.n * (1 - phi((x - 0.01) / 0.08))
        }
        let v: Double
        switch metric {
        case .revenue: v = x
        case .profit: v = (x + 0.5 * b.ur * b.m) / b.m
        default: v = x / (b.m * 6 + 0.25)
        }
        guard v > 0 else { return b.n }
        return b.n * (1 - phi((log(v / b.ur) + 0.45) / 0.8))
    }

    public static func board(_ s: GameState, data: GameData, scope: Scope, metric: Metric) -> Board {
        guard let me = yourEntry(s, data: data) else { return Board(entries: [], total: 0) }
        let mt = Set(me.trades), mc = Set(RivalGroups.myCountries(s))
        var L = groupEntries(s) + rivalEntries(s, data: data)
        L += playerEntries(s, data: data, skipping: Set(L.map { $0.name }))
        L = L.filter { e in
            switch scope {
            case .industries: return e.trades.contains { mt.contains($0) } && e.countries.contains { mc.contains($0) }
            case .country: return e.countryCode == s.homeCountryCode || e.countries.contains(s.homeCountryCode)
            case .world: return true
            }
        }
        L.append(me)
        let bk = buckets(data: data).filter { b in
            switch scope {
            case .industries: return mt.contains(b.trade) && mc.contains(b.cc)
            case .country: return b.cc == s.homeCountryCode
            case .world: return true
            }
        }
        func crowdAbove(_ x: Double) -> Int { Int(saturating: bk.reduce(0) { $0 + above($1, x, metric) }.rounded()) }
        let now = L.sorted { $0.figure(metric) > $1.figure(metric) }
        let before = L.sorted { $0.before(metric) > $1.before(metric) }
        var out: [Entry] = []
        for (i, var e) in now.enumerated() {
            e.rank = i + 1 + crowdAbove(e.figure(metric))
            e.previousRank = (before.firstIndex { $0.id == e.id } ?? i) + 1 + crowdAbove(e.before(metric))
            out.append(e)
        }
        return Board(entries: out, total: L.count + Int(bk.reduce(0) { $0 + $1.n }))
    }

    public static func yourRank(_ s: GameState, data: GameData, scope: Scope = .country, metric: Metric = .revenue) -> (rank: Int, of: Int)? {
        let b = board(s, data: data, scope: scope, metric: metric)
        return b.you.map { ($0.rank, b.total) }
    }

    static func snapshot(_ s: inout GameState, data: GameData) {
        var root = s.rest["rk27"] ?? .object(["prev": .object([:]), "rh": .object([:])])
        var all = groupEntries(s)
        if let me = yourEntry(s, data: data) { all.append(me) }
        for e in all {
            root["prev"][e.id] = .object(["rev": .number(e.revenue), "profit": .number(e.profit), "val": .number(e.value)])
            var h = root["rh"][e.id].array
            h.append(.number(jsRound(e.revenue)))
            if h.count > 24 { h.removeFirst(h.count - 24) }
            root["rh"][e.id] = .array(h)
        }
        s.rest["rk27"] = root
    }
}
