import Foundation
import GameCore
import Countries
import Finance

public enum VehicleRunning {
    public static func kmPerWeek(_ bd: Trade, tables: TradeTables) -> Double {
        bd.trait("km") ?? tables.raw["RUNNING"]["defaultKmPerWeek"].double
    }

    public static func companyPaysFuelLine(_ bd: Trade) -> Bool { !bd.hasTrait("fuel") && !bd.hasTrait("custFuel") }

    static func isRoad(model: String, tables: TradeTables) -> Bool {
        guard let k = tables.vehicles[model]?.kind else { return false }
        return tables.raw["RUNNING"]["roadKinds"].array.contains { $0.string == k }
    }

    public static func fuelPerKm(model: String, tables: TradeTables, country: Country, currency: Currency, fuelIndex: Double) -> Double {
        let intensity = tables.raw["VEH"][model][4].double
        let litres = intensity * tables.raw["RUNNING"]["litresPerFuelUnitKm"].double
        let price = country.vehicleRules.fuelPerLitre ?? currency.scaledPrice(tables.raw["RUNNING"]["referenceLitrePrice"].double)
        return litres * price * fuelIndex
    }

    public static func weeklyFuel(model: String, bd: Trade, util: Double, tables: TradeTables, country: Country, currency: Currency, fuelIndex: Double) -> Double {
        guard companyPaysFuelLine(bd), isRoad(model: model, tables: tables) else { return 0 }
        return kmPerWeek(bd, tables: tables) * util * fuelPerKm(model: model, tables: tables, country: country, currency: currency, fuelIndex: fuelIndex)
    }

    public static func vehicleWeek(_ v: JSONValue, bd: Trade, util: Double, tables: TradeTables, country: Country, currency: Currency, fuelIndex: Double) -> (km: Double, fuel: Double) {
        let model = v["model"].string
        if !v["perk"].isNull {
            let km = tables.raw["RUNNING"]["defaultKmPerWeek"].double * util
            return (km, km * fuelPerKm(model: model, tables: tables, country: country, currency: currency, fuelIndex: fuelIndex))
        }
        return (kmPerWeek(bd, tables: tables) * util, weeklyFuel(model: model, bd: bd, util: util, tables: tables, country: country, currency: currency, fuelIndex: fuelIndex))
    }

    static func isElectric(_ model: String, tables: TradeTables) -> Bool { tables.raw["RUNNING"]["electricModels"].array.contains { $0.string == model } }

    public struct Charges: Equatable, Sendable {
        public var insurance = 0.0, vehicleTax = 0.0, benefitCharge = 0.0
        public var total: Double { insurance + vehicleTax + benefitCharge }
    }

    public static func weeklyCharges(_ s: GameState, _ co: Company, data: GameData) -> Charges {
        let w = World(state: s, data: data)
        let c = w.country(co), rules = c.vehicleRules, tables = data.catalog.tables
        var out = Charges()
        for v in co.value("veh").array where isRoad(model: v["model"].string, tables: tables) {
            let model = v["model"].string
            if let share = rules.motorInsuranceShare { out.insurance += v["cost"].double * share / 52 }
            else if let per = rules.motorInsurancePerVehicle { out.insurance += per / 52 }
            if let tax = rules.roadTaxPerYear[tables.vehicles[model]?.kind ?? ""] { out.vehicleTax += tax / 52 }
            guard !v["perk"].isNull else { continue }
            let share = isElectric(model, tables: tables) ? (rules.benefitInKindEVShare ?? rules.benefitInKindShare) : rules.benefitInKindShare
            guard let share else { continue }
            let key = v["perk"].string
            let wage = key == "m" ? co.managerMonthlyWage : (co.staff.first { "s\($0.id)" == key }?.monthlyWage ?? 0)
            let rate = c.employerOnCost(monthlyWage: wage)
            out.benefitCharge += v["cost"].double * share / 52 * rate
        }
        return out
    }

    static func payCharges(_ s: inout GameState, companyIndex i: Int, data: GameData) {
        let co = s.companies[i]
        let c = weeklyCharges(s, co, data: data)
        if c.insurance > 0 { Payments.companyPays(&s, companyID: co.id, amount: c.insurance, category: "ins", label: "Motor insurance") }
        if c.vehicleTax > 0 { Payments.companyPays(&s, companyID: co.id, amount: c.vehicleTax, category: "oth", label: "Vehicle tax") }
        if c.benefitCharge > 0 { Payments.companyPays(&s, companyID: co.id, amount: c.benefitCharge, category: "wages", label: "Employer charges on company cars") }
    }

    public struct FleetCosts: Equatable, Sendable {
        public var fuel = 0.0, leases = 0.0
        public var charges = Charges()
        public var total: Double { fuel + leases + charges.total }
    }

    public static func fleetCosts(_ s: GameState, companyID: Int, data: GameData) -> FleetCosts {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return FleetCosts() }
        let w = World(state: s, data: data), tables = data.catalog.tables
        var out = FleetCosts()
        for v in co.value("veh").array {
            let perk = !v["perk"].isNull
            if perk { out.fuel += fuelPerKm(model: v["model"].string, tables: tables, country: w.country(co), currency: w.currency(co), fuelIndex: s.economy.fuel) * tables.raw["RUNNING"]["defaultKmPerWeek"].double }
            else { out.fuel += weeklyFuel(model: v["model"].string, bd: bd, util: 1, tables: tables, country: w.country(co), currency: w.currency(co), fuelIndex: s.economy.fuel) }
            if v["mode"].string == "lease" { out.leases += v["lease"].double * 12 / 52 }
        }
        out.charges = weeklyCharges(s, co, data: data)
        return out
    }
}
