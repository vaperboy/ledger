import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class OfficeFinanceManagerHireTests: XCTestCase {
    func testHireFinanceManagerThroughOfficeThenRunAndFireHolding() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 21)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        XCTAssertNotNil(e.officeRoles.first { $0.id == "fin" }, "finance manager is an office role")
        XCTAssertEqual(e.rentOffice(tier: "small"), .ok)
        XCTAssertEqual(e.officeRoom(role: "fin"), .locked, "needs a holding company first")
        guard case .success(let hid) = e.createHolding(name: "H", companies: []) else { throw XCTSkip("holding") }
        XCTAssertEqual(e.officeRoom(role: "fin"), .ok)
        guard let n = e.searchOffice(role: "fin", mode: .agency)?.first else { return XCTFail("no candidates") }
        XCTAssertTrue(n.askingMonthlyWage > 0)
        XCTAssertEqual(e.hireOffice(role: "fin", personID: n.id, monthlyWage: n.askingMonthlyWage), .ok)
        XCTAssertEqual(e.toggleHoldingFinanceManager(holdingID: hid), true)
        XCTAssertNotNil(FinanceManager.negotiator(e.state, holdingID: hid))
        e.fireOffice(personID: n.id)
        XCTAssertNil(FinanceManager.negotiator(e.state, holdingID: hid))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
