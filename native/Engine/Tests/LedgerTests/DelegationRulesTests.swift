import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class DelegationRulesTests: XCTestCase {
    private func company(_ e: inout GameEngine) throws -> Int {
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "webdev", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000, quickSetup: false) else { throw XCTSkip("no company") }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return id
    }

    func testARedAlertComesOncePerFourWeeksBeforeAForcedSale() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        let id = try company(&e)
        e.update { s, _, ctx in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].weeksNegative = 10
            s.companies[i].cash = -90_000_000
            Failure.warn(&s, context: ctx)
            Failure.warn(&s, context: ctx)
        }
        XCTAssertEqual(e.state.inbox.filter { $0.isAlert && $0.companyID == id }.count, 1)
    }

    func testNothingIsDelegatedWithoutAManager() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        _ = try company(&e)
        XCTAssertEqual(Delegation.spendLimit(e.state, data: e.data), 0, "no manager: every spend is the owner's")
        XCTAssertFalse(Delegation.autoRehire(e.state, e.state.companies[0]))
    }

    func testABankLendsAgainstWhatABusinessIsWorthEvenAtALoss() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        let id = try company(&e)
        let co = try XCTUnwrap(e.state.company(id))
        let none = Banking.offer(kind: "biz", amount: 1, company: co, state: e.state, netWorth: 0, companyValue: 0, context: e.context)
        let worth = Banking.offer(kind: "biz", amount: 1, company: co, state: e.state, netWorth: 0, companyValue: 500_000_000, context: e.context)
        XCTAssertGreaterThanOrEqual(worth.maximum, none.maximum)
        if none.creditBand != "E" { XCTAssertGreaterThan(worth.maximum, none.maximum, "worth counts, not only profit") }
    }
}
