import Foundation
import GameCore
import Countries

public enum EnergyMarket {
    public static let worldDemand = 400_000.0
    public static let worldSupply = 400_000.0
    public static let basePrice = 650.0
    public static let band: ClosedRange<Double> = 0.6...1.8
    public static let followRate = 0.08
    public static let noise = 0.01
    public static let sensitivity = 1.6
    public static let playerSupplyCap = 0.25
    public static let alertMove = 0.15

    public static func target(demand: Double, supply: Double, band: ClosedRange<Double> = EnergyMarket.band) -> Double {
        guard demand > 0, supply > 0 else { return 1 }
        return clamp(pow(demand / supply, sensitivity), band.lowerBound, band.upperBound)
    }

    public static func step(index: Double, target: Double, noise z: Double, band: ClosedRange<Double> = EnergyMarket.band) -> Double {
        clamp(index + (target - index) * followRate + z * noise, band.lowerBound, band.upperBound)
    }

    static func weeklyUse(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard co.status == .open, let line = SupplyCatalogue.lines(co, bd).first(where: { $0.id == "power" }) else { return 0 }
        let lastUtil = co.value("lastW")["util"]
        let util = lastUtil.isNull ? 0.6 : lastUtil.double
        let spend = CompanyCosts.fixedOverhead(co, bd, w) / max(0.01, w.inflationIndex) * line.share * SupplyCatalogue.activity(line, util: util)
        return max(0, spend / basePrice)
    }

    static func plantCapacity(_ co: Company, _ bd: Trade) -> Double {
        guard co.status == .open, bd.hasTrait("power") else { return 0 }
        return max(0, co.value("lastW")["cap"].double)
    }

    public struct Totals: Equatable, Sendable {
        public var demand: Double, supply: Double, playerUse: Double, playerPlants: Double
    }

    public static func totals(_ s: GameState, data: GameData) -> Totals {
        let w = World(state: s, data: data)
        var use = 0.0, plants = 0.0
        for co in s.companies {
            guard let bd = data.catalog[co.type] else { continue }
            use += weeklyUse(co, bd, w)
            plants += plantCapacity(co, bd)
        }
        plants = min(plants, worldSupply * playerSupplyCap)
        return Totals(demand: worldDemand * s.economy.demand + use, supply: worldSupply + plants, playerUse: use, playerPlants: plants)
    }

    public static func prepare(_ s: inout GameState, data: GameData) -> Double {
        let t = totals(s, data: data)
        var m = s.rest["emkt"] ?? .object([:])
        m["d"] = .number(t.demand); m["s"] = .number(t.supply); m["pu"] = .number(t.playerUse); m["pp"] = .number(t.playerPlants)
        s.rest["emkt"] = m
        return target(demand: t.demand, supply: t.supply, band: s.worldRules.powerBand)
    }

    public static func record(_ s: inout GameState) {
        var m = s.rest["emkt"] ?? .object([:])
        var h = m["h"].array
        h.append(.number(s.economy.power))
        if h.count > 13 { h.removeFirst(h.count - 13) }
        m["h"] = .array(h)
        if h.count > 12, let then = h.first?.double, then > 0 {
            let change = s.economy.power / then - 1
            let lastAlert = m["al"].isNull ? -1_000 : m["al"].int
            if abs(change) >= alertMove, s.week - lastAlert >= 12 {
                m["al"] = .number(Double(s.week))
                let pct = Int((abs(change) * 100).rounded())
                s.news(change > 0 ? "Electricity is \(pct)% dearer than three months ago. Companies that use a lot of power pay more." : "Electricity is \(pct)% cheaper than three months ago. Companies that use a lot of power pay less.",
                       tone: change > 0 ? "bad" : "good")
            }
        }
        var x = m["x"].object
        for (k, v) in goods(s.economy) {
            var a = (x[k] ?? .array([])).array
            a.append(.number(v))
            if a.count > 13 { a.removeFirst(a.count - 13) }
            x[k] = .array(a)
        }
        m["x"] = .object(x)
        s.rest["emkt"] = m
    }

    static func goods(_ e: Economy) -> [(String, Double)] { [("oil", e.oil), ("fuel", e.fuel), ("materials", e.materials), ("freight", e.freight)] }

    public enum Direction: String, Sendable { case up, down, flat }

    public struct Snapshot: Equatable, Sendable {
        public var priceIndex: Double
        public var priceThen: Double
        public var change: Double
        public var direction: Direction
        public var pricePerMWh: Double
        public var demandWord: String
        public var supplyWord: String
        public var balanceWord: String
        public var summary: String
    }

    public static func direction(change: Double) -> Direction { change > 0.02 ? .up : change < -0.02 ? .down : .flat }

    public static func snapshot(_ s: GameState, data: GameData? = nil) -> Snapshot {
        let m = s.rest["emkt"] ?? .object([:])
        let h = m["h"].array.map { $0.double }
        let now = s.economy.power
        let then = h.count > 12 ? h[h.count - 13] : (h.first ?? now)
        let change = then > 0 ? now / then - 1 : 0
        let demand = m["d"].isNull ? worldDemand * s.economy.demand : m["d"].double
        let supply = m["s"].isNull ? worldSupply : m["s"].double
        let ratio = supply > 0 ? demand / supply : 1
        let dWord = ratio > 1.06 ? "Very high" : ratio > 1.02 ? "High" : ratio < 0.94 ? "Low" : ratio < 0.98 ? "Soft" : "Normal"
        let sWord = ratio > 1.06 ? "Short" : ratio > 1.02 ? "Tight" : ratio < 0.94 ? "Ample" : ratio < 0.98 ? "Comfortable" : "Steady"
        let bal = ratio > 1.02 ? "Tight" : ratio < 0.98 ? "Plentiful" : "Balanced"
        let say: String
        switch bal {
        case "Tight": say = "Demand is running ahead of supply, so electricity costs more."
        case "Plentiful": say = "Supply is ahead of demand, so electricity is cheaper."
        default: say = "Supply and demand are about level."
        }
        return Snapshot(priceIndex: now, priceThen: then, change: change, direction: direction(change: change), pricePerMWh: basePrice * now * s.economy.inflationIndex,
                        demandWord: dWord, supplyWord: sWord, balanceWord: bal, summary: say)
    }

    public struct PriceRow: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var index: Double
        public var change: Double
        public var direction: Direction
    }

    public static func worldPrices(_ s: GameState) -> [PriceRow] {
        let e = snapshot(s)
        var rows = [PriceRow(id: "power", name: "Electricity", index: e.priceIndex, change: e.change, direction: e.direction)]
        let x = (s.rest["emkt"] ?? .object([:]))["x"]
        let names = ["oil": "Oil", "fuel": "Fuel", "materials": "Building and raw materials", "freight": "Freight"]
        for (k, now) in goods(s.economy) {
            let h = x[k].array.map { $0.double }
            let then = h.count > 12 ? h[h.count - 13] : (h.first ?? now)
            let ch = then > 0 ? now / then - 1 : 0
            rows.append(PriceRow(id: k, name: names[k] ?? k, index: now, change: ch, direction: direction(change: ch)))
        }
        return rows
    }

    public static func costFactor(_ s: GameState) -> Double { s.economy.power }
}
