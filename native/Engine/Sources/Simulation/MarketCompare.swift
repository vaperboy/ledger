import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

public struct MarketCompetitor: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isYours: Bool
    public var companyID: Int?
    public var rivalID: Int?
    public var share: Double
    public var revenue: Double
    public var priceIndex: Double?
    public var rating: Double?
    public var reviewCount: Int
    public var sizeWord: String
    public var growth: Double?
    public var forSale: Bool
    public var groupName: String?
    public var watched: Bool
}

public struct CompanyMarketPosition: Identifiable, Equatable {
    public var id: Int { companyID }
    public var companyID: Int
    public var name: String
    public var tradeID: String, tradeName: String
    public var cityID: String, cityName: String
    public var countryCode: String
    public var marketKey: String
    public var national: Bool
    public var share: Double
    public var shareText: String
    public var knowledge: MarketMap.Knowledge.Level
    public var shareHistory: [Double]
    public var shareChange: Double?
    public var rank: Int, of: Int
    public var priceIndex: Double?
    public var rating: Double?
    public var marketRating: Double?
    public var ratingVsMarket: Double?
    public var growth: Double?
    public var yourSales: Double
    public var marketSales: Double
    public var topRivals: [MarketCompetitor]
    public var competitors: [MarketCompetitor]
}

public struct MarketRivalRow: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String, owner: String
    public var marketKey: String
    public var companyID: Int
    public var tradeID: String, tradeName: String
    public var cityID: String, cityName: String
    public var countryCode: String
    public var size: Double
    public var sizeWord: String
    public var valuation: Double
    public var revenue: Double
    public var profit: Double
    public var share: Double
    public var priceIndex: Double?
    public var rating: Double
    public var forSale: Bool
    public var inTrouble: Bool
    public var strategy: String
    public var groupID: String?, groupName: String?
    public var isNewEntrant: Bool
    public var watched: Bool
}

public struct MarketGroupRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String, owner: String
    public var strategyName: String
    public var branches: Int
    public var revenue: Double, profit: Double
    public var valuation: Double
    public var yourStake: Double
    public var countries: [String]
    public var trades: [String]
    public var inTrouble: Bool
    public var rivalIDs: [Int]
}

public extension GameEngine {

    func marketPositions() -> [CompanyMarketPosition] {
        MarketMap.markets(state, data: data).flatMap { m in m.companyIDs.compactMap { marketPosition(companyID: $0, market: m) } }
    }

    func marketPosition(companyID: Int) -> CompanyMarketPosition? {
        guard let m = MarketMap.markets(state, data: data).first(where: { $0.companyIDs.contains(companyID) }) else { return nil }
        return marketPosition(companyID: companyID, market: m)
    }

    func marketCompetitors(companyID: Int) -> [MarketCompetitor] { marketPosition(companyID: companyID)?.competitors ?? [] }

