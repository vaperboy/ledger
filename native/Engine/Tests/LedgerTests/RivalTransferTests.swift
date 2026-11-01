import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

/// Stage 4D: buying a rival transfers its staff and equipment, keeps the customers (with a dip in loyalty) and charges integration costs;
/// it does not buy a duplicate set of equipment or hire a second team.
final class RivalTransferTests: XCTestCase {
    func testBuyingARivalBringsStaffEquipmentAndCustomersWithIntegrationCosts() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 777)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 600_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            _ = Payments.injectCash(&s, companyID: id, amount: 40_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(8 * 7) { e.nextDay() }
        let r = try XCTUnwrap(e.rivalRows(try XCTUnwrap(e.state.company(id))).first).rival
        let price = (e.rivalValue(companyID: id, rivalID: r.id) * 1.5 / 1000).rounded() * 1000
        let before = Set(e.state.companies.map { $0.id })
        var result = Rivals.AcquireResult.failed("")
        e.update { s, d, c in result = Rivals.acquire(&s, companyID: id, rivalID: r.id, price: price, data: d, context: c) }
        guard case .ok(let newID) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(before.contains(newID))
        let co = try XCTUnwrap(e.state.company(newID))
        XCTAssertGreaterThan(co.staff.count, 0, "the rival's people came with it")
        XCTAssertGreaterThan(co.value("flags")["integPeople"].double, 0)
        XCTAssertGreaterThan(co.value("flags")["integKit"].double, 0, "equipment transferred")
        XCTAssertGreaterThan(co.value("flags")["integCost"].double, price * Rivals.integrationShare - 1, "retention and integration are charged")
        // equipment is not bought twice: one standard set, at the used value
        let bd = try XCTUnwrap(e.data.catalog["cafe"])
        let need = CompanySetup.standardEquipment(bd, size: co.size)
        for (k, q) in need where bd.equipment.first(where: { $0.id == k })?.vehicleModels == nil {
            XCTAssertEqual(co.value("eq")[k]["n"].double, q, accuracy: 0.001, k)
        }
        // customers stay (reputation carried over) but demand dips while they decide
        XCTAssertGreaterThanOrEqual(co.reputation, 50)
        XCTAssertTrue(co.value("mods").array.contains { $0["k"].string == "dem" && $0["m"].double < 1 }, "a loyalty dip")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
