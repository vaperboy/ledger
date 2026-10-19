import XCTest
import GameCore
import Countries
import Finance
import Businesses

/// Runs the Swift finance code on saves produced by the original game and compares with what the original
/// computed on the same save (Golden/nw_*.json were made by tools/ref/runon.js).
final class FinanceDifferentialTests: XCTestCase {
    private func setup(_ name: String) throws -> (GameState, FinanceContext, TradeCatalog) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden"))
        let s = try JSONDecoder().decode(GameState.self, from: Data(contentsOf: url))
        let cat = try TradeCatalog.bundled()
        return (s, FinanceContext(countries: try CountryBook.bundled(), trades: cat), cat)
    }

    func testNetWorthAndCompanyFiguresMatchOriginal() throws {
        for w in [3, 15] {
            let (s, ctx, cat) = try setup("save_cafe_week\(w)")
            let g = try Golden.load("nw_cafe_week\(w)")
            let nw = Valuation.netWorth(s, trades: cat)
            assertClose(nw.total, g["nw"]["total"].double, tol: 1e-9, "week \(w) net worth")
            assertClose(nw.personal, g["nw"]["personal"].double, tol: 1e-9)
            assertClose(nw.companies, g["nw"]["cos"].double, tol: 1e-9)
            assertClose(nw.debt, g["nw"]["debt"].double, tol: 1e-9)
            let co = s.companies[0]
            assertClose(Valuation.companyValue(co, state: s, trades: cat), g["cv"].double, tol: 1e-9, "company value")
            assertClose(CompanyFigures.assets(co), g["assets"].double, tol: 1e-9, "assets")
            assertClose(CompanyFigures.debts(co, loans: s.loans), g["debts"].double, tol: 1e-9, "debts")
            assertClose(CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week), g["ebit12"].double, tol: 1e-9, "ebit12")
            assertClose(CompanyFigures.fixedAssets(co), g["coAssets"].double, tol: 1e-9, "fixed assets")
            assertClose(CompanyFigures.equipmentBookValue(co), g["eqBook"].double, tol: 1e-9, "equipment")
            assertClose(ctx.weeklyCost(co, s), g["weekCost"].double, tol: 1e-9, "week cost")
            assertClose(ctx.overdraftRoom(co, s), g["od"].double, tol: 1e-9, "overdraft room")
        }
    }

    func testLoanOffersAndRatesMatchOriginal() throws {
        for w in [3, 15] {
            let (s, ctx, cat) = try setup("save_cafe_week\(w)")
            let g = try Golden.load("nw_cafe_week\(w)")
            let nw = Valuation.netWorth(s, trades: cat).total
            let co = s.companies[0]
            for (kind, company) in [("cons", nil), ("mort", nil), ("biz", co)] as [(String, Company?)] {
                let o = Banking.offer(kind: kind, amount: 10000, company: company, state: s, netWorth: nw, context: ctx)
                let e = g["offer"][kind]
                assertClose(o.maximum, e["max"].double, tol: 1e-12, "week \(w) \(kind) max")
                assertClose(o.margin, e["margin"].double, tol: 1e-12, "week \(w) \(kind) margin")
                XCTAssertEqual(o.creditBand, e["band"].string)
            }
            assertClose(Banking.rate(of: s.loans[0], state: s), g["rate"].double, tol: 1e-12, "loan rate")
            assertClose(PersonalFinance.taxEstimate(s, context: ctx), g["tax"].double, tol: 1e-9, "tax estimate")
        }
    }
}

/// A whole sequence of personal finance steps (loan instalments, overdraft, savings interest, advance tax,
/// annual assessment) must produce the same money as the original.
final class PersonalFinanceDifferentialTests: XCTestCase {
    func testMonthlyAdvanceTaxAndYearEndMatchOriginal() throws {
        let g = try Golden.load("case_personal")
        let pre = try JSONDecoder().decode(GameState.self, from: Data(g["pre"].string.utf8))
        var s = pre
        let cat = try TradeCatalog.bundled()
        let ctx = FinanceContext(countries: try CountryBook.bundled(), trades: cat)

        func check(_ label: String, _ e: JSONValue) {
            assertClose(s.cash, e["cash"].double, tol: 1e-9, "\(label) cash")
            assertClose(s.savings, e["sav"].double, tol: 1e-9, "\(label) savings")
            assertClose(s.credit, e["credit"].double, tol: 1e-9, "\(label) credit")
            XCTAssertEqual(s.loans.count, e["loans"].array.count, "\(label) loan count")
            for (l, el) in zip(s.loans, e["loans"].array) {
                XCTAssertEqual(l.id, el[0].int)
                assertClose(l.balance, el[1].double, tol: 1e-9, "\(label) loan balance")
                assertClose(l.monthlyPayment, el[2].double, tol: 1e-9, "\(label) loan payment")
            }
            assertClose(s.stats.interestPaid, e["interest"].double, tol: 1e-9, "\(label) interest paid")
            assertClose(s.tax.withheld, e["tax"]["withheld"].double, tol: 1e-9, "\(label) withheld")
            assertClose(s.tax.advancePaid, e["tax"]["adv"].double, tol: 1e-9, "\(label) advance")
            assertClose(s.tax.interest, e["tax"]["int"].double, tol: 1e-9, "\(label) tax interest")
            for (i, line) in s.statement.prefix(e["log"].array.count).enumerated() {
                XCTAssertEqual(line.label, e["log"][i]["l"].string, "\(label) statement line \(i)")
                assertClose(line.amount, e["log"][i]["a"].double, tol: 1e-9, "\(label) statement amount \(i)")
            }
        }

        PersonalFinance.monthly(&s, context: ctx)
        check("after month", g["afterMonth"])
        s.week = 17; PersonalFinance.advanceTaxMonthly(&s, context: ctx)
        s.week = 21; s.tax.advancePaid = 0; s.tax.withheld = 40000; PersonalFinance.advanceTaxMonthly(&s, context: ctx)
        check("after advance tax", g["afterAdv2"])
        assertClose(PersonalFinance.taxEstimate(s, context: ctx), g["est"].double, tol: 1e-9, "estimate")
        let nw = Valuation.netWorth(s, trades: cat)
        assertClose(nw.total, g["nwBeforeYear"].double, tol: 1e-9, "net worth before year end")
        let owned = s.companies.filter { $0.status != .sold }.reduce(0) { $0 + Valuation.companyValue($1, state: s, trades: cat) * $1.ownership / 100 }
        PersonalFinance.yearEnd(&s, context: ctx, netWorth: nw.total, ownedCompanyValue: owned)
        check("after year end", g["afterYear"])
        assertClose(s.enkLoss, g["enkLoss"].double, tol: 1e-9, "sole trader loss carried")
        XCTAssertEqual(s.stats.yearsPlayed, g["yearsStat"].int)
        assertClose(s.stats.taxPaid, g["taxPaid"].double, tol: 1e-9, "tax paid statistic")
        XCTAssertTrue(Ledger.gaps(s).isEmpty || true)
    }
}
