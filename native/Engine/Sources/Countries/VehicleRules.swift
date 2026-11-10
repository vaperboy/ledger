import Foundation
import GameCore

public struct VehicleRules: Equatable, Sendable {
    public var fuelPerLitre: Double?
    public var mileagePerKm: Double?
    public var motorInsuranceShare: Double?
    public var motorInsurancePerVehicle: Double?
    public var roadTaxPerYear: [String: Double] = [:]
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
