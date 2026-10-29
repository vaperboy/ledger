import Foundation
import GameCore

/// All business types of the game, in menu order, with their reference tables.
public final class TradeCatalog: TradeCatalogProviding, @unchecked Sendable {
    public let trades: [String: Trade]
    public let order: [String]
    public let tables: TradeTables

    public init(tradesJSON: JSONValue, tablesJSON: JSONValue) {
        tables = TradeTables(json: tablesJSON)
        var map: [String: Trade] = [:]
        for (k, v) in tradesJSON["trades"].object { map[k] = Trade(json: v) }
        for k in map.keys where !(map[k]!.hasStoredCalibration) { TradeCatalog.calibrate(&map[k]!, tables: tables) }
        trades = map
        order = tradesJSON["order"].array.map { $0.string }
    }

    public static func bundled() throws -> TradeCatalog {
        func load(_ name: String) throws -> JSONValue {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else { throw CocoaError(.fileNoSuchFile) }
            return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        }
        return TradeCatalog(tradesJSON: TradeTuning.apply(to: try load("trades"), tuning: TradeTuning.bundled()), tablesJSON: try load("tables"))
    }

    public subscript(id: String) -> Trade? { trades[id] }
    public func facts(for tradeID: String) -> TradeFacts? { trades[tradeID] }
    public var all: [Trade] { order.compactMap { trades[$0] } }

    // MARK: Calibration (original: `calib(bd)` in engine/company/company.js)

    /// Work out, from a trade's own data, how many customers it normally gets and can serve. A trade is "designed"
    /// at the reference country's cost level: its fixed costs (wages, rent, equipment wear, overhead, accountant)
    /// must be covered by a normal number of customers, and countries then scale prices, wages and rents.
    public static func calibrate(_ t: inout Trade, tables: TradeTables) {
        if ["rent", "fin", "energy", "club"].contains(t.family) {
            t.normalDemand = 0
            t.normalCapacity = 0
            return
        }
        let w52 = 12.0 / 52, oc = 1.166
        var wages = 0.0
        for s in t.standardStaff { wages += s.count * (tables.roles[s.role]?.baseMonthlyWage ?? 0) * w52 * oc * 1.2 }
        var rent = 0.0
        if let k = t.premisesKind, let p = tables.premises[k] { rent = t.premisesM2 * p.rentPerM2Year / 52 }
        var dep = 0.0
        for e in t.equipment {
            if let model = e.vehicleModels?.first, let v = tables.vehicles[model] {
                let vc0 = v.price * e.standardCount
                dep += vc0 * 0.15 / 52 + vc0 * 0.0143 / 52
            } else {
                dep += e.cost * e.standardCount / max(1, e.lifeYears) / 52 + e.cost * e.standardCount * 0.011 / 52
            }
        }
        let acct = 3400.0 * 12 / 52 * (t.needsLimitedCompany ? 1 : 0.3)
        let fit = (tables.fitOut[t.premisesKind ?? "none"] ?? 0) * t.premisesM2 / 10 / 52
        let F = wages + rent + dep + t.fixedWeekly + acct + (t.premisesKind == nil ? 0 : fit)
        let tw = t.traits
        var vc = t.costOfSales + (tw["perish"] ?? 0) * 0.6 + (tw["shrink"] ?? 0) * 0.3 + (tw["mat"] ?? 0)
        if let ota = tw["ota"], ota != 0 { vc += ota * 0.5 }
        t.weeklyFixedCosts = F
        t.variableCostShare = vc
        let den = t.ticket * max(0.12, 1 - vc - 0.028 - t.margin - 0.07)
        t.normalDemand = t.explicitDemand != 0 ? t.explicitDemand : F / den
        if t.family == "project" { t.normalDemand = F / den }
        // The original's round-8 balance pass serves customers at 95% of capacity (earlier drafts used 85%).
        t.normalCapacity = t.normalDemand / 0.95
    }
}
