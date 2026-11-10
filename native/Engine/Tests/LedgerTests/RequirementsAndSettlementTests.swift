import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation
import Events

final class RequirementsAndSettlementTests: XCTestCase {
    func cafeGame() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        XCTAssertNotEqual(id, 0)
        return (e, id)
    }
    func suit(_ claim: Double) -> JSONValue {
        .object(["claim": .number(claim), "fee": 0, "who": "A. Customer", "big": false, "p": 0.5, "settle": .number(claim / 2), "wks": 0, "why": "says you broke the terms"])
    }

    func testFreshGameHasNoTrophies() throws {
        let (e, _) = try cafeGame()
        XCTAssertTrue(Trophies.entries(e.state).allSatisfy { $0.reachedWeek == nil }, "nothing is granted before its condition")
    }

    func testSettlementKeepsWagesFirstAndRecordsTheRest() throws {
        var (e, id) = try cafeGame()
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].payables["wages"] = 20_000
            Ledger.set(&s, to: 30_000)
            _ = Lawsuits.resolve(&s, companyIndex: i, d: suit(100_000), choice: 0, data: d)
        }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.cash, 20_000, "the wages owed stay covered")
        XCTAssertEqual(co.payables["wages"], 20_000)
        XCTAssertEqual(co.payables["legal"], 40_000, "settlement of 50,000 less 10,000 spare")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testPaidJudgmentLeavesNoLiabilityAndNoAlert() throws {
        var (e, id) = try cafeGame()
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].payables["wages"] = 0
            Ledger.set(&s, to: 0)
            Lawsuits.lose(&s, id, suit(40_000), extra: 0, data: d)
        }
        XCTAssertEqual(e.state.company(id)?.payables["legal"], 40_000)
        e.update { s, _, _ in
            Ledger.set(&s, to: 500_000)
            if let i = s.companyIndex(id) { LegalDebts.settle(&s, companyIndex: i) }
        }
        XCTAssertNil(e.state.company(id)?.payables["legal"])
        XCTAssertFalse(e.payrollAlerts().contains { $0.companyID == id && $0.isLate }, "no stale salary alert")
    }
}
