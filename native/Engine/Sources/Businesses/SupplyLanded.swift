import Foundation
import GameCore

public enum SupplyLanded {
    static let freshTrades: Set<String> = ["bakery", "farm", "salmon", "grocery"]

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
    private static let foodVenues: Set<String> = ["foodtruck", "cafe", "restaurant", "nightclub", "hotel", "casino", "fun", "kiosk", "gym", "pcbang", "skires", "indoorski"]
    private static let vehicleTrades: Set<String> = ["taxi", "courier", "trucking", "shipping", "carrental", "usedcar", "cardealer", "carrepair", "airline"]
    private static let makers: Set<String> = ["factory", "furniture", "brewery", "bakery", "salmon", "farm", "vineyard"]

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
        case "fuel":
            return supplierTrade == "oilgas" && (vehicleTrades.contains(buyerTrade) || buyerFamily == "logi")
        default:
            return false
        }
    }

    public static func relevant(_ listings: [SupplyListing], buyerTrade: String, buyerFamily: String) -> [SupplyListing] {
        listings.filter { uses(buyerTrade: buyerTrade, buyerFamily: buyerFamily, line: $0.lineID, supplierTrade: $0.tradeID) }
    }
}
