import Foundation
import GameCore

/// Reference tables shared by all trades: job roles and base wages, kinds of premises, vehicle models,
/// seasonal demand curves, documents. Loaded from `tables.json`.
public struct TradeTables: Sendable {
    public struct Role: Sendable { public var name: String; public var baseMonthlyWage: Double }
    public struct Premises: Sendable {
        public var name: String
        /// Rent per m² per year at the reference level
        public var rentPerM2Year: Double
        /// Purchase price per m² at the reference level
        public var pricePerM2: Double
        public var note: String
    }
    public struct VehicleModel: Sendable {
        public var name: String
        public var price: Double
        public var kind: String
    }

    public var roles: [String: Role]
    public var premises: [String: Premises]
    public var vehicles: [String: VehicleModel]
    /// Twelve monthly demand multipliers per season key
    public var seasons: [String: [Double]]
    public var salesRoles: Set<String>
    /// Fit-out cost per m² by premises kind
    public var fitOut: [String: Double]
    public var raw: JSONValue

    public init(json t: JSONValue) {
        raw = t
        roles = t["ROLES"].object.mapValues { Role(name: $0[0].string, baseMonthlyWage: $0[1].double) }
        premises = t["PREM"].object.mapValues { Premises(name: $0[0].string, rentPerM2Year: $0[1].double, pricePerM2: $0[2].double, note: $0[3].string) }
        vehicles = t["VEH"].object.mapValues { VehicleModel(name: $0[0].string, price: $0[1].double, kind: $0[2].string) }
        seasons = t["SEAS"].object.mapValues { $0.array.map { $0.double } }
        salesRoles = Set(t["SALES_ROLES"].object.keys)
        fitOut = t["FIT"].object.mapValues { $0.double }
    }
}
