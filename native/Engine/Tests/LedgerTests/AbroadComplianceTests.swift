import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
import Simulation

/// Abroad: new local rules fine a foreign company without a head-office country desk (original `regulationMonth`).
final class AbroadComplianceTests: XCTestCase {
    private func abroadEngine() throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in s.companies[s.companyIndex(cafe)!].reputation = 60; s.companies[s.companyIndex(cafe)!].status = .open }
        let option = try XCTUnwrap(e.abroadOptions(companyID: cafe).first)
        guard case .success(let id) = e.expandAbroad(companyID: cafe, countryCode: option.countryCode) else { XCTFail("no expansion"); return (e, 0) }
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].status = .open; _ = Payments.injectCash(&s, companyID: id, amount: 1_000_000) }
        return (e, id)
    }

    func testMissingCountryDeskLeadsToComplianceFinesOnTheForeignCompany() throws {
        var (e, id) = try abroadEngine()
        let fine0 = e.state.company(id)?.books.year["fine"] ?? 0
        e.update { s, d, _ in for _ in 0..<400 { Abroad.regulationMonth(&s, data: d) } }
        XCTAssertGreaterThan(e.state.company(id)?.books.year["fine"] ?? 0, fine0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testForeignEntityDocumentIsRequiredAbroad() throws {
        let (e, id) = try abroadEngine()
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertFalse(Abroad.hasDesk(e.state, country: co.countryCode))
        XCTAssertNotNil(Documents.definition("foreign_entity", country: try XCTUnwrap(e.data.countries[co.countryCode]), tables: e.data.catalog.tables))
    }
}
