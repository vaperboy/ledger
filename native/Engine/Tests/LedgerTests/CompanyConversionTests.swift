import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Stage 2, financial.md C1-C10: conversion to a limited company is one real transaction.
final class CompanyConversionTests: XCTestCase {
    private func ctx(_ e: GameEngine) -> FinanceContext { FinanceContext(countries: e.data.countries, trades: e.data.catalog) }

    /// A sole-trader cafe with staff, equipment, stock, documents and a business loan, played for `days`.
    private func trader(_ code: String, days: Int = 30, loan: Bool = true, seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 400_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 120_000_000) else {
            XCTFail("start \(code)"); throw XCTSkip("no company")
        }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        if loan { _ = e.takeLoan(kind: "biz", amount: 3_000_000, termMonths: 36, companyID: id) }
        for _ in 0..<days { _ = e.nextDay() }
        return (e, id)
    }

    func testConversionIsOneTransactionInFiveCountries() throws {
        for code in ["UK", "US", "DE", "NO", "MX"] {
            var (e, id) = try trader(code, days: 40)
            let country = try XCTUnwrap(e.data.countries[code])
            let c0 = try XCTUnwrap(e.state.company(id))
            XCTAssertEqual(c0.form, .soleTrader, code)
            let plan = try XCTUnwrap(e.conversionPlan(companyID: id))
            XCTAssertNil(plan.blocked, code)
            XCTAssertEqual(plan.fee, CompanyConversion.conversionFee(country: country), code)
            XCTAssertEqual(plan.shareCapital, country.shareCapitalMinimum, code)
            XCTAssertTrue(plan.affordable, code)
            let taxBefore = PersonalFinance.taxEstimate(e.state, context: ctx(e))
            let incomeBefore = PersonalFinance.soleTraderIncome(e.state)
            let cashBefore = e.state.cash, coCashBefore = c0.cash
            let nwBefore = e.netWorth.total
            let y = c0.books.year
            let ytd = (y["rev"] ?? 0) - Books.expenses(y)
            XCTAssertEqual(plan.profitClosedIntoPersonalTax, ytd, accuracy: 0.5, code)

            XCTAssertEqual(e.convertToLimited(companyID: id), .ok, code)
            let c = try XCTUnwrap(e.state.company(id))
            XCTAssertEqual(c.form, .limited, code)
            // Money: the owner paid the fee and the capital, the company got the capital.
            XCTAssertEqual(cashBefore - e.state.cash, plan.fee + plan.shareCapital, accuracy: 1, code)
            XCTAssertEqual(c.cash - coCashBefore, plan.shareCapital, accuracy: 1, code)
            XCTAssertEqual(c.shareCapital, country.shareCapitalMinimum, code)
            // Preview equals result.
            XCTAssertEqual(plan.personalBalanceAfter, e.state.cash, accuracy: 1, code)
            XCTAssertEqual(plan.companyBalanceAfter, c.cash, accuracy: 1, code)
            XCTAssertEqual(plan.netWorthAfter, e.netWorth.total, accuracy: 1, code)
            // No tax hole: the pre-conversion profit stays in the personal return.
            XCTAssertEqual(PersonalFinance.soleTraderIncome(e.state), incomeBefore, accuracy: 1, "\(code) sole-trader income must carry over")
            XCTAssertEqual(PersonalFinance.taxEstimate(e.state, context: ctx(e)), taxBefore, accuracy: 2, "\(code) personal tax must carry over")
            XCTAssertEqual(c.yearProfitSoFar, 0, code)
            // Contributed capital carried, so the dividend shield is right.
            XCTAssertGreaterThanOrEqual(c.injectedCapital, c.shareCapital, code)
            XCTAssertEqual(c.injectedCapital, max(c.shareCapital, c.ownerNetFlow), accuracy: 0.5, code)
            // Accountant and agreement as the legal form requires.
            XCTAssertFalse(c.value("acc").isNull, "\(code) accountant appointed")
            XCTAssertEqual(c.value("docs")["accountant_agreement"]["st"].string, "ok", code)
            // Legal identity.
            XCTAssertEqual(c.value("legal")["form"].string, "limited", code)
            XCTAssertEqual(c.value("legal")["hist"].array.count, 1, code)
            let ending = country.companyForms["limitedShort"] ?? ""
            if !ending.isEmpty { XCTAssertTrue(c.name.hasSuffix(ending), "\(code): \(c.name)") }
            // Loans keep the personal guarantee.
            let loans = e.state.loans.filter { $0.companyID == id }
            XCTAssertFalse(loans.isEmpty, code)
            XCTAssertTrue(loans.allSatisfy { $0.isGuaranteed }, "\(code) guarantee stays")
            XCTAssertEqual(plan.loans.count, loans.count, code)
            // Staff and equipment unchanged; value neutral (net worth moves by the fee only, within rounding of the model).
            XCTAssertEqual(c.staff.count, c0.staff.count, code)
            XCTAssertEqual(nwBefore - e.netWorth.total, plan.fee, accuracy: max(5, plan.fee * 0.01 + 5), "\(code) value-neutral: net worth falls by the fee only")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, code)
            // Repeat refused, nothing more moves.
            let cash1 = e.state.cash
            XCTAssertEqual(e.convertToLimited(companyID: id), .alreadyLimited, code)
            XCTAssertEqual(e.state.cash, cash1, code)
        }
    }

    func testPlayedDaysAfterConversionStayConsistent() throws {
        for code in ["UK", "DE"] {
            var (e, id) = try trader(code, days: 40)
            XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
            for _ in 0..<100 { _ = e.nextDay() }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(code) after 100 days")
            XCTAssertEqual(e.state.company(id)?.form, .limited)
            let data = try JSONEncoder().encode(e.state)
            let back = try JSONDecoder().decode(GameState.self, from: data)
            XCTAssertEqual(back, e.state, "\(code) save/load round trip")
            if code == "UK" {
                for _ in 0..<300 { _ = e.nextDay() }
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "UK after 400 days")
                let co = try XCTUnwrap(e.state.company(id))
                XCTAssertFalse(co.value("acc").isNull)
                XCTAssertTrue(co.status.isLive)
                // Group/ownership/net worth consistent: still 100%, counted once.
                XCTAssertEqual(co.ownership, 100)
                let nw = e.netWorth
                XCTAssertEqual(nw.companies, Valuation.companyValue(co, state: e.state, trades: e.data.catalog) * co.ownership / 100, accuracy: 1)
            }
        }
    }

    func testTaxYearIsSplitNotLost() throws {
        var (e, id) = try trader("UK", days: 40, loan: false)
        // Pretend the year so far was very profitable.
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var b = s.companies[i].books
            b.year["rev"] = 5_000_000; b.month["rev"] = 1_000_000
            s.companies[i].books = b
        }
        let before = PersonalFinance.soleTraderIncome(e.state)
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        XCTAssertEqual(PersonalFinance.soleTraderIncome(e.state), before, accuracy: 1)
        XCTAssertGreaterThan(e.state.tax.soleTraderFrozenProfit, 0)
        // The month in which it happened is not taxed twice: the part before conversion is taken off the corporate month.
        XCTAssertEqual(e.state.company(id)?.num("convMonthProfit") ?? 0, 1_000_000 - Books.expenses(e.state.company(id)?.books.month ?? [:]), accuracy: 1)
    }

    func testFeeFromCompanyAccountAndInsufficientFunds() throws {
        var (e, id) = try trader("UK", days: 20, loan: false)
        let plan = try XCTUnwrap(e.conversionPlan(companyID: id, payer: .company))
        XCTAssertEqual(plan.payerOptions.count, 2)
        XCTAssertEqual(plan.accountToCharge, "\(plan.companyName) account")
        let cash0 = e.state.cash, co0 = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertEqual(e.convertToLimited(companyID: id, payer: .company), .ok)
        // The owner paid only the capital; the company paid the fee and received the capital.
        XCTAssertEqual(cash0 - e.state.cash, plan.shareCapital, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, co0 - plan.fee + plan.shareCapital, accuracy: 1)
        XCTAssertTrue(e.state.company(id)?.transactions.contains { $0["l"].string.contains("fee") } ?? false)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)

        // Insufficient: nothing changes, shortfall shown per account.
        var (f, fid) = try trader("UK", days: 20, loan: false)
        f.update { s, _, _ in
            Ledger.move(&s, .me, -s.cash + 1, why: "Spent"); s.savings = 0
        }
        let p2 = try XCTUnwrap(f.conversionPlan(companyID: fid, payer: .personal))
        XCTAssertFalse(p2.affordable)
        XCTAssertGreaterThan(p2.payerOptions[0].shortfall, 0)
        let snapshot = f.state
        XCTAssertEqual(f.convertToLimited(companyID: fid), .notEnoughCash)
        XCTAssertEqual(f.state, snapshot, "nothing changed")
        XCTAssertEqual(f.convertToLimited(companyID: fid, payer: .company), .notEnoughCash, "the owner cannot pay the capital either")
        XCTAssertEqual(f.state, snapshot)
    }

    func testSavingsCountAsAvailableMoney() throws {
        var (e, id) = try trader("UK", days: 20, loan: false)
        e.update { s, _, _ in
            let c = s.cash - 100
            Ledger.move(&s, .me, -c, why: "To savings"); s.savings += c
        }
        let plan = try XCTUnwrap(e.conversionPlan(companyID: id))
        XCTAssertTrue(plan.payerOptions[0].affordable, "savings are drawn on, as for other personal payments")
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        XCTAssertGreaterThanOrEqual(e.state.savings, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testCancelChangesNothing() throws {
        let (e, id) = try trader("UK", days: 20)
        let snapshot = e.state
        _ = e.conversionPlan(companyID: id)
        _ = e.conversionPlan(companyID: id, payer: .company)
        XCTAssertEqual(e.state, snapshot, "reading the review sheet and cancelling changes nothing")
    }

    func testGuaranteeStaysAndCanBeRenegotiatedWithTheBank() throws {
        var (e, id) = try trader("UK", days: 20)
        let loanID = try XCTUnwrap(e.state.loans.first { $0.companyID == id }).id
        XCTAssertNotNil(e.guaranteeTerms(loanID: loanID)?.unavailable, "a sole trader cannot be released")
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        XCTAssertTrue(e.guaranteeTerms(loanID: loanID)?.guaranteed ?? false)
        XCTAssertNotNil(e.guaranteeTerms(loanID: loanID)?.unavailable, "needs three months of accounts as a limited company")
        for _ in 0..<130 { _ = e.nextDay() }
        XCTAssertNil(e.guaranteeTerms(loanID: loanID)?.unavailable)
        // Offering nothing is refused or countered; a generous premium is accepted (in at most a few rounds).
        var released = false
        var margin0 = 0.0
        e.update { s, _, _ in margin0 = s.loans.first { $0.id == loanID }?.margin ?? 0 }
        for _ in 0..<8 where !released {
            switch e.offerGuaranteeRelease(loanID: loanID, extraMargin: 0.08) {
            case .released: released = true
            case .counter, .refused: continue
            case .walkedAway, .notPossible: break
            }
        }
        XCTAssertTrue(released)
        let loan = try XCTUnwrap(e.state.loans.first { $0.id == loanID })
        XCTAssertFalse(loan.isGuaranteed)
        XCTAssertGreaterThan(loan.margin, margin0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testBlockedCases() throws {
        var (e, id) = try trader("UK", days: 10, loan: false)
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        XCTAssertEqual(e.conversionPlan(companyID: id)?.blocked, .alreadyLimited)
        XCTAssertEqual(e.convertToLimited(companyID: 999_999), .unknown)
    }
}
