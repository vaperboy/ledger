import XCTest
import GameCore
import Finance
import Simulation

final class MiscActionsTests: XCTestCase {
    func testRenameConvertAndWindUp() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 40_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 12_000_000) else { return XCTFail("start") }
        XCTAssertEqual(e.renameCompany(companyID: id, to: "x"), .tooShort)
        XCTAssertEqual(e.renameCompany(companyID: id, to: "Blue Door Cafe"), .ok)
        XCTAssertEqual(e.state.company(id)?.name, "Blue Door Cafe")
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        XCTAssertEqual(e.state.company(id)?.form, .limited)
        XCTAssertEqual(e.convertToLimited(companyID: id), .alreadyLimited)
        XCTAssertEqual(e.closeCompany(companyID: id, weeks: 2), .notOpen, "a company not yet open cannot be closed")
        e.setCreditCheck(companyID: id, on: true)
        XCTAssertEqual(e.state.company(id)?.value("flags")["ccheck"].double, 1)
        XCTAssertTrue(e.windUpCompany(companyID: id))
        XCTAssertEqual(e.state.company(id)?.status, .sold)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
