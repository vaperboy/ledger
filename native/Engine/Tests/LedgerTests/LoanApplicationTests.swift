import XCTest
import GameCore
import Finance
import Investments
@testable import Simulation

final class LoanApplicationTests: XCTestCase {
    private func game() throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        e.update { s, _, _ in Ledger.move(&s, .me, 50_000_000, why: "Test funds"); s.credit = 85 }
        return e
    }

    func testQuoteHasFeeDisbursalAndAScheduleThatRepaysTheLoan() throws {
        let e = try game()
        let room = e.loanQuote(kind: "cons", amount: 0, termMonths: 36, companyID: nil).maximum
        let amount = ((room * 0.3) / 1000).rounded(.down) * 1000
        let q = e.loanApplicationQuote(kind: "cons", amount: amount, termMonths: 36, companyID: nil)
        XCTAssertNil(q.refusal)
        XCTAssertEqual(q.schedule.count, 36)
        XCTAssertEqual(q.disbursal, amount - q.fee, accuracy: 0.5)
        XCTAssertGreaterThan(q.fee, 0)
        XCTAssertEqual(q.schedule.last?.balance ?? 1, 0, accuracy: 0.5)
        XCTAssertEqual(q.schedule.reduce(0) { $0 + $1.principal }, amount, accuracy: 1)
        XCTAssertFalse(q.firstPaymentText.isEmpty)
        XCTAssertNotNil(e.loanApplicationQuote(kind: "cons", amount: room + 1_000_000, termMonths: 36, companyID: nil).refusal)
    }

    func testApplicationChecksDocumentsThenPaysOutLessTheFee() throws {
        var e = try game()
        let room = e.loanQuote(kind: "cons", amount: 0, termMonths: 36, companyID: nil).maximum
        let amount = ((room * 0.3) / 1000).rounded(.down) * 1000
        let cash0 = e.state.cash
        let loans0 = e.state.loans.count
        guard case .refused = e.applyForLoan(kind: "cons", amount: amount, termMonths: 36, companyID: nil, documents: LoanDocuments(fullName: "Someone Else", incomeProof: .payslips), agreed: true) else { return XCTFail("name mismatch") }
        guard case .refused = e.applyForLoan(kind: "cons", amount: amount, termMonths: 36, companyID: nil, documents: LoanDocuments(fullName: "Tester"), agreed: true) else { return XCTFail("no proof") }
        guard case .refused = e.applyForLoan(kind: "cons", amount: amount, termMonths: 36, companyID: nil, documents: LoanDocuments(fullName: "Tester", incomeProof: .payslips), agreed: false) else { return XCTFail("not agreed") }
        XCTAssertEqual(e.state.cash, cash0)
        XCTAssertEqual(e.state.loans.count, loans0)
        let q = e.loanApplicationQuote(kind: "cons", amount: amount, termMonths: 36, companyID: nil)
        guard case .approved(_, let fee, let disbursed) = e.applyForLoan(kind: "cons", amount: amount, termMonths: 36, companyID: nil, documents: LoanDocuments(fullName: " tester ", incomeProof: .payslips), agreed: true) else { return XCTFail("should be approved") }
        XCTAssertEqual(fee, q.fee, accuracy: 0.5)
        XCTAssertEqual(e.state.cash, cash0 + disbursed, accuracy: 1)
        XCTAssertEqual(e.state.loans.count, loans0 + 1)
        XCTAssertEqual(e.state.loans.last?.balance ?? 0, amount, accuracy: 0.5)
        XCTAssertFalse(e.loanAgreement(kind: "cons", amount: amount, termMonths: 36, companyID: nil).isEmpty)
    }
}

final class TradeQuoteTests: XCTestCase {
    func testQuotesMatchTheTrades() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 5_000_000, why: "Test funds") }
        for kind in [Brokerage.Kind.stock, .crypto] {
            let sym = try XCTUnwrap(e.quotes(kind).first { !$0.isDelisted }).symbol
            let q = e.buyQuote(kind, symbol: sym, amount: 100_000)
            XCTAssertNil(q.refusal)
            let cash0 = e.state.cash
            XCTAssertEqual(e.buyInvestment(kind, symbol: sym, amount: 100_000), .ok)
            XCTAssertEqual(cash0 - e.state.cash, q.cashChange, accuracy: 1)
            let held = try XCTUnwrap(e.quotes(kind).first { $0.symbol == sym })
            XCTAssertEqual(held.quantity, q.units, accuracy: q.units * 1e-6)
            let sq = e.sellQuote(kind, symbol: sym, fraction: 1)
            let cash1 = e.state.cash
            e.sellInvestment(kind, symbol: sym, fraction: 1)
            XCTAssertEqual(e.state.cash - cash1, sq.cashChange, accuracy: 1)
        }
        XCTAssertNotNil(e.buyQuote(.stock, symbol: "X", amount: 1).refusal)
    }
}
