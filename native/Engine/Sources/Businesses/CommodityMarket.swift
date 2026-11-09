import Foundation
import GameCore

public enum CommodityMarket {
    public static let key = "cmx"
    public static let playerCap = 0.25
    public static let followRate = 0.3

    public struct Def: Sendable {
        public var id: String
        public var name: String
        public var unit: String
        public var quote: Double
        public var world: Double
        public var revert: Double
        public var shock: Double
        public var band: ClosedRange<Double>
        public var producers: Set<String>
        public var users: [String: Double]
        public var boomDemand: Double
    }

    public static let defs: [Def] = [
        Def(id: "oil", name: "Crude oil", unit: "barrel", quote: 80, world: 30_000_000, revert: 0.02, shock: 0.03, band: 0.3...2.5, producers: ["oilgas"],
            users: ["trucking": 0.15, "shipping": 0.2, "airline": 0.25, "taxi": 0.15, "courier": 0.1], boomDemand: 0),
        Def(id: "fuel", name: "Fuel", unit: "litre", quote: 2, world: 20_000_000, revert: 0.03, shock: 0.02, band: 0.6...2.2, producers: [],
            users: ["trucking": 0.2, "shipping": 0.2, "airline": 0.2, "taxi": 0.2, "courier": 0.15, "carrental": 0.1], boomDemand: 0.1),
        Def(id: "materials", name: "Building and raw materials", unit: "tonne", quote: 120, world: 20_000_000, revert: 0.02, shock: 0.012, band: 0.75...1.6,
            producers: ["factory"], users: ["construction": 0.35, "electrician": 0.1, "plumber": 0.1, "hardware": 0.4, "realdev": 0.3, "furniture": 0.2], boomDemand: 0),
        Def(id: "salmon", name: "Salmon", unit: "kilo", quote: 9, world: 10_000_000, revert: 0.03, shock: 0.03, band: 0.55...1.8, producers: ["salmon"], users: [:], boomDemand: 0),
    ]

    public static let power = Def(id: "power", name: "Electricity", unit: "MWh", quote: EnergyMarket.basePrice, world: EnergyMarket.worldSupply, revert: 0, shock: 0,
                                  band: 0.6...1.8, producers: [], users: [:], boomDemand: 0)

    public static var listed: [Def] { defs + [power] }

    public static func def(_ id: String) -> Def? { listed.first { $0.id == id } }

    public static func index(_ s: GameState, _ id: String) -> Double {
        switch id {
        case "oil": return s.economy.oil
        case "fuel": return s.economy.fuel
        case "materials": return s.economy.materials
        case "salmon": return s.economy.salmon
        case "power": return s.economy.power
        default: return 1
        }
    }

    public static func price(_ s: GameState, _ id: String) -> Double? {
        guard let d = def(id) else { return nil }
        return d.quote * index(s, id) * s.economy.inflationIndex
    }

    public struct Flows: Equatable, Sendable {
        public var demand: Double
        public var supply: Double
    }

    public static func flows(_ s: GameState, _ d: Def, shock z: Double) -> Flows {
        let infl = max(0.01, s.economy.inflationIndex)
        var made = 0.0, used = 0.0
        for co in s.companies where co.status == .open {
            let rev = co.lastWeekRevenue / infl
            if d.producers.contains(co.type) { made += rev }
            if let share = d.users[co.type] { used += rev * share }
        }
        let cap = d.world * playerCap
        let boom = s.economy.phase == "boom" ? 1 + d.boomDemand : 1
        return Flows(demand: d.world * boom + min(used, cap), supply: d.world * exp(z) + min(made, cap))
    }

    public static func target(demand: Double, supply: Double, band: ClosedRange<Double>) -> Double {
        guard demand > 0, supply > 0 else { return 1 }
        return clamp(demand / supply, band.lowerBound, band.upperBound)
    }

    public static func step(_ s: inout GameState, economy E: inout Economy) {
        var store = s.rest[key] ?? .object([:])
        for d in defs {
            var z = store[d.id]["z"].double
            z += -d.revert * z + s.random.gauss() * d.shock
            store[d.id] = .object(["z": .number(z)])
            let f = flows(s, d, shock: -z)
            let now = index(s, d.id)
            let next = clamp(now + (target(demand: f.demand, supply: f.supply, band: d.band) - now) * followRate, d.band.lowerBound, d.band.upperBound)
            switch d.id {
            case "oil": E.oil = next
            case "fuel": E.fuel = next
            case "materials": E.materials = next
            default: E.salmon = next
            }
        }
        s.rest[key] = store
    }
}
