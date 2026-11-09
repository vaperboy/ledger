import Foundation
import GameCore
import Businesses

public extension GameEngine {
    /// What the market pays for a trade now: the going ticket, or one item's market price when `itemID` is given.
    func marketPrice(tradeID: String, itemID: String? = nil, countryCode: String? = nil) -> Double? {
        MarketPrices.price(state, data: data, trade: tradeID, item: itemID, country: countryCode)
    }

    /// Price index, 13-week change, supply balance word and player counts for one trade in one country.
    func marketPriceInfo(tradeID: String, countryCode: String) -> MarketPrices.Snapshot? {
        MarketPrices.snapshot(state, data: data, country: countryCode, trade: tradeID)
    }

    /// Current price of a listed raw material ("oil", "fuel", "materials", "salmon", "power").
    func commodityPrice(_ id: String) -> Double? { CommodityMarket.price(state, id) }

    /// Feeds the market with players and company counts per trade that play outside this save.
    mutating func setOutsideSuppliers(countryCode: String, players: Int, companies: [String: Int]) {
        update { s, _, _ in MarketPrices.setOutside(&s, country: countryCode, players: players, companies: companies) }
    }
}
