import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation
import Employees

/// Vehicles for the trades whose people really travel, the running costs of every vehicle, the company-car perk with a real car behind it,
/// own car with mileage beyond estate agents, and the country data blocks for motor insurance, road tax and benefit in kind.
final class VehiclesTravelTests: XCTestCase {
    /// The rule recorded in docs/KNOWN_GAPS.md: sales reps get a car each, visiting professionals a car per three, goods that leave by road a vehicle.
    static let salesRepTrades = ["mktg", "staffing", "factory", "vineyard", "brewery", "furniture", "hardware", "event"]
    static let visitingTrades = ["cons", "photo", "law", "acctfirm", "engcons"]
    static let deliveryTrades = ["farm", "factory", "vineyard"]
    static let noVehicleTrades = ["barber", "cafe", "restaurant", "tutor", "webdev", "gym", "hotel", "kiosk", "boutique", "grocery", "dental", "physio", "carrepair", "bank"]

    func catalog() throws -> TradeCatalog { try TradeCatalog.bundled() }

    func vehicleSpecs(_ t: Trade) -> [EquipmentSpec] { t.equipment.filter { $0.vehicleModels != nil } }

    func testSalesRepsVisitorsAndDeliveriesGetVehicleEquipment() throws {
        let cat = try catalog()
        for id in Self.salesRepTrades {
            let t = try XCTUnwrap(cat[id])
            let car = try XCTUnwrap(t.equipment.first { $0.id == "rcar" }, "\(id) needs sales cars")
            XCTAssertNotNil(car.vehicleModels)
            XCTAssertEqual(car.personalRule?.roles, ["sales"], id)
            XCTAssertGreaterThan(car.standardCount, 0, id)
        }
        for id in Self.visitingTrades {
            let car = try XCTUnwrap(try XCTUnwrap(cat[id]).equipment.first { $0.id == "vcar" }, "\(id) needs a visiting car")
            XCTAssertNotNil(car.personalRule, id)
        }
        for id in Self.deliveryTrades { XCTAssertFalse(vehicleSpecs(try XCTUnwrap(cat[id])).isEmpty, "\(id) ships goods by road") }
        for id in Self.noVehicleTrades { XCTAssertTrue(vehicleSpecs(try XCTUnwrap(cat[id])).isEmpty, "\(id) has no reason for a vehicle") }
    }

    func testEveryVehicleSpecNamesKnownModelsAndRolesThatExist() throws {
        let cat = try catalog()
        for t in cat.all { for e in t.equipment {
            for m in e.vehicleModels ?? [] { XCTAssertNotNil(cat.tables.vehicles[m], "\(t.id).\(e.id) model \(m)") }
            for r in e.personalRule?.roles ?? [] { XCTAssertNotNil(cat.tables.roles[r], "\(t.id).\(e.id) role \(r)") }
        } }
    }

