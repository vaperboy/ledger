import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class EquipmentReadsTests: XCTestCase {
    private func start(_ tradeID: String) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: tradeID, cityID: e.state.player.cityID) else { throw XCTSkip("could not start") }
        return (e, id)
    }

    func testCafeHasMachinesOnly() throws {
        let (e, id) = try start("cafe")
        let r = e.equipmentRelevance(companyID: id)
        XCTAssertTrue(r.machines)
        XCTAssertFalse(r.vehicles)
        XCTAssertFalse(r.software)
    }

    func testVehicleTradeShowsVehicles() throws {
        let cat = try TradeCatalog.bundled()
        guard let t = cat.all.first(where: { $0.family == "logi" && $0.equipment.contains { $0.vehicleModels != nil } }) else { throw XCTSkip("no logistics trade with vehicles") }
        let (e, id) = try start(t.id)
        XCTAssertTrue(e.equipmentRelevance(companyID: id).vehicles, "\(t.id) runs vehicles")
    }

    func testUnknownCompanyHasNothing() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let r = e.equipmentRelevance(companyID: -1)
        XCTAssertFalse(r.machines || r.vehicles || r.software)
    }
}
