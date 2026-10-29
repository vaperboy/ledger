import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class CompanyScreenReadsTests: XCTestCase {
    private func cafe() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 40_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 12_000_000) else {
            XCTFail("start"); throw XCTSkip("no company")
        }
        return (e, id)
    }

    func testBalanceSheetLinesAddUpToCompanyFigures() throws {
        var (e, id) = try cafe()
        _ = e.quickSetup(companyID: id)
        _ = e.takeLoan(kind: "biz", amount: 2_000_000, termMonths: 36, companyID: id)
        for _ in 0..<21 { _ = e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        let b = try XCTUnwrap(e.companyBalanceSheet(companyID: id))
        XCTAssertEqual(b.assets.reduce(0) { $0 + $1.amount }, CompanyFigures.assets(co), accuracy: 1)
        XCTAssertEqual(b.debts.reduce(0) { $0 + $1.amount }, CompanyFigures.debts(co, loans: e.state.loans), accuracy: 1)
        XCTAssertEqual(b.equity, b.totalAssets - b.totalDebts, accuracy: 0.01)
        XCTAssertTrue(b.debts.contains { $0.id == "loans" }, "the loan shows as a debt")
    }

    func testLoanPaymentMatchesWhatTheBankSets() throws {
        var (e, id) = try cafe()
        let preview = e.companyLoanPayment(amount: 2_000_000, termMonths: 24, companyID: id)
        XCTAssertEqual(e.takeLoan(kind: "biz", amount: 2_000_000, termMonths: 24, companyID: id), .ok)
        let loan = try XCTUnwrap(e.state.loans.last { $0.companyID == id })
        XCTAssertEqual(loan.monthlyPayment, preview, accuracy: 1)
        XCTAssertGreaterThan(e.companyLoanPayment(amount: 2_000_000, termMonths: 12, companyID: id), preview, "a shorter term costs more a month")
    }

    func testConvertCostAndCashFlow() throws {
        var (e, id) = try cafe()
        let cost = try XCTUnwrap(e.convertToLimitedCost(companyID: id))
        let before = e.state.cash
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        XCTAssertEqual(before - e.state.cash, cost.registrationFee + cost.shareCapital, accuracy: 1)
        XCTAssertNil(e.convertToLimitedCost(companyID: id), "already limited")
        XCTAssertTrue(e.companyCashFlow(companyID: id).allSatisfy { $0.cashChange == nil || $0.otherMovements != nil })
        XCTAssertNil(e.closeNoticeTerms(companyID: -1))
    }
}
