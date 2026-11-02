import Foundation
import GameCore

/// Real demand effects that come from the market, not from the company's own price: the lift from a newly added item (ramping in, then kept)
/// and pressure from rivals (a launch, a price reaction, a rival group entering the country; decaying linearly to nothing).
/// Both are read by `Pricing.demandEffect` through `demandMultiplier`, which is exactly 1 for a company with nothing stored, so a game that
/// never adds an item and meets no pressure plays as before. Stored on the company: `lift27` = [{ w0, f }], `pr27` = [{ k, w0, n, a, r }].
/// See DECISIONS.md "Market pressure and item lift".
public enum MarketPressure {
    /// Weeks a new item's lift takes to enter demand in full.
    public static let rampWeeks = 4
    static let liftKey = "lift27"
    /// The most that added items can lift demand in total (a share of weekly units).
    public static let liftCap = 0.15
    /// Pressure never takes more than this much of demand; a gain never gives more than the other limit.
    static let floorMultiplier = 0.7
    static let ceilMultiplier = 1.1

    // MARK: Added items

    /// Demand lift the next added item brings: 2 percent of weekly units for a variant, 5 percent for a new category, divided by 1 + 0.25 per rival,
    /// and never beyond what is left of the total cap. The estimate in `NewItemOptions` and the real game both use this one function.
    public static func addedLift(_ co: Company, category: Bool, rivalCount: Int) -> Double {
        let base = category ? 0.05 : 0.02
        return max(0, min(base / (1 + 0.25 * Double(rivalCount)), liftCap - totalLift(co)))
    }

    static func totalLift(_ co: Company) -> Double { co.value("lift27").array.reduce(0) { $0 + $1["f"].double } }

    /// The lift in force in a given week: each addition counts linearly over `rampWeeks`.
    public static func liftFactor(_ co: Company, week: Int) -> Double {
        let list = co.value("lift27").array
        guard !list.isEmpty else { return 1 }
        return 1 + list.reduce(0.0) { $0 + $1["f"].double * min(1, max(0, Double(week - $1["w0"].int)) / Double(rampWeeks)) }
    }

    static func addLift(_ s: inout GameState, _ i: Int, lift: Double) {
        guard lift > 0 else { return }
        var list = s.companies[i].value("lift27").array
        list.append(.object(["w0": .number(Double(s.week)), "f": .number(lift)]))
        s.companies[i].set("lift27", .array(list))
    }

    // MARK: Pressure from rivals

    public enum Kind: String, Sendable { case launch, response, country, gain }

    /// Add a demand pressure of `amount` (a share of demand; negative = a gain) that fades to nothing over `weeks`.
    static func add(_ s: inout GameState, _ i: Int, kind: Kind, amount: Double, weeks: Int, rivalID: Int = 0) {
        guard amount != 0, weeks > 0 else { return }
        var list = s.companies[i].value("pr27").array.filter { s.week - $0["w0"].int < $0["n"].int }
        list.append(.object(["k": .string(kind.rawValue), "w0": .number(Double(s.week)), "n": .number(Double(weeks)), "a": .number(amount), "r": .number(Double(rivalID))]))
        s.companies[i].set("pr27", .array(list))
    }

    /// Remaining pressure of one entry in a given week.
    static func remaining(_ e: JSONValue, week: Int) -> Double {
        let n = max(1, e["n"].double)
        return e["a"].double * max(0, 1 - Double(week - e["w0"].int) / n)
    }

    /// Total pressure on a company in a week (positive takes demand away), optionally only one kind.
    public static func pressure(_ co: Company, week: Int, kind: Kind? = nil) -> Double {
        co.value("pr27").array.reduce(0.0) { acc, e in (kind == nil || e["k"].string == kind!.rawValue) ? acc + remaining(e, week: week) : acc }
    }

    /// The factor on a company's demand from added items and rival pressure. Exactly 1 when nothing is stored.
    public static func demandMultiplier(_ co: Company, week: Int) -> Double {
        let lift = liftFactor(co, week: week)
        let list = co.value("pr27").array
        guard !list.isEmpty else { return lift }
        return lift * clamp(1 - pressure(co, week: week), floorMultiplier, ceilMultiplier)
    }

    /// Old entries are dropped at the end of the week.
    static func prune(_ s: inout GameState) {
        for i in s.companies.indices {
            let list = s.companies[i].value("pr27").array
            if list.isEmpty { continue }
            let keep = list.filter { s.week - $0["w0"].int < $0["n"].int }
            if keep.count != list.count { s.companies[i].set("pr27", keep.isEmpty ? .null : .array(keep)) }
        }
    }
}
