import XCTest
import GameCore
import Countries
import Finance
@testable import Simulation

/// The Group tab shows each company's value with its change over the last month, read from a per-company day history.
final class CompanyValueChangeTests: XCTestCase {
    func testCompanyValueChangeFollowsItsOwnHistory() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else { return XCTFail("no company") }
        for _ in 0..<5 { e.nextDay() }
        let series = try XCTUnwrap(e.dayHistory.perCompany[id])
        XCTAssertGreaterThanOrEqual(series.count, 5)
        let c = try XCTUnwrap(e.companyValueChange(companyID: id, days: 30))
        XCTAssertEqual(c.amount, (series.last ?? 0) - (series.first ?? 0), accuracy: 1)
        XCTAssertNil(e.companyValueChange(companyID: 99_999, days: 30))
        let cash = try XCTUnwrap(e.groupCashChange(days: 30))
        let cos = e.dayHistory.companyCash
        XCTAssertEqual(cash.amount, (cos.last ?? 0) - (cos.first ?? 0), accuracy: 1)
        XCTAssertEqual(e.groupCash, e.state.companies.filter { $0.status.isLive && $0.type != "hold" }.reduce(0) { $0 + $1.cash }, accuracy: 1)
    }
}
