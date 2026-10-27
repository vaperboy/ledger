import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class LuxuryAccessTests: XCTestCase {
    func testGateAcceptsRichDeclinesPoorAndRemembers() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        XCTAssertEqual(e.luxuryGate, .notApplied)
        XCTAssertTrue(e.luxuryGatePasses(netWorth: e.luxuryGateThreshold))
        XCTAssertFalse(e.luxuryGatePasses(netWorth: e.luxuryGateThreshold - 1))
        guard case .declined(let w) = e.applyForLuxuryAccess() else { return XCTFail("a new player is declined") }
        XCTAssertFalse(e.luxuryGateCanApply, "same week: no second try")
        e.update { s, _, _ in s.week = w + 1 }
        XCTAssertTrue(e.luxuryGateCanApply)
        let th = e.luxuryGateThreshold
        e.update { s, _, _ in Ledger.move(&s, .me, th * 2, why: "Test funds") }
        XCTAssertEqual(e.applyForLuxuryAccess(), .accepted)
        // Accepted stays accepted even if the money goes.
        e.update { s, _, _ in Ledger.move(&s, .me, -th * 2, why: "Test spend") }
        XCTAssertEqual(e.applyForLuxuryAccess(), .accepted)
        XCTAssertEqual(e.luxuryGate, .accepted)
    }

    func testFinancedPurchaseTakesLoanAndPiece() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        let id = try XCTUnwrap(Luxury.categories.first?.items.first?.id)
        e.update { s, _, _ in Ledger.move(&s, .me, Luxury.item(id)!.price * 40, why: "Test funds") }
        let q = try XCTUnwrap(e.luxuryFinanceQuote(itemID: id))
        XCTAssertEqual(q.down + q.loan, Luxury.item(id)!.price, accuracy: 1)
        let loans0 = e.state.loans.count
        let cash0 = e.state.cash
        let r = e.buyLuxuryFinanced(itemID: id)
        if case .refused = r {
            // The bank's own limits apply; a refusal moves nothing.
            XCTAssertEqual(e.state.loans.count, loans0)
            XCTAssertEqual(e.state.cash, cash0)
            XCTAssertEqual(e.luxuryPieces.count, 0)
        } else {
            XCTAssertEqual(r, .ok)
            XCTAssertEqual(e.state.loans.count, loans0 + 1)
            XCTAssertEqual(e.luxuryPieces.count, 1)
        }
    }
}
