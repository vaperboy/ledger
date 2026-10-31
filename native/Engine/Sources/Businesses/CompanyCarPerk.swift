import Foundation
import GameCore
import Countries
import Finance

/// The "Company car" perk with a real vehicle behind it. Each recipient (the manager and the team leads) drives a leased car that sits in the
/// company's vehicle list like any other (`veh`, marked `perk`): the lease is paid weekly with the other leases (`CompanyWeek`), the car
/// burns fuel and turns its odometer in `CompanyCosts.equipmentWeek`, breaks down, and shows in the Fleet screen with the name of its driver.
/// So the perk costs what the vehicle machinery says, not a flat number a head. When a lead leaves, the car goes back; a new lead gets one.
public enum CompanyCarPerk {
    public static let equipmentID = "perkcar"
    /// The model every perk car is leased as (a small car; electric cars are bought as company vehicles, not as a perk).
    public static let model = "car_s"
    /// Data record kept in the vehicle: "m" for the manager, else the team lead's staff id.
    static func key(forStaff id: Int) -> String { "s\(id)" }

    public struct Recipient: Equatable, Sendable, Identifiable {
        public var id: String           // vehicle key
        public var name: String
        public var role: String         // "Manager" or the staff role id
        public var carName: String?     // nil while the car has not arrived yet
        public var monthlyLease: Double
    }

    public static var spec: EquipmentSpec {
        EquipmentSpec(id: equipmentID, name: "Company cars (perk)", cost: 0, lifeYears: 5, standardCount: 0, flags: "v", vehicleModels: [model])
    }

    /// The manager and the team leads, who each get a car while the perk is on.
    static func wanted(_ s: GameState, _ co: Company) -> [(key: String, name: String, role: String)] {
        var out: [(String, String, String)] = []
        if let m = co.managerID { out.append(("m", s.people[m]?.name ?? "Manager", "Manager")) }
        for st in co.staff where st.role == "lead" && st.noticeWeeks <= 0 { out.append((key(forStaff: st.id), s.people[st.id]?.name ?? "Team lead", st.role)) }
        return out
    }

    public static func recipients(_ s: GameState, companyID: Int) -> [Recipient] {
        guard let co = s.company(companyID), StaffPerks.isOn(co, "car") else { return [] }
        let cars = co.value("veh").array.filter { !$0["perk"].isNull }
        return wanted(s, co).map { w in
            let car = cars.first { $0["perk"].string == w.key }
            return Recipient(id: w.key, name: w.name, role: w.role, carName: car.map { $0["name"].string }, monthlyLease: car?["lease"].double ?? 0)
        }
    }

    /// Lease plus fuel a month of the cars that are there; recipients still waiting for a car are priced from the model when `data` is given.
    public static func monthlyCost(_ co: Company, currency cur: Currency, country: Country? = nil, data: GameData? = nil, week: Int = 0, inflation: Double = 1,
                                   missing: Int = 0, fuelIndex: Double = 1) -> Double {
        var total = 0.0
        for v in co.value("veh").array where !v["perk"].isNull {
            total += v["lease"].double
            if let data, let country { total += fuelMonthly(model: v["model"].string, tables: data.catalog.tables, country: country, cur: cur, fuelIndex: fuelIndex) }
        }
        if missing > 0, let data, let country, let v = data.catalog.tables.vehicles[model] {
            let price = jsRound(roundTo(v.price * inflation, step: 1000))
            total += Double(missing) * (jsRound(price * 0.0215) + fuelMonthly(model: model, tables: data.catalog.tables, country: country, cur: cur, fuelIndex: fuelIndex))
        }
        return total
    }

    /// What the perk costs a month for this company now, priced through the vehicle table.
    public static func monthlyCost(_ s: GameState, _ co: Company, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let have = Set(co.value("veh").array.compactMap { $0["perk"].isNull ? nil : $0["perk"].string })
        let missing = wanted(s, co).filter { !have.contains($0.key) }.count
        return monthlyCost(co, currency: w.currency(co), country: w.country(co), data: data, inflation: w.inflationIndex, missing: missing, fuelIndex: s.economy.fuel)
    }

    static func fuelMonthly(model: String, tables: TradeTables, country: Country, cur: Currency, fuelIndex: Double) -> Double {
        let km = tables.raw["RUNNING"]["defaultKmPerWeek"].double
        return km * VehicleRunning.fuelPerKm(model: model, tables: tables, country: country, currency: cur, fuelIndex: fuelIndex) * 52 / 12
    }

    /// Take every perk car back (the perk was switched off and no price data is at hand).
    public static func release(_ s: inout GameState, companyIndex i: Int) {
        var veh = s.companies[i].value("veh").array
        let n = veh.count
        veh.removeAll { !$0["perk"].isNull }
        if veh.count != n { s.companies[i].set("veh", .array(veh)) }
    }

    /// Give every recipient a leased car and take back the cars of people who no longer qualify (or all of them when the perk is off).
    public static func sync(_ s: inout GameState, companyIndex i: Int, data: GameData) {
        let co = s.companies[i]
        let on = StaffPerks.isOn(co, "car")
        let want = on ? wanted(s, co) : []
        let wantKeys = Set(want.map { $0.key })
        var veh = co.value("veh").array
        let before = veh.count
        veh.removeAll { !$0["perk"].isNull && !wantKeys.contains($0["perk"].string) }
        if veh.count != before { s.companies[i].set("veh", .array(veh)) }
        guard on, let v = data.catalog.tables.vehicles[model] else { return }
        let have = Set(veh.compactMap { $0["perk"].isNull ? nil : $0["perk"].string })
        let w = World(state: s, data: data)
        for r in want where !have.contains(r.key) {
            let price = jsRound(roundTo(v.price * w.inflationIndex, step: 1000))
            guard CompanySetup.addVehicle(&s, companyIndex: i, spec, model: model, modelName: v.name, price: price, mode: "lease", brand: nil, data: data) else { continue }
            var list = s.companies[i].value("veh").array
            list[list.count - 1]["perk"] = .string(r.key)
            list[list.count - 1]["driver"] = .string(r.name)
            s.companies[i].set("veh", .array(list))
        }
    }
}
