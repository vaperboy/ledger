import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class HeldMoneyAndFiguresTests: XCTestCase {
    private func game() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 21)
        e.update { s, _, _ in Ledger.move(&s, .me, 40_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 12_000_000) else {
            XCTFail("start"); throw XCTSkip("no company")
        }
        _ = e.quickSetup(companyID: id)
        return (e, id)
    }

    private func midWeek(_ e: inout GameEngine, day: Int) {
        for _ in 0..<(7 * 6) { e.nextDay() }
        while e.state.day != day { e.nextDay() }
    }

    func testRemainingAndSettleAreConsistent() throws {
        var (e, id) = try game()
        midWeek(&e, day: 2)
        let before = try XCTUnwrap(e.state.company(id)).cash
        let held = HeldMoney.remaining(e.state, companyID: id)
        var s = e.state
        let got = HeldMoney.settle(&s, companyID: id)
        XCTAssertEqual(got, held, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.company(id)).cash, before + held, accuracy: 0.01)
        XCTAssertEqual(HeldMoney.remaining(s, companyID: id), 0, "nothing is held for it any more")
        XCTAssertTrue(Ledger.gaps(s).isEmpty)
    }

    func testRemainderFullyReleasedByWeekEndWithoutSettling() throws {
        var (e, id) = try game()
        midWeek(&e, day: 0)
        let start = try XCTUnwrap(e.state.company(id)).cash
        let held = HeldMoney.remaining(e.state, companyID: id)
        for _ in 0..<6 { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        _ = start; _ = held
    }

    func testWindUpMidWeekSettlesHeldMoneyAndLeavesNoStrayCash() throws {
        var (e, id) = try game()
        midWeek(&e, day: 2)
        let held = HeldMoney.remaining(e.state, companyID: id)
        XCTAssertEqual(e.windUpCompany(companyID: id), true)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.status, .sold)
        XCTAssertEqual(co.cash, 0, accuracy: 0.01)
        XCTAssertEqual(HeldMoney.remaining(e.state, companyID: id), 0, "the held days were settled, not left behind")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "gaps: \(Ledger.gaps(e.state))")
        for _ in 0..<8 { e.nextDay() }
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, 0, accuracy: 0.01, "nothing lands in a dead company afterwards (held was \(held))")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testClosingMidWeekKeepsTheCompanyAndItsHeldMoney() throws {
        var (e, id) = try game()
        midWeek(&e, day: 3)
        XCTAssertEqual(e.closeCompany(companyID: id, weeks: 3), .ok)
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).cash.magnitude, -1)
        for _ in 0..<8 { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "gaps: \(Ledger.gaps(e.state))")
        XCTAssertNotNil(e.state.company(id))
    }

    func testCompanyFiguresAgreeAcrossScreens() throws {
        var (e, id) = try game()
        _ = e.takeLoan(kind: "biz", amount: 2_000_000, termMonths: 36, companyID: id)
        for _ in 0..<(7 * 20) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        let health = e.companyHealth(co)
        let debts = CompanyFigures.debts(co, loans: e.state.loans)
        XCTAssertEqual(health.debt, debts, accuracy: 0.5)
        XCTAssertEqual(health.value, Valuation.companyValue(co, state: e.state, trades: e.data.catalog), accuracy: 0.5)
        XCTAssertEqual(health.weeklyCost, e.context.weeklyCost(co, e.state), accuracy: 0.01)
        let overview = e.financeOverview(companyID: id)
        XCTAssertEqual(overview.taxesOwed, max(0, co.vatBalance) + (co.payables["tax"] ?? 0), accuracy: 0.5)
        let hist = co.monthlyHistory.suffix(12)
        XCTAssertEqual(health.profitTTM, hist.reduce(0) { $0 + $1.profit }, accuracy: 0.5)
        XCTAssertEqual(health.revenueTTM, hist.reduce(0) { $0 + $1.revenue }, accuracy: 0.5)
    }

    func testNetWorthAgreesWithItsParts() throws {
        var (e, id) = try game()
        for _ in 0..<(7 * 10) { e.nextDay() }
        let nw = e.netWorth
        XCTAssertEqual(nw.total, nw.totalAssets - nw.debt - nw.pendingTax, accuracy: 0.01)
        XCTAssertEqual(nw.debt, Banking.totalDebt(e.state, personalOnly: true), accuracy: 0.5, "personal debt is the loans that are not a company's")
        XCTAssertEqual(nw.personal, e.state.cash + HeldMoney.playerRemaining(e.state), accuracy: 0.01)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(nw.companies, (Valuation.companyValue(co, state: e.state, trades: e.data.catalog) + HeldMoney.remaining(e.state, companyID: co.id)) * co.ownership / 100, accuracy: 1)
    }
}
