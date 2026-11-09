import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation
import Events

/// Expansion gates are real requirements (no waiting-time gates), trophies only when earned, the lawsuit settlement path
/// keeps wages first, and a paid judgment leaves neither a liability nor a payroll alert.
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

    // MARK: D

    func testFreshGameHasNoTrophies() throws {
        let (e, _) = try cafeGame()
        XCTAssertTrue(Trophies.entries(e.state).allSatisfy { $0.reachedWeek == nil }, "nothing is granted before its condition")
    }

    func testChainRequirementsAreRealLifePapers() throws {
        let (e, id) = try cafeGame()
        // Real basis: a registered trademark and an operations manual; no cash, reputation or record gates.
        let r = Chains.requirements(e.state, e.state.company(id)!)
        XCTAssertEqual(r.map { $0.key }, ["trademark", "ops_manual"])
        XCTAssertFalse(r.contains { $0.title.lowercased().contains("cash") || $0.title.lowercased().contains("customers like") })
    }

    func testFranchiseRequirementsHaveNoYearsOrCashGate() throws {
        let (e, id) = try cafeGame()
        let r = Franchising.requirements(e.state, e.state.company(id)!)
        XCTAssertFalse(r.contains { $0.title.contains("years") || $0.title.contains("for a year") })
        XCTAssertFalse(r.contains { $0.title.lowercased().contains("cash") })
        XCTAssertEqual(r.map { $0.key }, ["proven", "trademark", "ops_manual", "fran", "support"])
    }

    // MARK: E

    func testSettlementKeepsWagesFirstAndRecordsTheRest() throws {
        var (e, id) = try cafeGame()
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].payables["wages"] = 20_000
            Ledger.set(&s, .company(id), to: 30_000)
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
            Ledger.set(&s, .company(id), to: 0)
            Lawsuits.lose(&s, id, suit(40_000), extra: 0, data: d)
        }
        XCTAssertEqual(e.state.company(id)?.payables["legal"], 40_000)
        e.update { s, _, _ in
            Ledger.set(&s, .company(id), to: 500_000)
            if let i = s.companyIndex(id) { LegalDebts.settle(&s, companyIndex: i) }
        }
        XCTAssertNil(e.state.company(id)?.payables["legal"])
        XCTAssertFalse(e.payrollAlerts().contains { $0.companyID == id && $0.isLate }, "no stale salary alert")
    }
}
