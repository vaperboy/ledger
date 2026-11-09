import XCTest
@testable import Events
import GameCore
import Finance
import Businesses
@testable import Simulation

/// One message per milestone, loan offers that match decisions, and broke only when out of money and companies.
final class PlaytestFixesTests: XCTestCase {
    func testSeveralNetWorthRungsInOneWeekAreOneMessage() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 900_000_000, why: "Test funds")
            Trophies.check(&s, data: data, context: ctx)
        }
        let reached = Trophies.entries(e.state).filter { $0.reachedWeek != nil && $0.text.hasPrefix("Your net worth passed") }
        XCTAssertGreaterThan(reached.count, 3, "every rung is still recorded")
        let told = e.state.inbox.filter { $0.from == "Trophy wall" && $0.body.hasPrefix("Your net worth passed") }
        XCTAssertEqual(told.count, 1, "but the player is told once")
    }

    func testBusinessLoanDecisionAgreesWithOffer() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds"); s.credit = 85 }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 30_000_000) else { throw XCTSkip("could not start") }
        let most = e.loanOffer(kind: "biz", amount: 0, companyID: id).maximum
        XCTAssertGreaterThan(most, 0)
        let docs = LoanDocuments(fullName: "T", incomeProof: .payslips, companyPapers: .registration)
        let r = e.applyForLoan(kind: "biz", amount: most, termMonths: 36, companyID: id, documents: docs, agreed: true)
        guard case .approved = r else { return XCTFail("offered \(most) but \(r)") }
    }

    func testNetWorthCountsMoneyOfTheWeekStillOnItsWay() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        var s = e.state
        let base = Valuation.netWorth(s, trades: e.data.catalog).total
        s.day = 1
        s.rest["pend"] = .object(["rows": .array([.object(["a": .number(8000), "l": .string("Sale"), "co": .number(0), "d": .number(3)]),
                                                  .object(["a": .number(500), "l": .string("Earlier"), "co": .number(0), "d": .number(0)])]), "co": .array([])])
        let held = Valuation.netWorth(s, trades: e.data.catalog).total
        XCTAssertEqual(held - base, 8000, accuracy: 0.01, "only what has not landed yet is added")
        s.day = 3
        XCTAssertEqual(Valuation.netWorth(s, trades: e.data.catalog).total, base, accuracy: 0.01, "nothing is held once it has landed")
    }

    func testNobodyIsBrokeWhileHoldingMoneyForAFirstCompany() throws {
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 1)
        for _ in 0..<(3 * 7 + 2) { e.nextDay() }
        XCTAssertFalse(e.state.isGameOver, "three weeks without a company but with start-up money is not game over")
    }
}