    private func marketPosition(companyID: Int, market m: MarketMap.Market) -> CompanyMarketPosition? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return nil }
        let w = World(state: state, data: data)
        let truth = MarketMap.truth(state, m, data: data)
        let know = MarketMap.knowledge(state, m)
        let watched = Set(watchedRivalIDs)
        let national = m.kind == .national
        let total = max(1, truth.total)
        var rows: [MarketCompetitor] = []
        let mine = m.companyIDs.compactMap { state.company($0) }
        let rivals = national ? [] : Rivals.rivals(state, for: co)
        var prices: [String: Double] = [:]
        if !national {
            for c in mine { prices["c\(c.id)"] = Pricing.ticket(c, bd, w) }
            for r in rivals { prices["r\(r.id)"] = Rivals.price(co, r, w) }
        }
        let avgPrice = prices.isEmpty ? 0 : prices.values.reduce(0, +) / Double(prices.count)
        func sizeWord(_ rev: Double) -> String {
            let ref = max(1, truth.total / Double(max(1, truth.players.count + mine.count)))
            return rev >= ref * 1.3 ? "Large" : rev >= ref * 0.7 ? "Medium" : "Small"
        }
        for c in mine {
            let rev = national ? (mine.count == 1 ? truth.mine : truth.mine / Double(mine.count)) : MarketMap.annualRevenue(c)
            let n = Reviews.count(c)
            rows.append(MarketCompetitor(id: "c\(c.id)", name: c.name, isYours: true, companyID: c.id, rivalID: nil, share: rev / total, revenue: rev,
                                         priceIndex: avgPrice > 0 ? prices["c\(c.id)"].map { $0 / avgPrice } : nil,
                                         rating: national || n < Reviews.minimumShown ? nil : Reviews.rating(c), reviewCount: n, sizeWord: sizeWord(rev),
                                         growth: Self.growth(c), forSale: false, groupName: nil, watched: false))
        }
        for p in truth.players {
            let r = p.rivalID.flatMap { id in rivals.first { $0.id == id } }
            rows.append(MarketCompetitor(id: p.id, name: p.name, isYours: false, companyID: nil, rivalID: p.rivalID, share: p.share, revenue: p.revenue,
                                         priceIndex: r.flatMap { r in avgPrice > 0 ? prices["r\(r.id)"].map { $0 / avgPrice } : nil },
                                         rating: r.map { Reviews.rivalRating(seed: state.seed, rivalID: $0.id, size: $0.size) },
                                         reviewCount: r.map { Reviews.rivalReviewCount(bd, size: $0.size, week: state.week) } ?? 0, sizeWord: sizeWord(p.revenue),
                                         growth: nil, forSale: r?.forSale ?? false, groupName: RivalGroups.group(state, id: r?.groupID)?.name,
                                         watched: p.rivalID.map { watched.contains($0) } ?? false))
        }
        rows.sort { $0.revenue > $1.revenue }
        let me = rows.first { $0.companyID == companyID }
        let rank = (rows.firstIndex { $0.companyID == companyID } ?? 0) + 1
        let others = rows.filter { $0.companyID != companyID }.compactMap { $0.rating }
        let marketRating = others.isEmpty ? nil : others.reduce(0, +) / Double(others.count)
        let hist = MarketMap.history(state, key: m.id).map { $0.share }
        let est = MarketMap.estimate(me?.share ?? 0, key: "my" + m.id, know, seed: state.seed, week: state.week)
        return CompanyMarketPosition(companyID: co.id, name: co.name, tradeID: co.type, tradeName: bd.name, cityID: co.cityID, cityName: cityName(co),
                                     countryCode: co.countryCode, marketKey: m.id, national: national, share: me?.share ?? 0, shareText: MarketMap.text(est),
                                     knowledge: know.level, shareHistory: hist, shareChange: hist.count >= 2 ? hist[hist.count - 1] - hist[hist.count - 2] : nil,
                                     rank: rank, of: rows.count, priceIndex: me?.priceIndex, rating: me?.rating, marketRating: marketRating,
                                     ratingVsMarket: me?.rating.flatMap { r in marketRating.map { r - $0 } }, growth: me?.growth,
                                     yourSales: me?.revenue ?? 0, marketSales: truth.total,
                                     topRivals: Array(rows.filter { !$0.isYours }.prefix(3)), competitors: rows)
    }

    static func growth(_ c: Company) -> Double? {
        let h = c.monthlyHistory.suffix(6)
        guard h.count == 6 else { return nil }
        let a = h.prefix(3).reduce(0) { $0 + $1.revenue }, b = h.suffix(3).reduce(0) { $0 + $1.revenue }
        return a > 0 ? pow(b / a, 4) - 1 : nil
    }

    func marketRivals(search: String = "") -> [MarketRivalRow] {
        let w = World(state: state, data: data)
        let watched = Set(watchedRivalIDs)
        var out: [MarketRivalRow] = []
        var seen = Set<String>()
        for co in state.companies where co.status == .open {
            guard let bd = data.catalog[co.type] else { continue }
            let key = Rivals.key(co)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let rivals = Rivals.rivals(state, for: co)
            if rivals.isEmpty { continue }
            let market = MarketMap.markets(state, data: data).first { $0.id == key }
            let truth = market.map { MarketMap.truth(state, $0, data: data) }
            var prices = rivals.map { Rivals.price(co, $0, w) }
            prices += state.companies.filter { $0.status == .open && Rivals.key($0) == key }.map { Pricing.ticket($0, bd, w) }
            let avg = prices.isEmpty ? 0 : prices.reduce(0, +) / Double(prices.count)
            for r in rivals {
                let rev = Rivals.yearlyRevenue(bd, r, w, co)
                let g = RivalGroups.group(state, id: r.groupID)
                let w0 = state.rest["mk"]?[key]["riv"].array.first { $0["id"].int == r.id }?["w0"]
                out.append(MarketRivalRow(id: r.id, name: r.name, owner: r.owner, marketKey: key, companyID: co.id, tradeID: co.type, tradeName: bd.name,
                                          cityID: co.cityID, cityName: cityName(co), countryCode: co.countryCode, size: r.size,
                                          sizeWord: r.size >= 1.15 ? "Large" : r.size >= 0.7 ? "Medium" : "Small",
                                          valuation: Rivals.value(bd, r, w, co), revenue: rev, profit: rev * Rivals.margin(bd, r, seed: state.seed),
                                          share: truth?.players.first { $0.rivalID == r.id }?.share ?? 0,
                                          priceIndex: avg > 0 ? Rivals.price(co, r, w) / avg : nil,
                                          rating: Reviews.rivalRating(seed: state.seed, rivalID: r.id, size: r.size), forSale: r.forSale, inTrouble: r.fortune < 0,
                                          strategy: Rivals.traits(r.strategy).name, groupID: r.groupID, groupName: g?.name,
                                          isNewEntrant: Self.isNewEntrant(w0, week: state.week, opened: co.openedWeek ?? co.foundedWeek),
                                          watched: watched.contains(r.id)))
            }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            out = out.filter { r in [r.name, r.owner, r.tradeName, r.cityName, r.groupName ?? ""].contains { $0.lowercased().contains(q) } }
        }
        return out.sorted { ($0.revenue, $1.id) > ($1.revenue, $0.id) }
    }

    static func isNewEntrant(_ w0: JSONValue?, week: Int, opened: Int) -> Bool {
        guard let w0, !w0.isNull else { return false }
        return w0.int > opened + 1 && week - w0.int <= 8
    }

    func marketRivalGroups() -> [MarketGroupRow] {
        let stakes = GroupDeals.stakes(state)
        return rivalGroupsAround().map { g in
            let raw = GroupStakes.group(state, id: g.id) ?? .null
            return MarketGroupRow(id: g.id, name: g.name, owner: g.owner, strategyName: g.strategyName, branches: g.branches, revenue: g.revenue, profit: g.profit,
                                  valuation: GroupStakes.value(of: raw, state), yourStake: stakes.filter { $0.groupID == g.id }.reduce(0) { $0 + $1.ownership },
                                  countries: g.countries, trades: g.trades, inTrouble: g.inTrouble, rivalIDs: rivalsOfGroup(g.id).map { $0.rival.id })
        }
    }

    var watchedRivalIDs: [Int] { (state.rest["mwatch"]?.array ?? []).map { $0.int } }
    func isWatched(rivalID: Int) -> Bool { watchedRivalIDs.contains(rivalID) }
    var watchlist: [MarketRivalRow] {
        let rows = marketRivals()
        return watchedRivalIDs.compactMap { id in rows.first { $0.id == id } }
    }

    @discardableResult
    mutating func toggleWatch(rivalID: Int) -> Bool {
        let present = Set(marketRivals().map { $0.id })
        var ids = watchedRivalIDs.filter { present.contains($0) }
        let now: Bool
        if let i = ids.firstIndex(of: rivalID) { ids.remove(at: i); now = false } else if present.contains(rivalID) { ids.append(rivalID); now = true } else { now = false }
        update { s, _, _ in s.rest["mwatch"] = .array(ids.map { .number(Double($0)) }) }
        return now
    }
}
