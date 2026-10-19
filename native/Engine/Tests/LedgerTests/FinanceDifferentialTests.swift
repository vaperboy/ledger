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
