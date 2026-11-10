import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class OwnerPayReadsTests: XCTestCase {
    private func gameWithCompany() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, ctx.homeCurrency(s).scaledPrice(5_000_000), why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
        }
        XCTAssertNotEqual(id, 0)
        return (e, id)
    }

    func testOptionsMatchTheTaxFunctions() throws {
        let (e, id) = try gameWithCompany()
        let amount = e.homeCurrency.scaledPrice(100_000)
        let r = try XCTUnwrap(e.ownerPayOptions(companyID: id, amount: amount))
        let home = e.context.homeCountry(e.state)
        let salary = try XCTUnwrap(r.options.first { $0.route == .salary })
        let dividend = try XCTUnwrap(r.options.first { $0.route == .dividend })
        let retain = try XCTUnwrap(r.options.first { $0.route == .retain })

        XCTAssertEqual(dividend.netInHand + dividend.personalTax, amount, accuracy: 0.01)
        XCTAssertEqual(dividend.personalTax, Taxes.dividendTax(amount, shield: e.taxEstimate().shield, in: home), accuracy: 0.01)
        XCTAssertEqual(dividend.companyTaxChange, 0)
        XCTAssertEqual(salary.netInHand + salary.personalTax, amount, accuracy: 0.01)
        XCTAssertGreaterThan(salary.cashFromCompany, amount, "employer contributions come on top")
        XCTAssertLessThan(salary.companyTaxChange, 0, "a salary is deductible")
        XCTAssertEqual(retain.netInHand, 0)
        XCTAssertEqual(retain.totalTax, 0)
    }

    func testNoComparisonWithoutALimitedCompany() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        XCTAssertNil(e.ownerPayOptions(companyID: 999, amount: 1))
    }
}
