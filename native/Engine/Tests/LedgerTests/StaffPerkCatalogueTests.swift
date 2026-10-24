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
        for g in Self.golden {
            XCTAssertEqual(e.staffPerkMonthlyCost(companyID: id, perk: g.0), cur.scaledPrice(g.2) * (g.5 ? 2 : 4), accuracy: 1e-6, g.0)
        }
        let monthly = Self.golden.reduce(0.0) { $0 + cur.scaledPrice($1.2) * ($1.5 ? 2 : 4) }
        XCTAssertEqual(e.staffPerksMonthlyTotal(companyID: id), monthly, accuracy: 1e-6)
        let all = Self.golden.reduce(1.0) { $0 * $1.3 }
        XCTAssertEqual(e.staffPerksFewerLeavePercent(companyID: id), (1 - all) * 100, accuracy: 1e-9)
        let lead = co.staff[1], waiter = co.staff[0]
        XCTAssertEqual(StaffPerks.quitFactor(co, lead), all, accuracy: 1e-12)
        XCTAssertEqual(StaffPerks.quitFactor(co, waiter), all / 0.82, accuracy: 1e-12, "the car is for the keys only")
        // a week: paid with the wages, long weeks eased by 1.5, the manager is happier by the car and the trip
        let cash0 = co.cash
        e.update { s, d, _ in StaffPerks.weekly(&s, data: d) }
        let after = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(cash0 - after.cash, monthly * 12 / 52, accuracy: 1)
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
}
