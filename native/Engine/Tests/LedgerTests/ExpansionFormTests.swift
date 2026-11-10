import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

final class ExpansionFormTests: XCTestCase {
    private func game() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 21)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 600_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            _ = Payments.injectCash(&s, companyID: id, amount: 40_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(6 * 7) { e.nextDay() }
        return (e, id)
    }

    func testPlanChangesNothingAndCancelRefundsTheUnspentPart() throws {
        var (e, id) = try game()
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        let plan = try XCTUnwrap(e.developmentPlan(companyID: id, project: "menu"))
        XCTAssertEqual(e.state.company(id)?.cash, cash0, "reading the form pays nothing")
        XCTAssertNil(plan.blockedReason)
        XCTAssertEqual(plan.cashAfter, plan.cashBefore - plan.cost, accuracy: 0.5)
        XCTAssertEqual(e.startDevelopment(companyID: id, project: "menu"), .ok)
        let paid = cash0 - (e.state.company(id)?.cash ?? 0)
        XCTAssertEqual(paid, plan.cost, accuracy: 1)
        for _ in 0..<(4 * 7) { e.nextDay() }
        let cashMid = try XCTUnwrap(e.state.company(id)).cash
        let refund = try XCTUnwrap(e.cancelDevelopment(companyID: id))
        XCTAssertGreaterThan(refund, 0)
        XCTAssertLessThan(refund, plan.cost)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, cashMid + refund, accuracy: 1)
        XCTAssertNil(Development.running(try XCTUnwrap(e.state.company(id))))
        XCTAssertNil(e.cancelDevelopment(companyID: id), "nothing left to cancel")
        XCTAssertEqual(e.startDevelopment(companyID: id, project: "loyal"), .ok)
        let back = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(e.state))
        XCTAssertEqual(Development.running(try XCTUnwrap(back.company(id)))?.project, "loyal")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
