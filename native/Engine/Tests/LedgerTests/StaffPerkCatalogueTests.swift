import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The perk catalogue is data (`staff_perks.json`). These pins are the numbers of the five perks that used to be hard-coded in Swift:
/// the move to data must not change any of them (golden equality), and the new per-role-group choice must add up to the same books.
final class StaffPerkCatalogueTests: XCTestCase {
    /// id, name, monthly cost per person at the reference price level, quit factor, pull, only the manager and team leads.
    static let golden: [(String, String, Double, Double, Double, Bool)] = [
        ("car", "Company car", 5500, 0.82, 0.15, true),
        ("gym", "Gym membership", 450, 0.95, 0.15, false),
        ("health", "Health insurance", 650, 0.93, 0.3, false),
        ("trips", "A team trip each year", 350, 0.9, 0.2, false),
        ("lunch", "Free lunch", 1500, 0.94, 0.25, false),
    ]

    private func cafe(_ e: inout GameEngine, manager: Bool = true) throws -> Int {
        e.update { s, _, _ in Ledger.move(&s, .me, 800_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("could not start") }
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].status = .open
            s.companies[i].staff = [
                StaffMember(raw: ["id": 9001, "role": "waiter", "wage": 30000, "w0": 0, "tired": 20]),
                StaffMember(raw: ["id": 9002, "role": "lead", "wage": 40000, "w0": 0, "tired": 10]),
                StaffMember(raw: ["id": 9003, "role": "barista", "wage": 31000, "w0": 0, "tired": 30]),
            ]
            for (pid, role) in [(9001, "waiter"), (9002, "lead"), (9003, "barista")] {
                s.people[pid] = Person(raw: ["id": .number(Double(pid)), "name": .string("Worker \(pid)"), "age": 30, "role": .string(role), "skill": 50, "hired": .number(Double(id))])
            }
            if manager {
                s.people[9100] = Person(raw: ["id": 9100, "name": "Anna Berg", "age": 40, "role": "mgr", "skill": 80])
                s.companies[i].managerID = 9100
                s.companies[i].set("mood", 50)
            }
        }
        return id
    }

    func testTheFivePerksAreTheOnesTheCodeUsedToHold() throws {
        XCTAssertEqual(StaffPerks.all.map { $0.id }, Self.golden.map { $0.0 })
        for (id, name, cost, quit, pull, keys) in Self.golden {
            let p = try XCTUnwrap(StaffPerks.perk(id))
            XCTAssertEqual(p.name, name)
            XCTAssertEqual(p.monthlyCost, cost, id)
            XCTAssertEqual(p.quitFactor, quit, accuracy: 1e-12, id)
            XCTAssertEqual(p.pull, pull, accuracy: 1e-12, id)
            XCTAssertEqual(p.keysOnly, keys, id)
            XCTAssertFalse(p.detail.isEmpty)
        }
    }

    func testCostsQuitOddsPullAndEffectsAreUnchanged() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        for g in Self.golden { XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: g.0), true) }
        let co = try XCTUnwrap(e.state.company(id))
        let cur = World(state: e.state, data: e.data).currency(co)
        // 3 staff + the manager are the headcount; the manager and the one team lead hold the keys.
        XCTAssertEqual(StaffPerks.headcount(co), 4)
        XCTAssertEqual(StaffPerks.keyPeople(co), 2)
        // The company car is no flat per-head figure any more: it is a leased car for each of the two key people (vehicle machinery).
        let carCost = CompanyCarPerk.monthlyCost(e.state, co, data: e.data)
        XCTAssertEqual(e.companyCarRecipients(companyID: id).compactMap { $0.carName }.count, 2)
        XCTAssertGreaterThan(carCost, 0)
        for g in Self.golden {
            let expected = g.0 == "car" ? carCost : cur.scaledPrice(g.2) * (g.5 ? 2 : 4)
            XCTAssertEqual(e.staffPerkMonthlyCost(companyID: id, perk: g.0), expected, accuracy: 1e-6, g.0)
        }
        let monthly = Self.golden.filter { $0.0 != "car" }.reduce(0.0) { $0 + cur.scaledPrice($1.2) * ($1.5 ? 2 : 4) }
        XCTAssertEqual(e.staffPerksMonthlyTotal(companyID: id), monthly + carCost, accuracy: 1e-6)
        let all = Self.golden.reduce(1.0) { $0 * $1.3 }
        XCTAssertEqual(e.staffPerksFewerLeavePercent(companyID: id), (1 - all) * 100, accuracy: 1e-9)
        let lead = co.staff[1], waiter = co.staff[0]
        XCTAssertEqual(StaffPerks.quitFactor(co, lead), all, accuracy: 1e-12)
        XCTAssertEqual(StaffPerks.quitFactor(co, waiter), all / 0.82, accuracy: 1e-12, "the car is for the keys only")
        // a week: paid with the wages, long weeks eased by 1.5, the manager is happier by the car and the trip
        let cash0 = co.cash
        e.update { s, d, _ in StaffPerks.weekly(&s, data: d) }
        let after = try XCTUnwrap(e.state.company(id))
        // Benefits in kind attract the employer's charges like pay does (deliberate model rule: StaffPerks.weekly adds the country's on-cost
        // at the median wage), so the perk line is the catalogue cost times (1 + on-cost), not the bare catalogue cost.
        let country = World(state: e.state, data: e.data).country(co)
        let onCost = 1 + country.employerOnCost(monthlyWage: country.medianMonthlyWage)
        XCTAssertGreaterThan(onCost, 1)
        XCTAssertEqual(cash0 - after.cash, monthly * 12 / 52 * onCost, accuracy: 1, "the car bills through its lease and fuel, not through the perk line")
        XCTAssertEqual(after.staff[0].tiredness, 20 - 1.5, accuracy: 1e-9)
        XCTAssertEqual(after.staff[1].tiredness, 10 - 1.5, accuracy: 1e-9)
        XCTAssertEqual(after.num("mood"), 50 + (0.25 + 0.2) * max(0, 1 - 50.0 / 85), accuracy: 1e-9)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTheOriginalFlagIsKeptForTheWholeCompany() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "gym"), true)
        XCTAssertEqual(e.state.company(id)?.value("perks58")["gym"].double, 1, "the plain flag of the original, so an old save reads the same")
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "gym"), false)
        XCTAssertEqual(e.state.company(id)?.value("perks58")["gym"].double, 0)
    }

    // MARK: Per role group

    func testAPerkCanGoToOneRoleGroupOnly() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        XCTAssertNil(e.toggleStaffPerk(companyID: id, perk: "car", group: "crew"), "a company car may not go to the crew")
        XCTAssertNil(e.toggleStaffPerk(companyID: id, perk: "gym", group: "nobody"))
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "lunch", group: "crew"), true)
        let co = try XCTUnwrap(e.state.company(id))
        let cur = World(state: e.state, data: e.data).currency(co)
        // the crew are the waiter and the barista; the manager and the lead hold the keys and are not covered
        XCTAssertEqual(e.staffPerkPeople(companyID: id, group: "crew"), 2)
        XCTAssertEqual(e.staffPerkMonthlyCost(companyID: id, perk: "lunch"), cur.scaledPrice(1500) * 2, accuracy: 1e-6)
        XCTAssertEqual(StaffPerks.quitFactor(co, co.staff[0]), 0.94, accuracy: 1e-12)
        XCTAssertEqual(StaffPerks.quitFactor(co, co.staff[1]), 1, accuracy: 1e-12, "the lead is not covered")
        XCTAssertEqual(StaffPerks.pull(co, role: "waiter"), 0.25, accuracy: 1e-12)
        XCTAssertEqual(StaffPerks.pull(co, role: "lead"), 0, accuracy: 1e-12)
        XCTAssertTrue(StaffPerks.isOn(co, "lunch"))
        XCTAssertFalse(StaffPerks.isOnForAll(co, "lunch"))
        // only the covered are eased (0.5 for lunch)
        e.update { s, d, _ in StaffPerks.weekly(&s, data: d) }
        let after = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(after.staff[0].tiredness, 20 - 0.5, accuracy: 1e-9)
        XCTAssertEqual(after.staff[1].tiredness, 10, accuracy: 1e-9)
        // the other group too: the stored state goes back to the plain flag
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "lunch", group: "keys"), true)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "lunch", group: "sales"), true)
        XCTAssertEqual(e.state.company(id)?.value("perks58")["lunch"].double, 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAGroupChoiceSurvivesASave() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "health", group: "keys"), true)
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        let co = try XCTUnwrap(back.company(id)), p = try XCTUnwrap(StaffPerks.perk("health"))
        XCTAssertTrue(StaffPerks.covers(co, p, group: "keys"))
        XCTAssertFalse(StaffPerks.covers(co, p, group: "crew"))
    }

    func testAPerkCostedOnPayIsAShareOfTheCoveredPay() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        var p = try XCTUnwrap(StaffPerks.perk("gym"))
        p.costBasis = .wage; p.monthlyCost = 0.02
        e.update { s, _, _ in _ = StaffPerks.set(&s, companyID: id, perk: "gym", on: true, group: "crew") }
        let co = try XCTUnwrap(e.state.company(id))
        let cur = World(state: e.state, data: e.data).currency(co)
        XCTAssertEqual(StaffPerks.monthlyCost(co, p, currency: cur), 0.02 * (30000 + 31000), accuracy: 1e-6)
    }

    func testPerksCountAsPayInTheMoodAndTheContractTalk() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        let co0 = try XCTUnwrap(e.state.company(id))
        let cur = World(state: e.state, data: e.data).currency(co0)
        XCTAssertEqual(StaffPerks.worthMonthly(co0, co0.staff[0], currency: cur), 0)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "health"), true)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "lunch", group: "crew"), true)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(StaffPerks.worthMonthly(co, co.staff[0], currency: cur), cur.scaledPrice(650) * 0.8 + cur.scaledPrice(1500) * 0.9, accuracy: 1e-6)
        XCTAssertEqual(StaffPerks.worthMonthly(co, co.staff[1], currency: cur), cur.scaledPrice(650) * 0.8, accuracy: 1e-6, "the lead has no lunch")
        let mood = try XCTUnwrap(StaffProfile.mood(e.state, companyID: id, staffID: 9001, data: e.data))
        XCTAssertTrue(mood.good.contains { $0.contains("Health insurance") && $0.contains("Free lunch") }, "\(mood.good)")
        let lead = try XCTUnwrap(StaffProfile.mood(e.state, companyID: id, staffID: 9002, data: e.data))
        XCTAssertTrue(lead.good.contains { $0.contains("Health insurance") && !$0.contains("Free lunch") }, "\(lead.good)")
    }
}
