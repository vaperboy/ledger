import Foundation
import GameCore
import Countries
import Finance

/// One line of the item list, for the screen.
public struct SalesItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isService: Bool
    /// The player's price (before any discount) and the market price, in accounting units like `Pricing.ticket`.
    public var price: Double
    public var marketPrice: Double
    public var discountPercent: Double
    public var discountWeeksLeft: Int
    public var weeklyUnits: Double
    public var weeklyRevenue: Double
    /// Demand against selling at the market price (0.2 = 20% more, -0.1 = 10% fewer), discount included.
    public var demandChange: Double
    public var listedForGroup: Bool
    public var revenueWeight: Double
}

/// What a price and a discount would do to one item in a normal week.
public struct ItemForecast: Equatable, Sendable {
    public var units: Double
    public var revenue: Double
    /// Weekly profit of the item compared with now (item revenue minus its cost of sales).
    public var profitChange: Double
    public var demandChange: Double
}

/// A listed item of another company of the owner, which this company can buy.
public struct OwnListing: Equatable, Identifiable, Sendable {
    public var id: String { "\(sellerID):\(itemID):\(equipmentID)" }
    public var sellerID: Int
    public var sellerName: String
    public var itemID: String
    public var itemName: String
    /// Price per unit, with the item's discount.
    public var price: Double
    /// The item of the buyer's TechPro list that the purchase puts in the company.
    public var equipmentID: String
    public var equipmentName: String
}

public extension SalesItems {
    static func rows(_ s: GameState, companyID: Int, data: GameData) -> [SalesItem] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return [] }
        let w = World(state: s, data: data)
        let list = items(co, bd), mt = marketTicket(co, bd, w)
        let g = max(1e-9, demandFactor(co))
        let units = co.value("lastW")["units"].isNull ? 0 : co.value("lastW")["units"].double
        return list.map { it in
            let dm = demandMultiplier(priceRatio: it.effectiveMultiplier)
            let u = units * it.unitShare * dm / g
            let market = mt * it.ratio
            return SalesItem(id: it.id, name: it.name, isService: it.isService, price: market * it.priceMultiplier, marketPrice: market,
                             discountPercent: it.discountPercent, discountWeeksLeft: it.discountWeeks, weeklyUnits: u,
                             weeklyRevenue: u * market * it.effectiveMultiplier, demandChange: dm - 1, listedForGroup: it.listedForGroup, revenueWeight: it.revenueWeight)
        }
    }

    /// Pure: what `price` (accounting units, absolute) with a discount does to one item.
    static func forecast(_ s: GameState, companyID: Int, itemID: String, price: Double, discountPercent: Double, data: GameData) -> ItemForecast {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], let it = items(co, bd).first(where: { $0.id == itemID }) else {
            return ItemForecast(units: 0, revenue: 0, profitChange: 0, demandChange: 0)
        }
        let w = World(state: s, data: data)
        let market = marketTicket(co, bd, w) * it.ratio
        let newMult = market > 0 ? max(0, price) / market : 1
        let mult = newMult * (1 - clamp(discountPercent, 0, 90) / 100)
        let gNow = max(1e-9, demandFactor(co))
        let dmNow = demandMultiplier(priceRatio: it.effectiveMultiplier), dmNew = demandMultiplier(priceRatio: mult)
        let atMarket = baseUnits(co, bd, w)
        let gNew = gNow - it.unitShare * dmNow + it.unitShare * dmNew
        var scale = 1.0
        let cap = co.value("lastW")["cap"].double
        if cap > 0, atMarket * gNew > cap { scale = cap / (atMarket * gNew) }
        let unitsNew = atMarket * it.unitShare * dmNew * scale
        let unitsNow = atMarket * it.unitShare * dmNow
        let cost = market * bd.costOfSales
        let revNew = unitsNew * market * mult, revNow = unitsNow * market * it.effectiveMultiplier
        return ItemForecast(units: unitsNew, revenue: revNew, profitChange: (revNew - unitsNew * cost) - (revNow - unitsNow * cost), demandChange: dmNew - 1)
    }

    static func mutate(_ s: inout GameState, companyID: Int, data: GameData, _ body: (inout [Item]) -> Void) {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return }
        var list = items(s.companies[i], bd)
        body(&list)
        store(&s, i, list)
    }

    /// Why an item cannot be changed, or nil.
    static func refusal(_ s: GameState, companyID: Int, itemID: String?, data: GameData) -> String? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return "That company no longer exists." }
        guard co.status == .open else { return "Only an open company sets item prices." }
        if let id = itemID, !items(co, bd).contains(where: { $0.id == id }) { return "That item no longer exists." }
        return nil
    }

    static func setPrice(_ s: inout GameState, companyID: Int, itemID: String, price: Double, data: GameData) {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return }
        let market = marketTicket(co, bd, World(state: s, data: data)) * (items(co, bd).first { $0.id == itemID }?.ratio ?? 1)
        mutate(&s, companyID: companyID, data: data) { list in
            if let k = list.firstIndex(where: { $0.id == itemID }), market > 0 { list[k].priceMultiplier = price / market }
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

    /// A new item takes a tenth of the customers at the company's going price; the others make room, so revenue stays as it was.
    static func add(_ s: inout GameState, companyID: Int, name: String, isService svc: Bool, data: GameData) {
        mutate(&s, companyID: companyID, data: data) { list in
            let qn = 0.1
            for k in list.indices { list[k].unitShare *= 1 - qn }
            var n = 1
            while list.contains(where: { $0.id == "n\(n)" }) { n += 1 }
            list.append(Item(id: "n\(n)", name: name, isService: svc, unitShare: qn, ratio: 1, priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false))
        }
    }
}
