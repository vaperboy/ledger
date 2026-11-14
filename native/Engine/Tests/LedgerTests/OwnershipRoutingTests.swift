import XCTest
@testable import Events
@testable import Businesses
import GameCore
import Countries
import Finance
import Simulation

final class OwnershipRoutingTests: XCTestCase {
    func testBuyBackTakesOneBoardSeatAway() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("holders", .array([.object(["name": "Ann Owner", "pct": 30, "sat": 50])]))
            s.companies[i].ownership = 70
            s.companies[i].set("flags", .object(["boardSeat": 2]))
        }
        XCTAssertNotNil(e.buyBackPrice(companyID: id, holder: "Ann Owner"))
        XCTAssertTrue(e.buyBackStake(companyID: id, holder: "Ann Owner"))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.value("flags")["boardSeat"].double, 1)
        XCTAssertEqual(co.ownership, 100, accuracy: 0.001)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testBigMeetingStakesAreOwnedByOneSystem() throws {
        var e = try ChainsTests.engine("UK")
        e.update { s, _, _ in s.rest["stakes"] = .array([.object(["id": 1, "name": "X Group", "pct": 25, "val": 1000, "yld": 0.08])]) }
        XCTAssertEqual(e.bigMeetingStakes.count, 1)
        XCTAssertEqual(e.bigMeetingStakes.first?.name, "X Group")
    }

    func testDealerPlantDiscountStaysInOneCountryAndMatches() throws {
        var e = try ChainsTests.engine("UK")
        let dealer = ChainsTests.start(&e, "cardealer")
        let plant = ChainsTests.start(&e, "factory")
        func prep(plantCountry: String) {
            e.update { s, _, _ in
                let di = s.companyIndex(dealer)!, pi = s.companyIndex(plant)!
                s.companies[pi].countryCode = plantCountry
                s.companies[pi].status = .open; s.companies[di].status = .open
                var k = s.companies[pi].value("knob"); k["line"] = 1; s.companies[pi].set("knob", k)
                s.companies[di].set("lastW", .object(["rev": 100_000, "cogs": 80_000]))
            }
        }
        // Both companies draw on the one account, so each side is read from its own cash flow.
        func flow(_ id: Int) -> Double { e.state.cashFlow["co\(id)"] ?? 0 }
        prep(plantCountry: "NO")
        var p0 = flow(plant)
        e.update { s, d, _ in Chains.reachWeek(&s, data: d) }
        XCTAssertEqual(flow(plant), p0, accuracy: 0.5)
        let home = try XCTUnwrap(e.state.company(dealer)).countryCode
        prep(plantCountry: home)
        p0 = flow(plant)
        let d0 = flow(dealer)
        e.update { s, d, _ in Chains.reachWeek(&s, data: d) }
        let plantGain = flow(plant) - p0
        let dealerGain = flow(dealer) - d0
        XCTAssertEqual(plantGain, 6_000, accuracy: 1)
        XCTAssertGreaterThanOrEqual(dealerGain, plantGain - 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
