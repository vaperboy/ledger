import Foundation

public protocol WorldRulesSource: Sendable {
    func ruleValue(_ key: String) -> Double?
}

public struct WorldRules: Codable, Equatable, Sendable {
    public struct Limit: Equatable, Sendable {
        public var def: Double, min: Double, max: Double
    }

    public static let limits: [String: Limit] = [
        "print.single_limit": Limit(def: 0.05, min: 0.01, max: 0.10),
        "print.window_limit": Limit(def: 0.15, min: 0.03, max: 0.30),
        "print.window_weeks": Limit(def: 12, min: 4, max: 26),
        "tax.transfer_max": Limit(def: 0.05, min: 0.01, max: 0.10),
        "tax.gains_min": Limit(def: 0.05, min: 0, max: 0.15),
        "tax.gains_max": Limit(def: 0.40, min: 0.20, max: 0.60),
        "tax.step": Limit(def: 0.01, min: 0.005, max: 0.03),
        "tax.gap_weeks": Limit(def: 7, min: 1, max: 26),
        "band.exchange_low": Limit(def: 0.75, min: 0.50, max: 0.95),
        "band.exchange_high": Limit(def: 1.25, min: 1.05, max: 2.00),
        "band.startup_low": Limit(def: 0.80, min: 0.50, max: 0.95),
        "band.startup_high": Limit(def: 1.25, min: 1.05, max: 2.00),
        "band.venture_low": Limit(def: 0.70, min: 0.40, max: 0.95),
        "band.venture_high": Limit(def: 1.50, min: 1.05, max: 2.50),
        "power.band_low": Limit(def: 0.60, min: 0.30, max: 0.90),
        "power.band_high": Limit(def: 1.80, min: 1.20, max: 3.00),
        "support.percent_max": Limit(def: 0.10, min: 0.02, max: 0.20),
        "support.weeks_max": Limit(def: 8, min: 1, max: 16),
        "support.budget_share": Limit(def: 0.05, min: 0.01, max: 0.10),
        "support.max_open": Limit(def: 2, min: 1, max: 5),
        "support.account_share": Limit(def: 0.25, min: 0.05, max: 0.50)
    ]

    public static let defaults = WorldRules()

    public private(set) var values: [String: Double] = [:]

    public init() {}

    public init(snapshot: [String: Double]) {
        for (key, lim) in Self.limits {
            guard let v = snapshot[key], v.isFinite else { continue }
            values[key] = Swift.min(lim.max, Swift.max(lim.min, v))
        }
        if self["print.single_limit"] > self["print.window_limit"] { values["print.single_limit"] = nil; values["print.window_limit"] = nil }
        if self["tax.gains_min"] >= self["tax.gains_max"] { values["tax.gains_min"] = nil; values["tax.gains_max"] = nil }
    }

    public init(source: any WorldRulesSource) {
        var snap: [String: Double] = [:]
        for key in Self.limits.keys { if let v = source.ruleValue(key) { snap[key] = v } }
        self.init(snapshot: snap)
    }

    public subscript(_ key: String) -> Double { values[key] ?? Self.limits[key]?.def ?? 0 }

    public var printSingleLimit: Double { self["print.single_limit"] }
    public var printWindowLimit: Double { self["print.window_limit"] }
    public var printWindowWeeks: Int { Int(self["print.window_weeks"]) }

    public var transferTaxRange: ClosedRange<Double> { 0...self["tax.transfer_max"] }
    public var gainsTaxRange: ClosedRange<Double> { self["tax.gains_min"]...self["tax.gains_max"] }
    public var taxStep: Double { self["tax.step"] }
    public var taxGapWeeks: Int { Int(self["tax.gap_weeks"]) }

    public var exchangeBand: ClosedRange<Double> { self["band.exchange_low"]...self["band.exchange_high"] }
    public var startupBand: ClosedRange<Double> { self["band.startup_low"]...self["band.startup_high"] }
    public var ventureBand: ClosedRange<Double> { self["band.venture_low"]...self["band.venture_high"] }

    public var powerBand: ClosedRange<Double> { self["power.band_low"]...self["power.band_high"] }

    public var supportPercentRange: ClosedRange<Double> { 0.01...self["support.percent_max"] }
    public var supportWeeksMax: Int { Int(self["support.weeks_max"]) }
    public var supportBudgetShare: Double { self["support.budget_share"] }
    public var supportMaxOpen: Int { Int(self["support.max_open"]) }
    public var supportAccountShare: Double { self["support.account_share"] }
}

public extension GameState {
    var worldRules: WorldRules {
        get {
            var snap: [String: Double] = [:]
            for (k, v) in (rest["wrules"] ?? .null).object { snap[k] = v.double }
            return WorldRules(snapshot: snap)
        }
        set {
            var o: [String: JSONValue] = [:]
            for (k, v) in newValue.values { o[k] = .number(v) }
            if o.isEmpty { rest.removeValue(forKey: "wrules") } else { rest["wrules"] = .object(o) }
        }
    }
}
