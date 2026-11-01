import Foundation
import GameCore

/// What a country's data says about running vehicles. Every field is optional: a country that has no sourced figure leaves it out and
/// the mechanism stays inactive (neutral) there. Amounts are written in the country's own currency in `countries.json` (block
/// `vehicles`) and converted to accounting units here. Gaps are listed in docs/KNOWN_GAPS.md and docs/TAX_SOURCES.md.
public struct VehicleRules: Equatable, Sendable {
    /// Price of a litre of fuel (or the energy equivalent), accounting units.
    public var fuelPerLitre: Double?
    /// What an employer may pay a person for a business kilometre in their own car, accounting units.
    public var mileagePerKm: Double?
    /// Motor insurance a year as a share of the vehicle's value.
    public var motorInsuranceShare: Double?
    /// Motor insurance a year for each vehicle, accounting units (used when no share is given).
    public var motorInsurancePerVehicle: Double?
    /// Annual vehicle tax by class of vehicle (`car`, `van`, `truck`, `bus`, `bike`), accounting units a year.
    public var roadTaxPerYear: [String: Double] = [:]
    /// Taxable benefit of a company car that a person also uses privately: share of the vehicle's list price a year, and the same for
    /// electric models. Feeds the employer's payroll charges.
    public var benefitInKindShare: Double?
    public var benefitInKindEVShare: Double?

    public static let none = VehicleRules()
    public init() {}

    public init(pack p: JSONValue) {
        let fx = p["fx"].double
        let v = p["vehicles"]
        func num(_ k: String) -> Double? { v[k].isNull ? nil : v[k].double }
        fuelPerLitre = num("fuelPerLitre").map { $0 * fx }
        mileagePerKm = num("mileagePerKm").map { $0 * fx }
        motorInsuranceShare = num("motorInsuranceShare")
        motorInsurancePerVehicle = num("motorInsurancePerVehicle").map { $0 * fx }
        roadTaxPerYear = v["roadTaxPerYear"].object.mapValues { $0.double * fx }
        benefitInKindShare = v["bik"]["share"].isNull ? nil : v["bik"]["share"].double
        benefitInKindEVShare = v["bik"]["evShare"].isNull ? nil : v["bik"]["evShare"].double
    }
}
