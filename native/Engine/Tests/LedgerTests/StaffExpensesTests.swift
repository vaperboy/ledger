import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// Expense reimbursement: chosen per person in the contract talk, booked as an expense (not wages), neutral tax unless the country data says otherwise,
/// and a training allowance that speeds up the existing skill growth.
final class StaffExpensesTests: XCTestCase {
    private func shop(seed: Int = 5, trade: String = "cafe") throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        return (e, id)
    }

    private func hire(_ e: inout GameEngine, _ id: Int, role: String) -> Int {
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: role, company: s.company(id), tier: "mid", state: &s, data: d)
            p.set("pers", "steady"); p.set("sec", 0.1)
            s.people[p.id] = p; pid = p.id
        }
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5), .ok)
        return pid
    }

    func testChoicesFollowTheJobAndNothingIsWrittenUntilOneIsChosen() throws {
        var (e, id) = try shop()
        let waiter = hire(&e, id, role: "waiter")
        let ids = e.contractChoices(companyID: id, personID: waiter, topic: .benefits).map { $0.id }
        XCTAssertTrue(ids.contains("exp:uniform") && ids.contains("exp:training"))
        XCTAssertFalse(ids.contains("exp:phone"), "a waiter has no work phone")
        XCTAssertNil(e.state.company(id)?.staff.first { $0.id == waiter }?.raw["ex"])
        guard case .notPossible = e.contractPropose(companyID: id, personID: waiter, proposal: .init(.benefits, amount: 1, choice: "exp:phone")) else { return XCTFail("not for a waiter") }
        let pv = e.contractPreview(companyID: id, personID: waiter, proposal: .init(.benefits, amount: 1, choice: "exp:uniform"))
        XCTAssertGreaterThan(pv.costPerMonth, 0)
        guard case .agreed = e.contractPropose(companyID: id, personID: waiter, proposal: .init(.benefits, amount: 1, choice: "exp:uniform")) else { return XCTFail("on") }
        guard case .agreed = e.contractPropose(companyID: id, personID: waiter, proposal: .init(.benefits, amount: 0, choice: "exp:uniform")) else { return XCTFail("off") }
        XCTAssertNil(e.state.company(id)?.staff.first { $0.id == waiter }?.raw["ex"], "back to nothing stored")
    }

    func testReimbursementsAreAnExpenseNotWagesAndBooksBalance() throws {
        var (e, id) = try shop()
        let waiter = hire(&e, id, role: "waiter")
        _ = e.contractPropose(companyID: id, personID: waiter, proposal: .init(.benefits, amount: 1, choice: "exp:uniform"))
        let co0 = e.state.company(id)!
        let cur = World(state: e.state, data: e.data).currency(co0)
        let oth0 = co0.books.week["oth"] ?? 0, wages0 = co0.books.week["wages"] ?? 0
        e.update { s, d, _ in StaffExpenses.weekly(&s, data: d) }
        let co = e.state.company(id)!
        XCTAssertEqual((co.books.week["oth"] ?? 0) - oth0, cur.scaledPrice(300) * 12 / 52, accuracy: 1)
        XCTAssertEqual(co.books.week["wages"] ?? 0, wages0, accuracy: 1e-9, "no wages, no employer charge: neutral without country data")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testACountryCanMarkAReimbursementAsATaxableBenefit() throws {
        let uk = try CountryBook.bundled().countries.first { $0.code == "UK" }!
        XCTAssertFalse(StaffExpenses.carriesEmployerCharge(uk, item: "phone"), "no source yet, so neutral")
        var pack = uk.pack
        pack["staffExpenses"] = .object(["phone": .object(["employerCharge": .bool(true)])])
        let other = Country(pack: pack)
        XCTAssertTrue(StaffExpenses.carriesEmployerCharge(other, item: "phone"))
        XCTAssertFalse(StaffExpenses.carriesEmployerCharge(other, item: "uniform"))
    }

    func testATrainingAllowanceSpeedsUpTheExistingSkillGrowth() throws {
        var (e, id) = try shop()
        let a = hire(&e, id, role: "waiter"), b = hire(&e, id, role: "waiter")
        e.update { s, _, _ in for pid in [a, b] { var n = s.people[pid]!; n.skill = 40; n.potential = 80; n.set("age", 30); s.people[pid] = n } }
        _ = e.contractPropose(companyID: id, personID: a, proposal: .init(.benefits, amount: 1, choice: "exp:training"))
        XCTAssertEqual(StaffExpenses.learnFactor(e.state.company(id)!.staff.first { $0.id == a }!), 1.3, accuracy: 1e-12)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var st = s.companies[i].staff; for k in st.indices { st[k].skillGain = 0 }; s.companies[i].staff = st
            for _ in 0..<10 { StaffRoutine.growSkills(&s, companyIndex: i) }
        }
        let st = e.state.company(id)!.staff
        let ga = st.first { $0.id == a }!.skillGain, gb = st.first { $0.id == b }!.skillGain
        XCTAssertGreaterThan(ga, gb * 1.2, "trained: \(ga), not: \(gb)")
    }

    func testReimbursementsSurviveASaveAndAreDeterministic() throws {
        func run() throws -> Double {
            var (e, id) = try shop(seed: 9)
            let w = hire(&e, id, role: "waiter")
            _ = e.contractPropose(companyID: id, personID: w, proposal: .init(.benefits, amount: 1, choice: "exp:training"))
            for _ in 0..<14 { e.nextDay() }
            let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
            XCTAssertTrue(StaffExpenses.isOn(back.company(id)!.staff.first { $0.id == w }!, "training"))
            return e.state.cash
        }
        XCTAssertEqual(try run(), try run())
    }
}
