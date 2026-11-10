import Foundation
import GameCore
import Countries

public enum TransportCost {
    public enum Mode: String, Sendable { case road, sea, air }

    public enum Cargo: String, Sendable, CaseIterable {
        case light, standard, bulky, perishable
        var rateFactor: Double {
            switch self { case .light: return 0.5; case .standard: return 1; case .bulky: return 1.8; case .perishable: return 1.4 }
        }
    }

    public static let minimumKm = 120.0

    public static func distanceKm(from a: String, to b: String) -> Double {
        guard let p = CountryTraits.capital(a), let q = CountryTraits.capital(b) else { return a == b ? minimumKm : 8000 }
        let r = 6371.0, rad = Double.pi / 180
        let dLat = (q.lat - p.lat) * rad, dLon = (q.lon - p.lon) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(p.lat * rad) * cos(q.lat * rad) * sin(dLon / 2) * sin(dLon / 2)
        return max(minimumKm, 2 * r * asin(min(1, h.squareRoot())))
    }

    public static func crossesBorder(from a: String, to b: String) -> Bool {
        guard a != b else { return false }
        guard CountryTraits.capital(a) != nil, CountryTraits.capital(b) != nil else { return true }
        return CountryTraits.customsZone(a) != CountryTraits.customsZone(b)
    }

    public static func mode(from a: String, to b: String, cargo: Cargo) -> Mode {
        if distanceKm(from: a, to: b) <= 4500 && sameRegion(a, b) { return .road }
        return cargo == .perishable ? .air : .sea
    }

    static func sameRegion(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard let r = CountryTraits.region(a) else { return false }
        return r == CountryTraits.region(b)
    }

    static func ratePer1000Km(_ m: Mode) -> Double {
        switch m { case .road: return 0.022; case .sea: return 0.009; case .air: return 0.09 }
    }
    static func fixedFee(_ m: Mode) -> Double {
        switch m { case .road: return 400; case .sea: return 2500; case .air: return 1500 }
    }
    static let customsRate = 0.012
    static let customsFixed = 1200.0

    public struct Quote: Equatable, Sendable {
        public var distanceKm: Double
        public var mode: Mode
        public var goodsValue: Double
        public var transport: Double
        public var customs: Double
        public var crossesBorder: Bool
        public var transitWeeks: Int
        public var fees: Double { transport + customs }
        public var landed: Double { goodsValue + fees }
    }

    public static func quote(goodsValue: Double, from a: String, to b: String, cargo: Cargo = .standard, priceLevel: Double = 1) -> Quote {
        let value = max(0, goodsValue.isFinite ? goodsValue : 0)
        let km = distanceKm(from: a, to: b)
        let m = mode(from: a, to: b, cargo: cargo)
        let border = crossesBorder(from: a, to: b)
        let level = max(0.05, priceLevel)
        let variable = value * ratePer1000Km(m) * km / 1000 * cargo.rateFactor
        let transport = value > 0 ? jsRound(variable + fixedFee(m) * level) : 0
        let customs = (border && value > 0) ? jsRound(value * customsRate + customsFixed * level) : 0
        let days: Double
        switch m {
        case .road: days = 1 + km / 600
        case .sea: days = 5 + km / 450
        case .air: days = 2
        }
        return Quote(distanceKm: km, mode: m, goodsValue: value, transport: transport, customs: customs, crossesBorder: border,
                     transitWeeks: Int((days / 7).rounded()))
    }

    public struct Offer: Equatable, Sendable {
        public var id: String
        public var country: String
        public var unitPrice: Double
        public init(id: String, country: String, unitPrice: Double) { self.id = id; self.country = country; self.unitPrice = unitPrice }
    }

    public struct Landed: Equatable, Sendable {
        public var offer: Offer
        public var quote: Quote
        public var units: Double
        public var landedUnitCost: Double
    }

    public static func rank(_ offers: [Offer], units: Double, to country: String, cargo: Cargo = .standard, priceLevel: Double = 1) -> [Landed] {
        let n = max(1, units)
        return offers.map { o -> Landed in
            let q = quote(goodsValue: max(0, o.unitPrice) * n, from: o.country, to: country, cargo: cargo, priceLevel: priceLevel)
            return Landed(offer: o, quote: q, units: n, landedUnitCost: q.landed / n)
        }.sorted { $0.landedUnitCost != $1.landedUnitCost ? $0.landedUnitCost < $1.landedUnitCost : $0.offer.id < $1.offer.id }
    }
}
