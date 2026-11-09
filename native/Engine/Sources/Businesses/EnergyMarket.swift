import Foundation
import GameCore
import Countries

/// The one global electricity price. Demand is the electricity use of every company (a big world baseline plus what the
/// player's companies really use, scaled by how busy they are); supply is the world's baseline plants plus the capacity of the
/// player's power plants. The price index (`Economy.power`, 1 = normal) drifts toward a target set by the demand/supply ratio, once a
/// week. A power plant sells at this price; every other company buys at it (the "power" overhead line, `SupplyCatalogue`).
/// The world baseline and the slow drift keep one player from steering it: a 30 MW plant moves the price by well under 1 %.
public enum EnergyMarket {
    /// Weekly MWh the rest of the world uses (and, at a ratio of 1, produces). Scaled by the economy's demand.
    public static let worldDemand = 400_000.0
    /// The baseline plants always on the grid; equal to demand at a normal economy, so the opening price is neutral.
    public static let worldSupply = 400_000.0
    /// Price per MWh at index 1 before inflation, as the plants price it (`EnergyModel.powerWeek`).
    public static let basePrice = 650.0
    /// Index band the price stays in, how fast it follows its target each week, and the weekly noise.
    public static let band: ClosedRange<Double> = 0.6...1.8
    public static let followRate = 0.08
    public static let noise = 0.01
    /// Price response to the ratio of demand to supply (1 = proportional).
    public static let sensitivity = 1.6
    /// The most the player's plants can add to supply, as a share of the world's baseline.
    public static let playerSupplyCap = 0.25

    /// The index the market is heading for at this demand and supply.
    public static func target(demand: Double, supply: Double) -> Double {
        guard demand > 0, supply > 0 else { return 1 }
        return clamp(pow(demand / supply, sensitivity), band.lowerBound, band.upperBound)
    }

    /// One week's step toward the target (`noise` is a standard normal draw).
    public static func step(index: Double, target: Double, noise z: Double) -> Double {
        clamp(index + (target - index) * followRate + z * noise, band.lowerBound, band.upperBound)
    }

    /// What a company really uses in a week, in MWh: its power line of the overhead, at today's activity, priced at the base rate.
    static func weeklyUse(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard co.status == .open, let line = SupplyCatalogue.lines(co, bd).first(where: { $0.id == "power" }) else { return 0 }
        let lastUtil = co.value("lastW")["util"]
        let util = lastUtil.isNull ? 0.6 : lastUtil.double
        let spend = CompanyCosts.fixedOverhead(co, bd, w) / max(0.01, w.inflationIndex) * line.share * SupplyCatalogue.activity(line, util: util)
        return max(0, spend / basePrice)
    }

    /// Capacity of the power plants that are built and open, in MWh a week.
    static func plantCapacity(_ co: Company, _ bd: Trade) -> Double {
        guard co.status == .open, bd.hasTrait("power") else { return 0 }
        return max(0, co.value("lastW")["cap"].double)
    }

    public struct Totals: Equatable, Sendable {
        public var demand: Double, supply: Double, playerUse: Double, playerPlants: Double
    }

    /// Demand and supply now, in MWh a week.
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

    /// The index the world's weekly step should head for; also keeps the totals for the snapshot. Called by `WorldWeek.economy`.
    public static func prepare(_ s: inout GameState, data: GameData) -> Double {
        let t = totals(s, data: data)
        var m = s.rest["emkt"] ?? .object([:])
        m["d"] = .number(t.demand); m["s"] = .number(t.supply); m["pu"] = .number(t.playerUse); m["pp"] = .number(t.playerPlants)
        s.rest["emkt"] = m
        return target(demand: t.demand, supply: t.supply)
    }

    /// Records the week's price so the market can say how it moved over 12 weeks.
    public static func record(_ s: inout GameState) {
        var m = s.rest["emkt"] ?? .object([:])
        var h = m["h"].array
        h.append(.number(s.economy.power))
        if h.count > 13 { h.removeFirst(h.count - 13) }
        m["h"] = .array(h)
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

    /// The other global goods the economy prices (index, 1 = normal).
    static func goods(_ e: Economy) -> [(String, Double)] { [("oil", e.oil), ("fuel", e.fuel), ("materials", e.materials), ("freight", e.freight)] }

    public enum Direction: String, Sendable { case up, down, flat }

    /// The market as the app shows it.
    public struct Snapshot: Equatable, Sendable {
        /// 1 = normal.
        public var priceIndex: Double
        /// The index 12 weeks ago (the oldest known if the game is younger).
        public var priceThen: Double
        /// Fractional change over those weeks.
        public var change: Double
        public var direction: Direction
        /// Price of a MWh now, in base money (before the country's price level).
        public var pricePerMWh: Double
        public var demandWord: String
        public var supplyWord: String
        /// "Tight", "Balanced" or "Plentiful".
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
        /// 1 = normal.
        public var index: Double
        /// Fractional change over 12 weeks.
        public var change: Double
        public var direction: Direction
    }

    /// The global goods card: electricity first, then every commodity the economy prices, each against 12 weeks ago.
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

    /// What a company's electricity line costs against normal: the factor the utility overhead is multiplied by.
    public static func costFactor(_ s: GameState) -> Double { s.economy.power }
}
