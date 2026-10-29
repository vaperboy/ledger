import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class CompanyTabsTests: XCTestCase {
    func testActionsRunAndBooksBalance() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester Smith", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 60_000_000) else { return XCTFail("start") }
        let law = e.adviserOffers(companyID: id, kind: .law)
        XCTAssertFalse(law.isEmpty)
        XCTAssertEqual(e.chooseAdviser(companyID: id, kind: .law, providerID: law[0]["id"].int), .done)
        let ins = e.adviserOffers(companyID: id, kind: .insurer)
        XCTAssertEqual(e.chooseAdviser(companyID: id, kind: .insurer, providerID: ins[0]["id"].int), .done)
        XCTAssertEqual(e.toggleInsurancePolicy(companyID: id, product: "prop"), .done)
        _ = e.supplierCandidates(companyID: id, scope: "goods")
        e.chooseGoodsClass(companyID: id, goodsClass: 2)
        XCTAssertEqual(e.give(giftID: "food", countryCode: e.state.homeCountryCode, cityID: e.state.player.cityID), .ok)
        XCTAssertTrue(e.chooseAmbition(path: "dynasty"))
        for _ in 0..<(7 * 30) { e.nextDay() }
        _ = e.frontPages; _ = e.monthlyResults(companyID: id); _ = e.weatherForecast(countryCode: e.state.homeCountryCode)
        _ = e.staffProfile(companyID: id, staffID: 0); _ = e.complaints(companyID: id)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
