import XCTest
@testable import Events
@testable import Businesses
import GameCore
import Countries
import Finance
import Simulation

/// One co-owner buy-back, one big meeting; sale proceeds of a company inside a holding go to the holding; the car-dealer plant discount stays in one country.
final class OwnershipRoutingTests: XCTestCase {
    private func setup() throws -> (GameEngine, cafe: Int, hold: Int) {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        guard case .success(let hid) = e.createHolding(name: "H", companies: []) else { throw XCTSkip("holding") }
        XCTAssertTrue(e.moveToHolding(companyID: cafe, holdingID: hid))
        return (e, cafe, hid)
    }

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

    func testSecondarySaleInsideAHoldingPaysTheHolding() throws {
        var (e, cafe, hold) = try setup()
        let me0 = e.state.cash, h0 = try XCTUnwrap(e.state.company(hold)).cash, gains0 = e.state.tax.gains
        guard case .ok(let amt) = e.sellPrivateShares(companyID: cafe, percent: 20, mode: "secondary") else { return XCTFail("sale") }
        XCTAssertEqual(e.state.cash, me0, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(e.state.company(hold)).cash, h0 + amt, accuracy: 1)
        XCTAssertEqual(e.state.tax.gains, gains0, accuracy: 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(hold)).books.total["gain"] ?? 0, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSecondarySaleOutsideAHoldingStillPaysYou() throws {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        let me0 = e.state.cash, gains0 = e.state.tax.gains
        guard case .ok(let amt) = e.sellPrivateShares(companyID: cafe, percent: 20, mode: "secondary") else { return XCTFail("sale") }
        XCTAssertEqual(e.state.cash, me0 + amt, accuracy: 1)
        XCTAssertGreaterThan(e.state.tax.gains, gains0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSellingAHeldCompanyPaysTheHolding() throws {
        var (e, cafe, hold) = try setup()
        let me0 = e.state.cash, h0 = try XCTUnwrap(e.state.company(hold)).cash, gains0 = e.state.tax.gains
        var got: Double?
        e.update { s, d, c in got = CompanySale.complete(&s, companyIndex: s.companyIndex(cafe)!, buyer: "Buyer", price: 5_000_000, data: d, context: c) }
        let paid = try XCTUnwrap(got)
        XCTAssertEqual(e.state.cash, me0, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(e.state.company(hold)).cash, h0 + paid, accuracy: 1)
        XCTAssertEqual(e.state.tax.gains, gains0, accuracy: 0.001)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
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
        // another country: the plant earns nothing
        prep(plantCountry: "NO")
        var p0 = try XCTUnwrap(e.state.company(plant)).cash
        e.update { s, d, _ in Chains.reachWeek(&s, data: d) }
        XCTAssertEqual(try XCTUnwrap(e.state.company(plant)).cash, p0, accuracy: 0.5)
        // same country: the plant earns what the dealer saves (6% of the dealer's sales)
        let home = try XCTUnwrap(e.state.company(dealer)).countryCode
        prep(plantCountry: home)
        p0 = try XCTUnwrap(e.state.company(plant)).cash
        let d0 = try XCTUnwrap(e.state.company(dealer)).cash
        e.update { s, d, _ in Chains.reachWeek(&s, data: d) }
        let plantGain = try XCTUnwrap(e.state.company(plant)).cash - p0
        let dealerGain = try XCTUnwrap(e.state.company(dealer)).cash - d0
        XCTAssertEqual(plantGain, 6_000, accuracy: 1)
        XCTAssertGreaterThanOrEqual(dealerGain, plantGain - 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
