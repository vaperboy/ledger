import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Simulation

final class TaxAtSourceTests: XCTestCase {
    private func fresh(_ code: String = "UK") throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 7)
        e.update { s, _, _ in
            Ledger.set(&s, to: 0)
            s.loans.removeAll()
            s.tax = PersonalTaxYear(raw: ["ytd": 0, "paid": 0, "wage": 0, "div": 0, "ytdDiv": 0, "withheld": 0, "gain": 0, "int": 0, "shield": 0])
            Ledger.move(&s, .me, 500_000_000, why: "Test funds")
        }
        return e
    }

    func testAGainPaysTaxAtTheSale() throws {
        var e = try fresh()
        XCTAssertEqual(e.buyInvestment(.fund, symbol: "idx", amount: 5_000_000), .ok)
        e.update { s, _, _ in let px = Brokerage.price(s, .fund, "idx"); s.rest["fundPx"]?["idx"] = .number(px * 1.5) }
        let cash0 = e.state.cash
        let quote = e.sellQuote(.fund, symbol: "idx", fraction: 1)
        e.sellInvestment(.fund, symbol: "idx", fraction: 1)
        let s = e.state
        XCTAssertGreaterThan(s.tax.gains, 0)
        let tax = Taxes.capitalGainsTax(s.tax.gains, in: e.context.homeCountry(s))
        XCTAssertGreaterThan(tax, 0)
        XCTAssertEqual(s.tax.paidGains, tax, accuracy: 1)
        XCTAssertEqual(s.cash - cash0, quote.cashChange - tax, accuracy: 2, "proceeds less the tax on the gain, at the sale")
        XCTAssertEqual(s.statement.first?.label, "Tax on gains")
        XCTAssertEqual(s.statement.first?.amount ?? 0, -tax, accuracy: 1)
    }

    func testWealthTaxIsPaidMonthlyAsATwelfthOfTheYear() throws {
        let book = try CountryBook.bundled()
        let code = try XCTUnwrap(book.countries.first { $0.wealthRate > 0 }?.code)
        var e = try fresh(code)
        e.update { s, data, ctx in
            let c = ctx.homeCountry(s)
            Ledger.move(&s, .me, c.wealthThreshold * 3, why: "Test funds")
            let months = Double(GameCalendar.monthIndex(week: s.week) % 12 + 1)
            let nw = Valuation.netWorth(s, trades: data.catalog).total
            let annual = PersonalFinance.breakdown(s, context: ctx, netWorth: nw, ownedCompanyValue: 0).wealthTax
            XCTAssertGreaterThan(annual, 0)
            MonthEnd.closeMonth(&s, data: data, context: ctx)
            XCTAssertEqual(s.tax.paidWealth, annual * months / 12, accuracy: annual * 0.02, "\(code): the months so far, a twelfth each")
            XCTAssertTrue(s.statement.contains { $0.label == "Wealth tax" })
            let paid = s.tax.paidWealth
            PersonalFinance.withholdWealthTax(&s, context: ctx, netWorth: Valuation.netWorth(s, trades: data.catalog).total, ownedCompanyValue: 0)
            XCTAssertEqual(s.tax.paidWealth, paid, accuracy: annual * 0.01)
        }
    }

    func testYearEndSettlesOnlyTheDifference() throws {
        var e = try fresh()
        e.update { s, _, ctx in
            let c = ctx.homeCountry(s)
            s.tax.gains = 2_000_000
            PersonalFinance.withholdNow(&s, context: ctx)
            let paidOnGains = s.tax.paidGains
            XCTAssertEqual(paidOnGains, Taxes.capitalGainsTax(2_000_000, in: c), accuracy: 1)
            s.tax.gains = 1_500_000
            s.tax.dividends = 3_000_000
            let dividendTax = Taxes.dividendTax(3_000_000, shield: s.tax.dividendShield, in: c)
            let before = s.cash
            PersonalFinance.yearEnd(&s, context: ctx, netWorth: 0, ownedCompanyValue: 0)
            let expectedChange = dividendTax - (paidOnGains - Taxes.capitalGainsTax(1_500_000, in: c))
            XCTAssertEqual(before - (s.cash), expectedChange, accuracy: 3, "only the difference moves at the year end")
            let last = PersonalFinance.lastAssessment(s)
            XCTAssertEqual(last?.total ?? 0, expectedChange, accuracy: 3)
            XCTAssertEqual(last?.paidGains ?? 0, paidOnGains, accuracy: 1)
            XCTAssertEqual((last?.annual ?? 0) - (last?.paidSoFar ?? 0), expectedChange, accuracy: 3, "annual total less paid agrees with the settlement")
            XCTAssertTrue(s.statement.contains { $0.label == "Annual tax true-up: tax on gains" && $0.amount > 0 }, "the refund is its own line")
            XCTAssertEqual(s.tax.paidGains, 0, "a new tax year starts clean")
            XCTAssertEqual(s.tax.paidDividend, 0)
        }
    }

    func testCorporateTaxIsPaidInTheMonthItArises() throws {
        var e = try fresh()
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { return XCTFail("cafe") }
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].status = .open
            s.companies[i].payables["tax"] = 0
            Ledger.moveRaw(&s, .company(id), 100_000_000)
            let rate = data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode).corporateTax
            var b = s.companies[i].books
            b.month = ["rev": 3_000_000]
            s.companies[i].books = b
            let cash0 = s.companies[i].cash
            MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
            XCTAssertEqual(cash0 - s.companies[i].cash, 3_000_000 * rate, accuracy: 2, "the month's tax left the account in the month")
            XCTAssertEqual(s.companies[i].payables["tax"] ?? 0, 0, accuracy: 1)
            XCTAssertTrue(s.companies[i].transactions.contains { $0["l"].string == "Corporate tax" })
        }
    }
}
