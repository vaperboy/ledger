import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// The staff-terms gate and the sole trader against limited company comparison.
final class StaffTermsAndLegalFormTests: XCTestCase {
    private func game(form: LegalForm) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, ctx.homeCurrency(s).scaledPrice(5_000_000), why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: form, data: data, context: ctx) { id = i }
        }
        XCTAssertNotEqual(id, 0)
        return (e, id)
    }

    func testStaffTermsUnlockWithAManagerOrFiveStaff() throws {
        var (e, id) = try game(form: .limited)
        XCTAssertFalse(e.staffTermsUnlocked(companyID: 999))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].staff = []
            s.companies[i].managerID = nil
        }
        XCTAssertFalse(e.staffTermsUnlocked(companyID: id))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].staff = (1...5).map { StaffMember(raw: ["id": .number(Double($0))]) }
        }
        XCTAssertTrue(e.staffTermsUnlocked(companyID: id))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].staff = []
            s.companies[i].managerID = 0
        }
        XCTAssertTrue(e.staffTermsUnlocked(companyID: id))
    }

    func testLegalFormComparisonUsesTheTaxFunctions() throws {
        var (e, id) = try game(form: .soleTrader)
        let profit = e.homeCurrency.scaledPrice(80_000)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var b = s.companies[i].books
            b.year = ["rev": profit]
            s.companies[i].books = b
        }
        let r = try XCTUnwrap(e.legalFormCompare(companyID: id))
        let home = e.context.homeCountry(e.state)
        let country = try XCTUnwrap(e.data.countries[try XCTUnwrap(e.state.company(id)).countryCode])
        XCTAssertEqual(r.profit, profit, accuracy: 0.01)
        XCTAssertEqual(r.soleTrader.personalTax, Taxes.personalIncomeTax(profit, kind: .selfEmployed, in: home), accuracy: 0.01)
        XCTAssertEqual(r.soleTrader.keep + r.soleTrader.personalTax, profit, accuracy: 0.01)
        XCTAssertEqual(r.limited.companyTax, max(0, r.limited.taxableProfit) * country.corporateTax, accuracy: 0.01)
        XCTAssertEqual(r.limited.keep, r.limited.keepInCompany - r.limited.personalTax, accuracy: 0.01)
        XCTAssertFalse(r.recommendation.isEmpty)
        XCTAssertEqual(r.currentForm, .soleTrader)
        XCTAssertNil(e.legalFormCompare(companyID: 999))
    }
}
