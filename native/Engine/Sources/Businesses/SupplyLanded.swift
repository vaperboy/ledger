import Foundation
import GameCore

/// What a supplier's offer really costs the buyer, and whether the buyer has any use for it.
///
/// Landed cost: the price of the goods plus freight and customs from the supplier's country to the buyer's (`TransportCost`). A cheap supplier far
/// away can cost more than a dearer one next door. Only goods that move (stock, materials, packaging, parts, supplies, fuel) travel; services and
/// utilities (cleaning, laundry, software, repairs, power) are delivered without freight.
///
/// Needs: a trade can supply only lines of the fixed supply catalogue (`SupplyMarketCatalogue`), and only to trades that really use them (a
/// bakery's bread goes to cafes, restaurants and shops, not to a car repairer). No custom products exist.
public enum SupplyLanded {
    /// Goods that spoil on the way.
    static let freshTrades: Set<String> = ["bakery", "farm", "salmon", "grocery"]

    /// How a line travels; nil for a line that is not carried (no freight and no customs).
    public static func cargo(lineID: String, supplierTrade: String) -> TransportCost.Cargo? {
        switch lineID {
        case "goods": return freshTrades.contains(supplierTrade) ? .perishable : .standard
        case "mat", "fuel": return .bulky
        case "pack", "supplies": return .light
        case "parts": return .standard
        default: return nil
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String
        /// What one unit costs at the supplier's price tier (the buyer's money).
        public var unitPrice: Double
        public var freightPerUnit: Double
        public var customsPerUnit: Double
        public var landedPerUnit: Double
        /// Against the market supplier's unit price: positive costs more.
        public var vsMarketPerUnit: Double
        /// Landed cost as a multiple of the goods' price (1 = no freight or customs).
        public var landedFactor: Double
        public var transitWeeks: Int
        public var distanceKm: Double
        public var crossesBorder: Bool
        public var mode: TransportCost.Mode?
        public var weeklyFreight: Double
        public var weeklyCustoms: Double
    }

    /// The offers of `listings` for a buyer in `buyerCountry` whose market supplier charges `marketUnitPrice` a unit. `units` is the weekly order;
    /// `priceLevel` is the buyer country's cost index. Cheapest landed cost first, ties by listing id.
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

    /// The words for how a shipment travels and how long it takes.
    public static func transitText(_ r: Row) -> String {
        guard let m = r.mode else { return "No freight" }
        let how = m == .road ? "By road" : m == .sea ? "By sea" : "By air"
        let wait = r.transitWeeks == 0 ? "arrives the same week" : r.transitWeeks == 1 ? "about a week on the way" : "about \(r.transitWeeks) weeks on the way"
        return how + ", " + wait + (r.crossesBorder ? ", customs at the border" : "")
    }
}

public enum SupplyNeeds {
    private static let foodVenues: Set<String> = ["foodtruck", "cafe", "restaurant", "nightclub", "hotel", "casino", "fun", "kiosk", "gym", "pcbang", "skires", "indoorski"]
    private static let vehicleTrades: Set<String> = ["taxi", "courier", "trucking", "shipping", "carrental", "usedcar", "cardealer", "carrepair", "airline"]
    private static let makers: Set<String> = ["factory", "furniture", "brewery", "bakery", "salmon", "farm", "vineyard"]

    /// Whether a buyer of this trade and family has a real use for what a supplier of `supplierTrade` offers on `line`.
    public static func uses(buyerTrade: String, buyerFamily: String, line: String, supplierTrade: String) -> Bool {
        switch line {
        case "goods":
            switch supplierTrade {
            case "farm": return ["bakery", "brewery", "grocery", "restaurant", "cafe", "foodtruck", "hotel", "kiosk", "salmon"].contains(buyerTrade)
            case "bakery": return ["cafe", "restaurant", "foodtruck", "hotel", "grocery", "kiosk", "fun", "casino"].contains(buyerTrade)
            case "brewery": return foodVenues.contains(buyerTrade) || buyerTrade == "grocery"
            case "vineyard": return ["restaurant", "nightclub", "hotel", "casino", "grocery", "cafe"].contains(buyerTrade)
            case "salmon": return ["restaurant", "hotel", "grocery", "foodtruck", "cafe"].contains(buyerTrade)
            case "grocery": return foodVenues.contains(buyerTrade)
            case "factory": return ["boutique", "webshop", "hardware", "kiosk", "furniture", "factory", "cardealer"].contains(buyerTrade)
            case "furniture": return ["boutique", "webshop", "hardware"].contains(buyerTrade)
            case "hardware": return ["construction", "electrician", "plumber", "handy", "carrepair", "furniture", "factory", "realdev"].contains(buyerTrade)
            default: return false
            }
        case "mat":
            switch supplierTrade {
            case "factory": return buyerFamily == "svc"
            case "furniture": return ["handy", "construction", "engcons"].contains(buyerTrade)
            default: return false
            }
        case "pack":
            guard ["factory", "hardware"].contains(supplierTrade) else { return false }
            return foodVenues.contains(buyerTrade) || makers.contains(buyerTrade) || ["boutique", "webshop", "grocery", "courier"].contains(buyerTrade)
        case "parts":
            switch supplierTrade {
            case "factory", "hardware": return vehicleTrades.contains(buyerTrade) || buyerFamily == "prod" || ["fun", "skires", "indoorski", "gym"].contains(buyerTrade)
            case "carrepair": return vehicleTrades.contains(buyerTrade)
            case "handy", "electrician", "plumber": return ["venue", "retail", "rent", "project", "club"].contains(buyerFamily)
            default: return false
            }
        case "repair":
            switch supplierTrade {
            case "carrepair": return vehicleTrades.contains(buyerTrade)
            case "handy", "electrician", "plumber": return ["venue", "retail", "rent", "project", "club", "prod"].contains(buyerFamily)
            default: return false
            }
        case "supplies":
            return supplierTrade == "hardware" && ["svc", "project", "fin", "energy", "club"].contains(buyerFamily)
        case "clean":
            switch supplierTrade {
            case "cleaning": return ["venue", "retail", "prod", "rent", "fin", "club"].contains(buyerFamily)
            case "carclean": return vehicleTrades.contains(buyerTrade)
            default: return false
            }
        case "laundry":
            return supplierTrade == "cleaning" && (["hotel", "restaurant", "cafe", "gym", "nightclub", "casino"].contains(buyerTrade) || buyerFamily == "club")
        case "software":
            if supplierTrade == "gamestudio" { return ["pcbang", "casino", "fun", "nightclub"].contains(buyerTrade) }
            return ["webdev", "startup"].contains(supplierTrade)
        case "power":
            return ["power", "oilgas"].contains(supplierTrade)
        case "fuel":
            return supplierTrade == "oilgas" && (vehicleTrades.contains(buyerTrade) || buyerFamily == "logi")
        default:
            return false
        }
    }

    /// The listings a buyer can use: its trade has a real need for them.
    public static func relevant(_ listings: [SupplyListing], buyerTrade: String, buyerFamily: String) -> [SupplyListing] {
        listings.filter { uses(buyerTrade: buyerTrade, buyerFamily: buyerFamily, line: $0.lineID, supplierTrade: $0.tradeID) }
    }
}
