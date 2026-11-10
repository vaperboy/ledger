import Foundation
import GameCore
import Countries

public enum MarketPrices {
    public static let key = "mpx"
    public static let outsideKey = "mpl"
    public static let band: ClosedRange<Double> = 0.8...1.25
    public static let followRate = 0.08
    public static let noise = 0.003
    public static let backupShare = 0.6
    public static let backupElasticity = 1.5
    public static let playerCap = 0.25
    public static let dealCap = 0.3
    public static let playersDemandStep = 0.01
    public static let playersDemandCap = 50.0
    public static let alertMove = 0.1

    static let skipFamilies: Set<String> = ["rent", "fin", "energy", "club"]

    public struct Totals: Equatable, Sendable {
        public var demand: Double
        public var supply: Double
        public var playerOutlets: Int
        public var outsideCompanies: Int
        public var dealVolume: Double
    }

    public static func marketKey(country: String, trade: String) -> String { country + "|" + trade }

    public static func index(_ s: GameState, country: String, trade: String) -> Double {
        let g = s.rest[key]?[marketKey(country: country, trade: trade)]["g"] ?? .null
        return g.isNull ? 1 : g.double
    }

    public static func index(_ s: GameState, _ co: Company) -> Double { index(s, country: co.countryCode, trade: co.type) }

    public static func equilibrium(demand: Double, supply: Double, backup: Double, elasticity: Double) -> Double {
        guard demand > 0, supply > 0 else { return 1 }
        func excess(_ g: Double) -> Double { supply + backup * backupElasticity * (g - 1) - demand * pow(g, -elasticity) }
        var lo = band.lowerBound, hi = band.upperBound
        if excess(lo) >= 0 { return lo }
        if excess(hi) <= 0 { return hi }
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if excess(mid) < 0 { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    public static func step(index: Double, target: Double, noise z: Double) -> Double {
        clamp(index + (target - index) * followRate + z * noise, band.lowerBound, band.upperBound)
    }

    public static func setOutside(_ s: inout GameState, country: String, players: Int, companies: [String: Int]) {
        var o = s.rest[outsideKey] ?? .object([:])
        o[country] = .object(["p": .number(Double(max(0, players))), "c": .object(companies.mapValues { .number(Double(max(0, $0))) })])
        s.rest[outsideKey] = o
    }

    static func outlets(_ co: Company) -> Double {
        let fr = co.value("fr")
        let units = fr["on"].bool ? Double(fr["units"].array.count) : 0
        return clamp(co.size, 0.3, 1.5) * (1 + units)
    }

    public static func totals(_ s: GameState, data: GameData, country code: String, trade: Trade) -> Totals? {
        guard !skipFamilies.contains(trade.family), trade.normalDemand > 0 else { return nil }
        let country = data.countries.resolve(code, orHome: s.homeCountryCode)
        var demand = 0.0, aiAndSeats = 0.0, excess = 0.0
        var seatSize: [String: Double] = [:]
        for city in country.cities {
            let r = trade.normalDemand * trade.ticket * max(0.01, city.demand)
            let density = CityMarket.rivalDensity(trade: trade.id, country: country, city: city, tables: data.balance.cityMarket)
            let n = max(1, 1 + city.population / 120 * density)
            demand += r * (n + 1)
            aiAndSeats += r * (n + 1)
            seatSize[city.id] = r
        }
        var perCity: [String: Double] = [:]
        var outletsCount = 0
        for co in s.companies where co.status == .open && co.type == trade.id && co.countryCode == code {
            perCity[co.cityID, default: 0] += outlets(co)
            outletsCount += 1 + (co.value("fr")["on"].bool ? co.value("fr")["units"].array.count : 0)
        }
        for (cid, o) in perCity { excess += max(0, o - 1) * (seatSize[cid] ?? 0) }
        let o = s.rest[outsideKey]?[code] ?? .null
        let outsideCompanies = o["c"][trade.id].int
        let avg = demand / Double(max(1, country.cities.count)) / 4
        excess += Double(outsideCompanies) * avg
        excess = min(excess, demand * playerCap)
        var deals = 0.0
        let infl = max(0.01, s.economy.inflationIndex)
        for l in IntercompanySupply.links(s) {
            guard let sup = s.company(l.supplierID), sup.type == trade.id, sup.countryCode == code else { continue }
            deals += l.lastSpend * l.lastShare / infl
        }
        deals = min(deals, demand * dealCap)
        let players = min(playersDemandCap, o["p"].double)
        let d = max(0.0001, (demand - deals) * (1 + playersDemandStep * players))
        return Totals(demand: d, supply: aiAndSeats + excess, playerOutlets: outletsCount, outsideCompanies: outsideCompanies, dealVolume: deals)
    }

    public static func target(_ s: GameState, data: GameData, country: String, trade: Trade) -> Double {
        guard let t = totals(s, data: data, country: country, trade: trade) else { return 1 }
        return equilibrium(demand: t.demand, supply: t.supply, backup: t.demand * backupShare, elasticity: clamp(trade.elasticity, 0.3, 2))
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        var pairs = Set<String>()
        for co in s.companies where co.status == .open { pairs.insert(marketKey(country: co.countryCode, trade: co.type)) }
        var store = s.rest[key] ?? .object([:])
        for k in pairs.sorted() {
            let parts = k.split(separator: "|").map(String.init)
            guard parts.count == 2, let bd = data.catalog[parts[1]], totals(s, data: data, country: parts[0], trade: bd) != nil else { continue }
            var m = store[k]
            let now = m["g"].isNull ? 1 : m["g"].double
            let next = step(index: now, target: target(s, data: data, country: parts[0], trade: bd), noise: s.random.gauss())
            var h = m["h"].array
            h.append(.number(next))
            if h.count > 13 { h.removeFirst(h.count - 13) }
            m["g"] = .number(next)
            m["h"] = .array(h)
            store[k] = m
        }
        s.rest[key] = store
    }

    public struct Snapshot: Equatable, Sendable {
        public var index: Double
        public var change: Double
        public var balanceWord: String
        public var playerOutlets: Int
        public var outsideCompanies: Int
    }

    public static func snapshot(_ s: GameState, data: GameData, country: String, trade id: String) -> Snapshot? {
        guard let bd = data.catalog[id], let t = totals(s, data: data, country: country, trade: bd) else { return nil }
        let now = index(s, country: country, trade: id)
        let h = (s.rest[key]?[marketKey(country: country, trade: id)]["h"].array ?? []).map { $0.double }
        let then = h.count > 12 ? h[h.count - 13] : (h.first ?? now)
        let ratio = t.supply / t.demand
        let word = ratio > 1.03 ? "Plentiful" : ratio < 0.97 ? "Tight" : "Balanced"
        return Snapshot(index: now, change: then > 0 ? now / then - 1 : 0, balanceWord: word, playerOutlets: t.playerOutlets, outsideCompanies: t.outsideCompanies)
    }

    public static func price(_ s: GameState, data: GameData, trade id: String, item: String? = nil, country: String? = nil) -> Double? {
        let cos = s.companies.filter { $0.type == id && $0.status.isLive && (country == nil || $0.countryCode == country) }
        guard let co = cos.first, let bd = data.catalog[id] else { return nil }
        let w = World(state: s, data: data)
        guard let item else { return SalesItems.marketTicket(co, bd, w) }
        let rows = SalesItems.rows(s, companyID: co.id, data: data)
        return rows.first { $0.id == item || SalesItems.localID($0.id) == item }?.marketPrice
    }
}
