import Foundation
import GameCore

public enum SupplyLanded {
    // Freight class of a line from the supply map; nil for services, which travel no freight.
    public static func cargo(lineID: String, supplierTrade: String) -> TransportCost.Cargo? {
        SupplyMap.line(lineID)?.cargo.flatMap { TransportCost.Cargo(rawValue: $0) }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String
        public var unitPrice: Double
        public var freightPerUnit: Double
        public var customsPerUnit: Double
        public var landedPerUnit: Double
        public var vsMarketPerUnit: Double
        public var landedFactor: Double
        public var transitWeeks: Int
        public var distanceKm: Double
        public var crossesBorder: Bool
        public var mode: TransportCost.Mode?
        public var weeklyFreight: Double
        public var weeklyCustoms: Double
    }

    public static func compare(_ listings: [SupplyListing], buyerCountry: String, marketUnitPrice: Double, units: Int, priceLevel: Double) -> [Row] {
        let n = Double(max(1, units))
        let market = max(0, marketUnitPrice.isFinite ? marketUnitPrice : 0)
        return listings.map { l -> Row in
            let price = market * l.priceFactor
            let goods = price * n
            let from = l.country.isEmpty ? buyerCountry : l.country
            guard let cargo = cargo(lineID: l.lineID, supplierTrade: l.tradeID), goods > 0 else {
                return Row(id: l.id, unitPrice: price, freightPerUnit: 0, customsPerUnit: 0, landedPerUnit: price, vsMarketPerUnit: price - market, landedFactor: 1,
                           transitWeeks: 0, distanceKm: 0, crossesBorder: false, mode: nil, weeklyFreight: 0, weeklyCustoms: 0)
            }
            let q = TransportCost.quote(goodsValue: goods, from: from, to: buyerCountry, cargo: cargo, priceLevel: priceLevel)
            return Row(id: l.id, unitPrice: price, freightPerUnit: q.transport / n, customsPerUnit: q.customs / n, landedPerUnit: q.landed / n, vsMarketPerUnit: q.landed / n - market,
                       landedFactor: q.landed / goods, transitWeeks: q.transitWeeks, distanceKm: q.distanceKm, crossesBorder: q.crossesBorder, mode: q.mode,
                       weeklyFreight: q.transport, weeklyCustoms: q.customs)
        }.sorted { $0.landedPerUnit != $1.landedPerUnit ? $0.landedPerUnit < $1.landedPerUnit : $0.id < $1.id }
    }

    public static func transitText(_ r: Row) -> String {
        guard let m = r.mode else { return "No freight" }
        let how = m == .road ? "By road" : m == .sea ? "By sea" : "By air"
        let wait = r.transitWeeks == 0 ? "arrives the same week" : r.transitWeeks == 1 ? "about a week on the way" : "about \(r.transitWeeks) weeks on the way"
        return how + ", " + wait + (r.crossesBorder ? ", customs at the border" : "")
    }
}

public enum SupplyNeeds {
    public static func uses(buyerTrade: String, buyerFamily: String, line: String, supplierTrade: String) -> Bool {
        SupplyMap.uses(buyerTrade: buyerTrade, line: line, supplierTrade: supplierTrade)
    }

    public static func relevant(_ listings: [SupplyListing], buyerTrade: String, buyerFamily: String) -> [SupplyListing] {
        listings.filter { uses(buyerTrade: buyerTrade, buyerFamily: buyerFamily, line: $0.lineID, supplierTrade: $0.tradeID) }
    }
}
