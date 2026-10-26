import XCTest
import GameCore
import Countries
import Finance
import Investments
@testable import Simulation

/// Audit part 2: loans and early repayment, investments (fees, tax at year end), personal year-end tax in all 23 countries.
final class PersonalFinanceAuditTests: XCTestCase {
    private func game(_ code: String = "UK", seed: Int = 5) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 100_000_000, why: "Test funds") }
        return e
    }

    func testConsumerLoanAmortisesToZeroInItsTermAndEarlyRepaymentWorks() throws {
        var e = try game()
        var id = 0
        var cash0 = 0.0
        var amt = 0.0
        e.update { s, _, ctx in
            s.loans.removeAll()   // the starting loan would blur the totals
            cash0 = s.cash
            amt = Banking.offer(kind: "cons", amount: 0, company: nil, state: s, netWorth: 50_000_000, context: ctx).maximum
            XCTAssertGreaterThan(amt, 50_000, "the bank offers something")
            if case .ok(let l) = Banking.take(kind: "cons", amount: amt, termMonths: 12, company: nil, state: &s, netWorth: 50_000_000, context: ctx) { id = l.id }
            XCTAssertNotEqual(id, 0, "loan granted")
            XCTAssertEqual(s.cash, cash0 + amt, accuracy: 1)
        }
        var paid = 0.0
        for _ in 0..<14 {
            e.update { s, _, ctx in
                let before = s.cash
                Banking.collectMonthlyInstalments(state: &s, context: ctx)
                paid += before - s.cash
                s.week += (s.week % 2 == 0 ? 5 : 4)   // about 4.5 weeks a month, a little over the loan's 4.33
            }
            if e.state.loans.isEmpty { break }
        }
        XCTAssertTrue(e.state.loans.isEmpty, "a 12 month loan is paid off in about 12 instalments")
        XCTAssertGreaterThan(paid, amt, "interest was paid on top of the principal")
        XCTAssertLessThan(paid, amt * 1.25, "but not an absurd amount")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)

        // Early repayment: half, then the rest.
        e.update { s, _, ctx in
            if case .ok(let l) = Banking.take(kind: "cons", amount: amt, termMonths: 24, company: nil, state: &s, netWorth: 50_000_000, context: ctx) { id = l.id }
            XCTAssertNotEqual(id, 0)
            let c = s.cash
            XCTAssertTrue(Banking.repay(loanID: id, amount: amt * 0.4, state: &s))
            XCTAssertEqual(c - s.cash, amt * 0.4, accuracy: 1)
            XCTAssertEqual(s.loans.first { $0.id == id }?.balance ?? 0, amt * 0.6, accuracy: 1)
            XCTAssertTrue(Banking.repay(loanID: id, amount: amt * 10, state: &s), "an over-large amount repays only the balance")
            XCTAssertEqual(c - s.cash, amt, accuracy: 1)
            XCTAssertTrue(s.loans.isEmpty)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testStockAndCryptoFeesAndGainsTaxBase() throws {
        var e = try game()
        e.update { s, _, _ in
            let c0 = s.cash
            XCTAssertEqual(Brokerage.buy(&s, .stock, "FOOD", amount: 1_000_000), .ok)
            XCTAssertEqual(c0 - s.cash, 1_001_000, accuracy: 1, "0.1 % broker fee")
            var st = s.rest["stocks"]!
            var f = st["FOOD"]; f["p"] = .number(f["p"].double * 1.1); st["FOOD"] = f
            s.rest["stocks"] = st
            let g0 = s.tax.gains, c1 = s.cash
            let v = Brokerage.sell(&s, .stock, "FOOD", fraction: 1)
            XCTAssertEqual(s.cash - c1, v - max(29, v * 0.001), accuracy: 1)
            XCTAssertEqual(s.tax.gains - g0, v - max(29, v * 0.001) - 1_001_000, accuracy: 1, "gain = proceeds less fee less cost (the buy fee is in the cost)")
            XCTAssertGreaterThan(s.tax.gains - g0, 80_000)
            // Crypto: spread and fee both ways, so an instant round trip loses about 1.6 % plus 0.8 % fees.
            let c2 = s.cash, g1 = s.tax.gains
            XCTAssertEqual(Brokerage.buy(&s, .crypto, "BTC", amount: 1_000_000), .ok)
            _ = Brokerage.sell(&s, .crypto, "BTC", fraction: 1)
            let loss = c2 - s.cash
            XCTAssertGreaterThan(loss, 20_000); XCTAssertLessThan(loss, 28_000)
            XCTAssertEqual(s.tax.gains - g1, -loss, accuracy: 2, "a loss lowers the taxable gains by exactly what was lost")
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testYearEndPersonalTaxMatchesCountryRulesInAll23Countries() throws {
        let codes = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1).data.countries.countries.map { $0.code }
        for code in codes {
            var e = try game(code, seed: 9)
            e.update { s, data, ctx in
                let c = data.countries.resolve(code, orHome: code)
                s.tax = PersonalTaxYear(raw: ["ytd": 0, "paid": 0, "enkIncome": 0, "wage": 0, "div": 0, "ytdDiv": 0, "withheld": 0, "gain": 0, "int": 0, "shield": 0])
                s.tax.gains = 1_000_000; s.tax.dividends = 500_000; s.tax.dividendShield = 100_000; s.tax.interest = 20_000
                let nw = 400_000_000.0
                let before = s.cash + s.savings
                PersonalFinance.yearEnd(&s, context: ctx, netWorth: nw, ownedCompanyValue: 0)
                let expected = 1_000_000 * c.dividendTax + 400_000 * c.dividendTax + 20_000 * c.dividendTax
                    + max(0, nw - c.wealthThreshold) * c.wealthRate
                XCTAssertEqual(before - (s.cash + s.savings), expected, accuracy: 3, "\(code) year-end tax")
                XCTAssertEqual(s.tax.gains, 0, "\(code) tax year reset")
                XCTAssertEqual(s.tax.dividends, 0, code)
            }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(code) ledger gaps")
        }
    }
}
