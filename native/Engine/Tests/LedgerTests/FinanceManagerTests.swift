import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class FinanceManagerTests: XCTestCase {
    func testFundManagerLifecycleKeepsBooksBalanced() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 5_000_000, why: "Test funds") }
        let cands = e.fundManagerCandidates()
        XCTAssertEqual(cands.count, 3)
        XCTAssertEqual(e.fundManagerCandidates().map { $0.id }, cands.map { $0.id }, "the pool is kept")
        let cash0 = e.state.cash
        XCTAssertEqual(e.hireFundManager(personID: cands[0].id, mandate: .balanced, amount: 1_000_000), .ok)
        XCTAssertEqual(e.state.cash, cash0 - 1_000_000)
        XCTAssertEqual(e.hireFundManager(personID: cands[1].id, mandate: .cautious, amount: 1_000), .busy)
        XCTAssertTrue(e.addToFundManager(500_000))
        XCTAssertEqual(e.fundManager?.cost, 1_500_000)
        for _ in 0..<(7 * 8) { _ = e.nextDay() }
        let bal = e.fundManager?.balance ?? 0
        XCTAssertNotEqual(bal, 1_500_000, "eight weeks of returns and fees moved the balance")
        XCTAssertTrue(e.withdrawFromFundManager(300_000))
        XCTAssertEqual(e.fundManager?.balance ?? 0, bal - 300_000, accuracy: 1)
        e.dismissFundManager()
        XCTAssertNil(e.fundManager)
        XCTAssertEqual(e.state.people[cands[0].id]?.employerID, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testOfficeFinanceManagerNeedsAnOfficeHireAndLayoffChip() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 12)
        XCTAssertNil(e.toggleHoldingFinanceManager(holdingID: 1), "no finance manager in the office yet")
        XCTAssertEqual(e.layoffCount(companyID: 99, preset: "10"), 1)
        XCTAssertEqual(e.layoffCount(companyID: 99, preset: "3"), 0, "no such company: nobody to lay off")
    }
}
