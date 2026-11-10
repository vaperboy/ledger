import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

final class MoneyProjectsReadModelTests: XCTestCase {
    private func rich(seed: Int = 4242) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 50_000_000, why: "Test funds"); s.credit = 85 }
        return e
    }

    func testLoanQuoteMatchesTheLoanTaken() throws {
        var e = try rich()
        let room = e.loanQuote(kind: "cons", amount: 0, termMonths: 60, companyID: nil).maximum
        let amount = ((room * 0.3) / 1000).rounded(.down) * 1000
        XCTAssertGreaterThan(amount, 0)
        for term in [24, 84] {
            let q = e.loanQuote(kind: "cons", amount: amount, termMonths: term, companyID: nil)
            XCTAssertTrue(q.withinLimit, "the test player should be able to borrow")
            XCTAssertFalse(q.tooSmall)
            let before = Set(e.state.loans.map { $0.id })
            XCTAssertEqual(e.takeLoan(kind: "cons", amount: amount, termMonths: term, companyID: nil), .ok)
            let l = try XCTUnwrap(e.state.loans.first { !before.contains($0.id) })
            XCTAssertEqual(l.termMonths, term)
            XCTAssertEqual(q.monthlyPayment, l.monthlyPayment, accuracy: 0.01)
            XCTAssertEqual(q.totalRepaid, l.monthlyPayment * Double(term), accuracy: 1)
            XCTAssertEqual(q.totalInterest, q.totalRepaid - amount, accuracy: 1)
            XCTAssertGreaterThan(q.totalInterest, 0)
        }
        let short = e.loanQuote(kind: "cons", amount: amount, termMonths: 12, companyID: nil)
        let long = e.loanQuote(kind: "cons", amount: amount, termMonths: 120, companyID: nil)
        XCTAssertLessThan(long.monthlyPayment, short.monthlyPayment)
        XCTAssertGreaterThan(long.totalInterest, short.totalInterest)
        XCTAssertTrue(e.loanQuote(kind: "cons", amount: 10, termMonths: 60, companyID: nil).tooSmall)
    }

    func testDepositQuoteMatchesTheDepositOpened() throws {
        var e = try rich()
        for w in GameEngine.depositTermChoices {
            let q = e.depositQuote(amount: 100_000, weeks: w)
            XCTAssertTrue(e.openDeposit(amount: 100_000, weeks: w))
            let d = try XCTUnwrap(e.deposits.last)
            XCTAssertEqual(q.yearlyRate, d.rate, accuracy: 1e-12)
            XCTAssertEqual(q.interest, 100_000 * d.rate * Double(w) / 52, accuracy: 1e-6)
        }
    }

    func testLoanPayoffRunsToTheEndOfTheTerm() throws {
        var e = try rich()
        let room = e.loanQuote(kind: "cons", amount: 0, termMonths: 60, companyID: nil).maximum
        let amount = ((room * 0.3) / 1000).rounded(.down) * 1000
        let before = Set(e.state.loans.map { $0.id })
        XCTAssertEqual(e.takeLoan(kind: "cons", amount: amount, termMonths: 60, companyID: nil), .ok)
        let l = try XCTUnwrap(e.state.loans.first { !before.contains($0.id) })
        let p = try XCTUnwrap(e.loanPayoff(loanID: l.id))
        XCTAssertEqual(p.monthsLeft, 60)
        XCTAssertEqual(p.interestLeft, l.monthlyPayment * 60 - amount, accuracy: l.monthlyPayment)
        XCTAssertNil(e.loanPayoff(loanID: -1))
    }
}
