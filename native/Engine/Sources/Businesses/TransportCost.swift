import Foundation
import GameCore
import Countries

/// What it costs to move goods between countries, and the landed cost (price plus transport) that supplier choice compares.
/// A cheap supplier far away can cost more per unit than a dearer local one: freight grows with distance, and crossing a customs border adds duty and paperwork.
public enum TransportCost {
    public enum Mode: String, Sendable { case road, sea, air }

    /// What is carried: it sets the rate per kilometre.
    public enum Cargo: String, Sendable, CaseIterable {
        case light, standard, bulky, perishable
        var rateFactor: Double {
            switch self { case .light: return 0.5; case .standard: return 1; case .bulky: return 1.8; case .perishable: return 1.4 }
        }
    }

    /// Road trips never count for less than this (a delivery inside one country still has a haul).
    public static let minimumKm = 120.0

    /// Great-circle distance between two countries' capitals, at least `minimumKm`. An unknown country counts as far away (8 000 km).
    public static func distanceKm(from a: String, to b: String) -> Double {
        guard let p = CountryTraits.capital(a), let q = CountryTraits.capital(b) else { return a == b ? minimumKm : 8000 }
        let r = 6371.0, rad = Double.pi / 180
        let dLat = (q.lat - p.lat) * rad, dLon = (q.lon - p.lon) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(p.lat * rad) * cos(q.lat * rad) * sin(dLon / 2) * sin(dLon / 2)
        return max(minimumKm, 2 * r * asin(min(1, h.squareRoot())))
    }

    /// Does the goods' trip cross a customs border? Within one country or within the EU it does not.
    public static func crossesBorder(from a: String, to b: String) -> Bool {
        guard a != b else { return false }
        guard CountryTraits.capital(a) != nil, CountryTraits.capital(b) != nil else { return true }
        return CountryTraits.customsZone(a) != CountryTraits.customsZone(b)
    }

    public static func mode(from a: String, to b: String, cargo: Cargo) -> Mode {
        if distanceKm(from: a, to: b) <= 4500 && sameRegion(a, b) { return .road }
        // Perishable goods fly over the sea; everything else goes by ship.
        return cargo == .perishable ? .air : .sea
    }

    /// Land links: Europe, and North America, can be driven; the rest is across water.
    static func sameRegion(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard let r = CountryTraits.region(a) else { return false }
        return r == CountryTraits.region(b)
    }

    /// Transport rate as a share of the goods' value per 1 000 km.
    static func ratePer1000Km(_ m: Mode) -> Double {
        switch m { case .road: return 0.022; case .sea: return 0.009; case .air: return 0.09 }
    }
    /// A fixed fee per shipment at the reference price level (loading, port, handling).
    static func fixedFee(_ m: Mode) -> Double {
        switch m { case .road: return 400; case .sea: return 2500; case .air: return 1500 }
    }
    static let customsRate = 0.012
    static let customsFixed = 1200.0

    public struct Quote: Equatable, Sendable {
        public var distanceKm: Double
        public var mode: Mode
        public var goodsValue: Double
        /// Freight and handling.
        public var transport: Double
        /// Duty and paperwork at a border (0 inside a customs zone).
        public var customs: Double
        public var crossesBorder: Bool
        /// Whole weeks the goods are on the way (0 = arrives the same week).
        public var transitWeeks: Int
        public var fees: Double { transport + customs }
        public var landed: Double { goodsValue + fees }
    }

    /// The cost of moving `goodsValue` of goods. `priceLevel` is the buyer country's cost index (`Country.costIndex`) that scales the fixed fees.
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

    // MARK: Choosing a supplier by landed cost

    /// One supplier's offer: the unit price already in the buyer's money.
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
        /// Price plus transport and customs per unit.
        public var landedUnitCost: Double
    }

    /// Offers for an order of `units`, cheapest landed cost first (ties by id).
    public static func rank(_ offers: [Offer], units: Double, to country: String, cargo: Cargo = .standard, priceLevel: Double = 1) -> [Landed] {
        let n = max(1, units)
        return offers.map { o -> Landed in
            let q = quote(goodsValue: max(0, o.unitPrice) * n, from: o.country, to: country, cargo: cargo, priceLevel: priceLevel)
            return Landed(offer: o, quote: q, units: n, landedUnitCost: q.landed / n)
        }.sorted { $0.landedUnitCost != $1.landedUnitCost ? $0.landedUnitCost < $1.landedUnitCost : $0.offer.id < $1.offer.id }
    }
}