    func testANewSalesRepCompanyBuysItsCarsAndTheirNumberLimitsTheReps() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 5)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "staffing", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 8_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertTrue(co.value("veh").array.contains { $0["eq"].string == "rcar" }, "the sales cars are bought with the rest of the equipment")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Running costs

    func startedCompany(_ trade: String, country: String = "UK", seed: Int = 5, fund: Double = 8_000_000) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: fund)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        XCTAssertNotEqual(id, 0, trade)
        return (e, id)
    }

    /// Cash a week of wear and running costs takes from the company at a given fuel price.
    func weekCost(_ e: GameEngine, _ id: Int, fuelIndex: Double, util: Double) -> (cash: Double, km: Double) {
        var s = e.state
        s.economy.fuel = fuelIndex
        let i = s.companyIndex(id)!
        let before = s.companies[i].cash
        let km0 = s.companies[i].value("veh").array.reduce(0) { $0 + $1["km"].double }
        CompanyCosts.equipmentWeek(&s, companyIndex: i, utilisation: util, e.data.catalog[s.companies[i].type]!, data: e.data)
        return (before - s.companies[i].cash, s.companies[i].value("veh").array.reduce(0) { $0 + $1["km"].double } - km0)
    }

    /// Fuel is a standard-rated purchase: the bank pays net plus input VAT (reclaimed later by a registered company); sales-tax countries add none.
    /// The exact cash a fuel bill of `net` costs: the bank pays the net rounded to whole money (Payments.companyPays) plus Vat.input's
    /// jsRound(net * standard rate) on the unrounded net, so the bill is not simply net * (1 + vat).
    private func fuelBill(_ net: Double, _ c: Country) -> Double { jsRound(net) + (c.usesSalesTax ? 0 : jsRound(net * c.vat.standard)) }

    func testAPlumberPaysFuelForTheKilometresItsOdometerCounts() throws {
        let (e, id) = try startedCompany("plumber")
        let co = try XCTUnwrap(e.state.company(id))
        let bd = try XCTUnwrap(e.data.catalog["plumber"])
        let vans = co.value("veh").array
        XCTAssertFalse(vans.isEmpty)
        let util = 0.8
        let one = weekCost(e, id, fuelIndex: 1, util: util), two = weekCost(e, id, fuelIndex: 2, util: util)
        let w = World(state: e.state, data: e.data)
        let perKm = vans.reduce(0.0) { $0 + VehicleRunning.fuelPerKm(model: $1["model"].string, tables: e.data.catalog.tables, country: w.country(co), currency: w.currency(co), fuelIndex: 1) }
        let km = VehicleRunning.kmPerWeek(bd, tables: e.data.catalog.tables) * util
        XCTAssertEqual(one.km, km * Double(vans.count), accuracy: 1e-6, "the odometer turns by the trait's kilometres for every vehicle")
        XCTAssertGreaterThan(perKm, 0)
        XCTAssertEqual(two.cash - one.cash, fuelBill(2 * km * perKm, w.country(co)) - fuelBill(km * perKm, w.country(co)), accuracy: 1e-6, "doubling the fuel price adds exactly the fuel bill of those kilometres, with the input VAT paid on it")
    }

    func testTradesThatCarryFuelInTheirCostOfSalesOrLetTheCustomerPayGetNoSecondFuelLine() throws {
        for trade in ["taxi", "courier", "trucking", "carrental"] {
            let (e, id) = try startedCompany(trade, fund: 30_000_000)
            XCTAssertFalse(try XCTUnwrap(e.state.company(id)).value("veh").array.isEmpty, trade)
            let one = weekCost(e, id, fuelIndex: 1, util: 0.8), two = weekCost(e, id, fuelIndex: 2, util: 0.8)
            XCTAssertEqual(two.cash, one.cash, accuracy: 1e-6, "\(trade): fuel is not charged on a line of its own")
            XCTAssertGreaterThan(one.km, 0, trade)
        }
    }

    func testATradeWithoutVehiclesPaysNoFuelAndTurnsNoOdometer() throws {
        let (e, id) = try startedCompany("barber")
        XCTAssertTrue(try XCTUnwrap(e.state.company(id)).value("veh").array.isEmpty)
        let one = weekCost(e, id, fuelIndex: 1, util: 0.8), two = weekCost(e, id, fuelIndex: 2, util: 0.8)
        XCTAssertEqual(one.km, 0); XCTAssertEqual(two.cash, one.cash, accuracy: 1e-6)
    }

    func testACountryFuelPriceInTheDataReplacesTheReferencePrice() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        let uk = e.data.countries["UK"]!
        let tables = e.data.catalog.tables
        let cur = Currency(country: uk, rates: ExchangeRates(drift: [:]))
        var priced = uk
        priced.vehicleRules.fuelPerLitre = 100
        let base = VehicleRunning.fuelPerKm(model: "van_s", tables: tables, country: uk, currency: cur, fuelIndex: 1)
        let withData = VehicleRunning.fuelPerKm(model: "van_s", tables: tables, country: priced, currency: cur, fuelIndex: 1)
        XCTAssertEqual(withData, 0.9 * 0.1 * 100, accuracy: 1e-9)
        XCTAssertNotEqual(base, withData)
    }

    // MARK: Company car perk

    func hireLead(_ e: inout GameEngine, _ id: Int) throws -> Int {
        var pid = 0
        e.update { s, d, _ in pid = Hiring.generateCandidate(role: "lead", company: s.company(id), tier: "mid", state: &s, data: d).id }
        let wage = e.state.people[pid]!.askingMonthlyWage * 1.5
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: wage), .ok)
        return pid
    }

    func testCompanyCarPerkLeasesARealCarForEachRecipientAndPricesItThroughTheVehicleMachinery() throws {
        var (e, id) = try startedCompany("cafe", fund: 3_000_000)
        _ = try hireLead(&e, id)
        XCTAssertTrue(e.companyCarRecipients(companyID: id).isEmpty, "perk off: nobody drives one")
        let preview = e.staffPerkMonthlyCost(companyID: id, perk: "car")
        XCTAssertGreaterThan(preview, 0, "the cost is shown before the perk is switched on")
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "car"), true)
        let rec = e.companyCarRecipients(companyID: id)
        XCTAssertEqual(rec.count, 1)
        XCTAssertNotNil(rec[0].carName, "the car is there at once")
        let cars = e.state.company(id)!.value("veh").array.filter { !$0["perk"].isNull }
        XCTAssertEqual(cars.count, 1)
        XCTAssertEqual(cars[0]["mode"].string, "lease")
        XCTAssertEqual(cars[0]["eq"].string, CompanyCarPerk.equipmentID)
        XCTAssertEqual(rec[0].monthlyLease, cars[0]["lease"].double)
        XCTAssertEqual(e.staffPerkMonthlyCost(companyID: id, perk: "car"), preview, accuracy: 1.0, "what was shown is what the cars cost")
        // the car appears in the Fleet list with its driver and its fuel
        let fleet = try XCTUnwrap(e.ownedEquipment(companyID: id).first { $0.equipmentID == CompanyCarPerk.equipmentID })
        XCTAssertEqual(fleet.vehicles.count, 1)
        XCTAssertFalse(fleet.vehicles[0].driver.isEmpty)
        XCTAssertGreaterThan(fleet.vehicles[0].fuelPerWeek, 0)
        // fuel for the perk car follows the same kilometres as its odometer, whatever the trade
        let one = weekCost(e, id, fuelIndex: 1, util: 0.5), two = weekCost(e, id, fuelIndex: 2, util: 0.5)
        let w = World(state: e.state, data: e.data), co = e.state.company(id)!
        let perKm = VehicleRunning.fuelPerKm(model: CompanyCarPerk.model, tables: e.data.catalog.tables, country: w.country(co), currency: w.currency(co), fuelIndex: 1)
        let km = e.data.catalog.tables.raw["RUNNING"]["defaultKmPerWeek"].double * 0.5
        XCTAssertEqual(one.km, km, accuracy: 1e-9)
        XCTAssertEqual(two.cash - one.cash, fuelBill(2 * km * perKm, w.country(co)) - fuelBill(km * perKm, w.country(co)), accuracy: 1e-6)
        // the old flat per-head charge is gone: the weekly perk line carries no car
        var s = e.state
        let before = s.companies[s.companyIndex(id)!].cash
        StaffPerks.weekly(&s, data: e.data)
        XCTAssertEqual(s.companies[s.companyIndex(id)!].cash, before, accuracy: 1e-6, "no flat 'Staff perks' charge for the car")
        // switching it off gives the car back
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "car"), false)
        XCTAssertTrue(e.state.company(id)!.value("veh").array.allSatisfy { $0["perk"].isNull })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testANewTeamLeadGetsACarAndALeavingOneGivesItBack() throws {
        var (e, id) = try startedCompany("cafe", fund: 3_000_000)
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "car"), true)
        XCTAssertTrue(e.companyCarRecipients(companyID: id).isEmpty)
        let pid = try hireLead(&e, id)
        e.update { s, d, _ in StaffPerks.weekly(&s, data: d) }
        XCTAssertEqual(e.companyCarRecipients(companyID: id).compactMap { $0.carName }.count, 1)
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            s.companies[i].staff.removeAll { $0.id == pid }
            StaffPerks.weekly(&s, data: d)
        }
        XCTAssertTrue(e.state.company(id)!.value("veh").array.allSatisfy { $0["perk"].isNull })
    }

    // MARK: Own car with mileage beyond estate agents

    func testASalesRepCanUseTheirOwnCarAndMileageFollowsTheCountryRateOtherwiseTheFlatFigure() throws {
        for (code, rate) in [("UK", 0.55 / 1.609344), ("DE", Double?.none)] as [(String, Double?)] {
            var (e, id) = try startedCompany("staffing", country: code, fund: 8_000_000)
            var rep = 0, hr = 0
            e.update { s, d, _ in
                rep = Hiring.generateCandidate(role: "sales", company: s.company(id), tier: "mid", state: &s, data: d).id
                hr = Hiring.generateCandidate(role: "hr", company: s.company(id), tier: "mid", state: &s, data: d).id
            }
            for p in [rep, hr] { XCTAssertEqual(e.hire(personID: p, companyID: id, monthlyWage: e.state.people[p]!.askingMonthlyWage * 1.5), .ok) }
            XCTAssertTrue(e.offersOwnCar(companyID: id, role: "sales"), code)
            XCTAssertFalse(e.offersOwnCar(companyID: id, role: "hr"), code)
            let before = PersonalEquipment.needed(e.state.company(id)!, e.data.catalog["staffing"]!, e.data.catalog["staffing"]!.equipment.first { $0.id == "rcar" }!, tables: e.data.catalog.tables)
            XCTAssertTrue(e.contractPropose(companyID: id, personID: rep, proposal: .init(.benefits, amount: 1, choice: "ownCar")).changedTerms, code)
            guard case .notPossible = e.contractPropose(companyID: id, personID: hr, proposal: .init(.benefits, amount: 1, choice: "ownCar")) else { return XCTFail("an HR clerk has no car for work") }
            let after = PersonalEquipment.needed(e.state.company(id)!, e.data.catalog["staffing"]!, e.data.catalog["staffing"]!.equipment.first { $0.id == "rcar" }!, tables: e.data.catalog.tables)
            XCTAssertEqual(after, before - 1, "a rep on their own car needs no company car")
            let bd = e.data.catalog["staffing"]!
            let monthly = e.ownCarMileagePerMonth(companyID: id)
            let w = World(state: e.state, data: e.data), co = e.state.company(id)!
            if let rate { XCTAssertEqual(monthly, VehicleRunning.kmPerWeek(bd, tables: e.data.catalog.tables) * 52 / 12 * rate * w.country(co).fx, accuracy: 0.5, code) }
            else { XCTAssertEqual(monthly, w.currency(co).scaledPrice(4500), accuracy: 0.01, "\(code) has no mileage rate in its data: the game's flat figure") }
            // booked once: the difference between a rep on their own car and not is exactly one week of mileage
            var with = e.state, without = e.state
            let i = with.companyIndex(id)!
            without.companies[i].staff = without.companies[i].staff.map { var m = $0; m.set("ownCar", 0); return m }
            let a = with.companies[i].cash, b = without.companies[i].cash
            PersonalEquipment.weeklyCosts(&with, companyIndex: i, bd, data: e.data)
            PersonalEquipment.weeklyCosts(&without, companyIndex: i, bd, data: e.data)
            XCTAssertEqual((a - with.companies[i].cash) - (b - without.companies[i].cash), monthly * 12 / 52, accuracy: 1.0, code)
        }
    }

    // MARK: Country blocks: motor insurance, vehicle tax, benefit in kind

    func dataWith(_ code: String, _ edit: (inout VehicleRules) -> Void, from e: GameEngine) -> GameData {
        var list = e.data.countries.countries
        let k = list.firstIndex { $0.code == code }!
        edit(&list[k].vehicleRules)
        return GameData(countries: CountryBook(countries: list), catalog: e.data.catalog, balance: e.data.balance)
    }

    func testCountriesWithoutFiguresAreNeutralAndThoseWithFiguresChargeThroughInsuranceTaxAndPayroll() throws {
        var (e, id) = try startedCompany("cafe", country: "DE", fund: 3_000_000)
        _ = try hireLead(&e, id)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "car"), true)
        let co = e.state.company(id)!
        XCTAssertEqual(VehicleRunning.weeklyCharges(e.state, co, data: e.data), VehicleRunning.Charges(), "no sourced figures for DE: nothing is charged")
        let d2 = dataWith("DE", { $0.motorInsuranceShare = 0.04; $0.roadTaxPerYear = ["car": 52_000]; $0.benefitInKindShare = 0.1 }, from: e)
        let c = VehicleRunning.weeklyCharges(e.state, co, data: d2)
        let car = co.value("veh").array.first { !$0["perk"].isNull }!
        XCTAssertEqual(c.insurance, car["cost"].double * 0.04 / 52, accuracy: 1e-6)
        XCTAssertEqual(c.vehicleTax, 1000, accuracy: 1e-6)
        XCTAssertGreaterThan(c.benefitCharge, 0)
        // booked through the insurance, "other" and wages lines, cash and books agree
        var s = e.state
        let i = s.companyIndex(id)!
        let books0 = s.companies[i].books
        let cash0 = s.companies[i].cash
        VehicleRunning.payCharges(&s, companyIndex: i, data: d2)
        XCTAssertEqual(cash0 - s.companies[i].cash, c.total, accuracy: 3.0)
        XCTAssertGreaterThan((s.companies[i].books.year["ins"] ?? 0) - (books0.year["ins"] ?? 0), 0)
        XCTAssertTrue(Ledger.gaps(s).isEmpty)
    }

    func testUKRoadTaxAndMileageComeFromTheCountryData() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        let rules = e.data.countries["UK"]!.vehicleRules
        XCTAssertEqual(rules.mileagePerKm ?? 0, 0.55 / 1.609344 * e.data.countries["UK"]!.fx, accuracy: 1e-3)
        XCTAssertEqual(rules.roadTaxPerYear["car"] ?? 0, 200 * e.data.countries["UK"]!.fx, accuracy: 1e-3)
        XCTAssertNil(rules.motorInsuranceShare); XCTAssertNil(rules.benefitInKindShare)
        XCTAssertEqual(e.data.countries["DE"]!.vehicleRules, VehicleRules.none)
    }

    // MARK: A year, several seeds: costs appear only where vehicles are

    func fuelWeeks(_ trade: String, seed: Int) throws -> (fuelWeeks: Int, vehicles: Int, gaps: Int) {
        var (e, id) = try startedCompany(trade, country: "UK", seed: seed, fund: 20_000_000)
        var seen = Set<Int>()
        for _ in 0..<(52 * 7) {
            e.nextDay()
            for t in e.state.company(id)?.transactions ?? [] where t["l"].string == "Fuel" { seen.insert(t["w"].int) }
            if e.state.isGameOver { break }
        }
        return (seen.count, e.state.company(id)?.value("veh").array.count ?? 0, Ledger.gaps(e.state).count)
    }

    func testAYearOnSeveralSeedsFieldDeliveryAndNoVehicleTrades() throws {
        for seed in [11, 12, 13] {
            let field = try fuelWeeks("plumber", seed: seed), delivery = try fuelWeeks("bakery", seed: seed), none = try fuelWeeks("barber", seed: seed)
            XCTAssertGreaterThan(field.vehicles, 0); XCTAssertGreaterThan(field.fuelWeeks, 10, "plumber seed \(seed) pays fuel")
            XCTAssertGreaterThan(delivery.vehicles, 0); XCTAssertGreaterThan(delivery.fuelWeeks, 10, "bakery seed \(seed) pays fuel")
            XCTAssertEqual(none.vehicles, 0); XCTAssertEqual(none.fuelWeeks, 0, "barber seed \(seed) has no vehicle and no fuel")
            XCTAssertEqual(field.gaps + delivery.gaps + none.gaps, 0, "ledger gaps, seed \(seed)")
        }
    }
}
