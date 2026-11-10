import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class EquipmentNeedsTests: XCTestCase {
    func testNoTradeAsksForAnotherTradesItems() throws {
        let cat = try TradeCatalog.bundled()
        for t in cat.all {
            for e in t.foreignItems {
                XCTAssertNil(PersonalEquipment.rule(t, e, tables: cat.tables), "\(t.id) must not need \(e.name)")
            }
        }
    }

    func testCafeWithStaffNeedsNoWorkstationsOrLaptops() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("could not start") }
        let own = Set(try XCTUnwrap(e.data.catalog["cafe"]).equipment.map { $0.id })
        let needs = e.equipmentNeeds(companyID: id)
        XCTAssertTrue(needs.contains { !$0.ofTrade }, "the store still sells other trades' items")
        for n in needs where !own.contains(n.equipmentID) {
            XCTAssertFalse(n.ofTrade)
            XCTAssertEqual(n.need, 0, "\(n.name) is not a café need")
        }
        XCTAssertTrue(needs.filter { $0.ofTrade }.allSatisfy { own.contains($0.equipmentID) })
    }
}
