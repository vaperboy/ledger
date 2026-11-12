import Foundation
import GameCore
import Countries
import Finance

public struct SalesItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isService: Bool
    public var price: Double
    public var marketPrice: Double
    public var discountPercent: Double
    public var discountWeeksLeft: Int
    public var weeklyUnits: Double
    public var weeklyRevenue: Double
    public var demandChange: Double
    public var listedForGroup: Bool
    public var revenueWeight: Double
    public var priceSetter: SalesItems.PriceSetter = .owner
    public var priceFloor: Double = SalesItems.priceFloor
    public var priceCeiling: Double = SalesItems.priceCeiling
    public var minPrice: Double { marketPrice * priceFloor }
    public var maxPrice: Double { marketPrice * priceCeiling }
}

public struct ItemForecast: Equatable, Sendable {
    public var units: Double
    public var revenue: Double
    public var profitChange: Double
    public var demandChange: Double
    public var marketPosition: Double = 0
}

public struct OwnListing: Equatable, Identifiable, Sendable {
    public var id: String { "\(sellerID):\(itemID):\(equipmentID)" }
    public var sellerID: Int
    public var sellerName: String
    public var itemID: String
    public var itemName: String
    public var price: Double
    public var equipmentID: String
    public var equipmentName: String
    public var available: Int = 0
}

public extension SalesItems {
    static func rows(_ s: GameState, companyID: Int, data: GameData) -> [SalesItem] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return [] }
        let w = World(state: s, data: data)
        let list = items(co, bd), mt = marketTicket(co, bd, w)
        let g = max(1e-9, demandFactor(co, bd, w)), sh = shape(co, bd, w)
        let setter = priceSetter(s, co)
        let top = ceiling(for: bd)
        let units = co.value("lastW")["units"].isNull ? 0 : co.value("lastW")["units"].double
        return list.map { it in
            let dm = demandMultiplier(priceRatio: it.effectiveMultiplier, shape: sh)
            let u = units * it.unitShare * dm / g
            let market = mt * it.ratio
            return SalesItem(id: it.id, name: it.name, isService: it.isService, price: market * it.priceMultiplier, marketPrice: market,
                             discountPercent: it.discountPercent, discountWeeksLeft: it.discountWeeks, weeklyUnits: u,
                             weeklyRevenue: u * market * it.effectiveMultiplier, demandChange: dm - 1, listedForGroup: it.listedForGroup, revenueWeight: it.revenueWeight, priceSetter: setter,
                             priceFloor: priceFloor, priceCeiling: top)
        }
    }

    static func forecast(_ s: GameState, companyID: Int, itemID: String, price: Double, discountPercent: Double, data: GameData) -> ItemForecast {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], let it = items(co, bd).first(where: { $0.id == itemID }) else {
            return ItemForecast(units: 0, revenue: 0, profitChange: 0, demandChange: 0)
        }
        let w = World(state: s, data: data)
        let market = marketTicket(co, bd, w) * it.ratio
        let newMult = market > 0 ? clamp(max(0, price) / market, range(for: bd).lowerBound, range(for: bd).upperBound) : 1
        let mult = newMult * (1 - clamp(discountPercent, 0, 90) / 100)
        let gNow = max(1e-9, demandFactor(co, bd, w)), sh = shape(co, bd, w)
        let dmNow = demandMultiplier(priceRatio: it.effectiveMultiplier, shape: sh), dmNew = demandMultiplier(priceRatio: mult, shape: sh)
        let atMarket = baseUnits(co, bd, w)
        let gNew = gNow - it.unitShare * dmNow + it.unitShare * dmNew
        var scale = 1.0
        let cap = co.value("lastW")["cap"].double
        if cap > 0, atMarket * gNew > cap { scale = cap / (atMarket * gNew) }
        let unitsNew = atMarket * it.unitShare * dmNew * scale
        let unitsNow = atMarket * it.unitShare * dmNow
        let cost = market * (co.type == UsedCarDealer.tradeID ? (UsedCarDealer.costRatio(co) ?? bd.costOfSales) : bd.costOfSales)
        let revNew = unitsNew * market * mult, revNow = unitsNow * market * it.effectiveMultiplier
        return ItemForecast(units: unitsNew, revenue: revNew, profitChange: (revNew - unitsNew * cost) - (revNow - unitsNow * cost), demandChange: dmNew - 1,
                            marketPosition: position(priceRatio: mult, shape: sh))
    }

    static func mutate(_ s: inout GameState, companyID: Int, data: GameData, _ body: (inout [Item]) -> Void) {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return }
        var list = stored(s.companies[i], bd)
        body(&list)
        store(&s, i, list)
    }

    static func refusal(_ s: GameState, companyID: Int, itemID: String?, data: GameData) -> String? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return "That company no longer exists." }
        guard co.status == .open else { return "Only an open company sets item prices." }
        if firstChoicePending(co), itemID != nil { return "Choose what you sell first." }
        if let id = itemID, hiddenIDs(co).contains(id) { return "That item no longer exists." }
        if let id = itemID, !items(co, bd).contains(where: { $0.id == id }) { return "That item no longer exists." }
        return nil
    }

    static func setPrice(_ s: inout GameState, companyID: Int, itemID: String, price: Double, data: GameData) {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return }
        let market = marketTicket(co, bd, World(state: s, data: data)) * (items(co, bd).first { $0.id == itemID }?.ratio ?? 1)
        mutate(&s, companyID: companyID, data: data) { list in
            if let k = list.firstIndex(where: { $0.id == itemID }), market > 0 { list[k].priceMultiplier = clamp(price / market, range(for: bd).lowerBound, range(for: bd).upperBound) }
        }
    }

    static func setDiscount(_ s: inout GameState, companyID: Int, itemID: String, percent: Double, weeks: Int, data: GameData) {
        mutate(&s, companyID: companyID, data: data) { list in
            guard let k = list.firstIndex(where: { $0.id == itemID }) else { return }
            list[k].discountPercent = percent > 0 ? percent : 0
            list[k].discountWeeks = percent > 0 ? weeks : 0
        }
    }

    static func setListed(_ s: inout GameState, companyID: Int, itemID: String, listed: Bool, data: GameData) {
        mutate(&s, companyID: companyID, data: data) { list in
            if let k = list.firstIndex(where: { $0.id == itemID }) { list[k].listedForGroup = listed }
        }
    }

    static func add(_ s: inout GameState, companyID: Int, name: String, isService svc: Bool, data: GameData) {
        settlePick(&s, companyID: companyID, keeping: nil, data: data)
        if let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] {
            let co = s.companies[i]
            MarketPressure.addLift(&s, i, lift: MarketPressure.addedLift(co, category: svc != isService(bd), rivalCount: Rivals.rivals(s, for: co).count))
        }
        mutate(&s, companyID: companyID, data: data) { list in
            let qn = 0.1
            for k in list.indices { list[k].unitShare *= 1 - qn }
            var n = 1
            while list.contains(where: { $0.id == "n\(n)" }) { n += 1 }
            list.append(Item(id: "n\(n)", name: name, isService: svc, unitShare: qn, ratio: 1, priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false))
        }
    }
}
