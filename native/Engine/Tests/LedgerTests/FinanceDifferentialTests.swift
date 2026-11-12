import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Employees

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
            // The original kept cash in the company; loading folds it into the one account, so it moves from the company's figures to the player's.
            let coCash = try Golden.load("save_cafe_week\(w)")["cos"][0]["cash"].double
            XCTAssertGreaterThan(coCash, 0)
            let nw = Valuation.netWorth(s, trades: cat)
            XCTAssertEqual(nw.total, g["nw"]["total"].double, accuracy: 1, "week \(w) net worth: no money is lost when the company's cash joins the account")
            assertClose(nw.personal, g["nw"]["personal"].double + coCash, tol: 1e-9, "personal")
            XCTAssertEqual(nw.companies, g["nw"]["cos"].double - coCash, accuracy: 1, "companies")
            assertClose(nw.debt, g["nw"]["debt"].double, tol: 1e-9)
            let co = s.companies[0]
            XCTAssertEqual(Valuation.companyValue(co, state: s, trades: cat), g["cv"].double - coCash, accuracy: 1, "company value")
            assertClose(CompanyFigures.assets(co), g["assets"].double - coCash, tol: 1e-9, "assets")
            assertClose(CompanyFigures.debts(co, loans: s.loans), g["debts"].double, tol: 1e-9, "debts")
            assertClose(CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week), g["ebit12"].double, tol: 1e-9, "ebit12")
            assertClose(CompanyFigures.fixedAssets(co), g["coAssets"].double, tol: 1e-9, "fixed assets")
            assertClose(CompanyFigures.equipmentBookValue(co), g["eqBook"].double, tol: 1e-9, "equipment")
            let country = ctx.country(of: co, s)
            let cover = LabourRules(country: country).leaveWeeks / 52 * 0.3
            let leaveCover = co.staff.filter { !$0.isOffSeason }.reduce(0.0) { $0 + $1.monthlyWage * 12 / 52 * country.payrollFactor(monthlyWage: $1.monthlyWage) * cover }
            XCTAssertGreaterThan(leaveCover, 0)
            assertClose(ctx.weeklyCost(co, s), g["weekCost"].double + leaveCover, tol: 1e-9, "week cost")
            assertClose(ctx.overdraftRoom(co, s), max(0, s.overdraftLimit), tol: 1e-9, "the only overdraft is the one on the account")
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
