import Foundation
import GameCore
import Businesses

public extension GameEngine {
    func marketPrice(tradeID: String, itemID: String? = nil, countryCode: String? = nil) -> Double? {
        MarketPrices.price(state, data: data, trade: tradeID, item: itemID, country: countryCode)
    }

    func marketPriceInfo(tradeID: String, countryCode: String) -> MarketPrices.Snapshot? {
        MarketPrices.snapshot(state, data: data, country: countryCode, trade: tradeID)
    }

    func commodityPrice(_ id: String) -> Double? { CommodityMarket.price(state, id) }

    mutating func setOutsideSuppliers(countryCode: String, players: Int, companies: [String: Int]) {
        update { s, _, _ in MarketPrices.setOutside(&s, country: countryCode, players: players, companies: companies) }
    }
}
