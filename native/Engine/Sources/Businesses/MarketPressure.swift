import Foundation
import GameCore

public enum MarketPressure {
    public static let rampWeeks = 4
    static let liftKey = "lift27"
    public static let liftCap = 0.15
    static let floorMultiplier = 0.7
    static let ceilMultiplier = 1.1

    public static func addedLift(_ co: Company, category: Bool, rivalCount: Int) -> Double {
        let base = category ? 0.05 : 0.02
        return max(0, min(base / (1 + 0.25 * Double(rivalCount)), liftCap - totalLift(co)))
    }

    static func totalLift(_ co: Company) -> Double { co.value("lift27").array.reduce(0) { $0 + $1["f"].double } }

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

    public enum Kind: String, Sendable { case launch, response, country, gain }

    static func add(_ s: inout GameState, _ i: Int, kind: Kind, amount: Double, weeks: Int, rivalID: Int = 0) {
        guard amount != 0, weeks > 0 else { return }
        var list = s.companies[i].value("pr27").array.filter { s.week - $0["w0"].int < $0["n"].int }
        list.append(.object(["k": .string(kind.rawValue), "w0": .number(Double(s.week)), "n": .number(Double(weeks)), "a": .number(amount), "r": .number(Double(rivalID))]))
        s.companies[i].set("pr27", .array(list))
    }

    static func remaining(_ e: JSONValue, week: Int) -> Double {
        let n = max(1, e["n"].double)
        return e["a"].double * max(0, 1 - Double(week - e["w0"].int) / n)
    }

    public static func pressure(_ co: Company, week: Int, kind: Kind? = nil) -> Double {
        co.value("pr27").array.reduce(0.0) { acc, e in (kind == nil || e["k"].string == kind!.rawValue) ? acc + remaining(e, week: week) : acc }
    }

    public static func demandMultiplier(_ co: Company, week: Int) -> Double {
        let lift = liftFactor(co, week: week)
        let list = co.value("pr27").array
        guard !list.isEmpty else { return lift }
        return lift * clamp(1 - pressure(co, week: week), floorMultiplier, ceilMultiplier)
    }

    static func prune(_ s: inout GameState) {
        for i in s.companies.indices {
            let list = s.companies[i].value("pr27").array
            if list.isEmpty { continue }
            let keep = list.filter { s.week - $0["w0"].int < $0["n"].int }
            if keep.count != list.count { s.companies[i].set("pr27", keep.isEmpty ? .null : .array(keep)) }
        }
    }
}
