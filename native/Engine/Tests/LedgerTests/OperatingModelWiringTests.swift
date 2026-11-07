import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Wiring checks for how the company families run: leased vehicles are serviced by the lessor.
final class OperatingModelWiringTests: XCTestCase {
    private func upkeepPaid(mode: String) throws -> Double {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        var paid = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
            guard case .success(let id) = CompanySetup.create(&s, tradeID: "airline", cityID: s.player.cityID, form: .limited, data: data, context: ctx),
                  let i = s.companyIndex(id), let bd = data.catalog["airline"] else { return XCTFail("no company") }
            Payments.injectCash(&s, companyID: id, amount: 5_000_000_000)
            s.companies[i].set("eq", .object([:]))
            s.companies[i].set("veh", .array([.object(["id": 1, "eq": "plane", "model": "plane_s", "cost": 180_000_000, "bv": 0, "cond": 1, "km": 0,
                                                        "mode": .string(mode), "loan": 0, "rel": 1, "down": 0, "warr": 0])]))
            let before = s.companies[i].cash
            CompanyCosts.equipmentWeek(&s, companyIndex: i, utilisation: 0.7, bd, data: data)
            paid = before - s.companies[i].cash
        }
        return paid
    }

    func testLeasedVehicleHasNoUpkeepBillButOwnedOneDoes() throws {
        XCTAssertEqual(try upkeepPaid(mode: "lease"), 0, accuracy: 0.5, "the lessor services a leased aircraft")
        XCTAssertGreaterThan(try upkeepPaid(mode: "own"), 0, "an owned aircraft costs upkeep")
    }
}
