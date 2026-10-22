import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Wiring of demand, seasons, rivals, price holds and marketing.
final class DemandWiringTests: XCTestCase {
    private func engineWithCafe(weeks: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    func testSouthernHemisphereSeasonIsSixMonthsApart() throws {
        var (e, id) = try engineWithCafe(weeks: 1)
        e.update { s, data, _ in
            let w = World(state: s, data: data)
            guard let bd = data.catalog.all.first(where: { b in
                let c = data.catalog.tables.seasons[b.seasonKey] ?? []
                return c.count == 12 && (c.max() ?? 1) - (c.min() ?? 1) > 0.2
            }), var co = s.company(id) else { return XCTFail("no seasonal trade") }
            let curve = data.catalog.tables.seasons[bd.seasonKey]!
            let m = GameCalendar.month(week: s.week)
            co.countryCode = "UK"
            XCTAssertEqual(DemandModel.season(bd, w, for: co), curve[m])
            XCTAssertEqual(DemandModel.season(bd, w), curve[m])
            co.countryCode = "AU"
            XCTAssertEqual(DemandModel.season(bd, w, for: co), curve[(m + 6) % 12])
        }
    }

    func testHoldingPricesLetsThePriceGapGrowAndSwitchingOffResets() throws {
        var (e, id) = try engineWithCafe(weeks: 2)
        XCTAssertEqual(e.state.company(id)?.num("ig", 1), 1)
        e.setInflationHold(companyID: id, hold: true)
        for _ in 0..<(8 * 7) { e.nextDay() }
        let ig = try XCTUnwrap(e.state.company(id)).num("ig", 1)
        XCTAssertGreaterThan(ig, 1, "a held price falls behind the market")
        e.setInflationHold(companyID: id, hold: false)
        XCTAssertEqual(e.state.company(id)?.num("ig", 1), 1)
        for _ in 0..<(3 * 7) { e.nextDay() }
        XCTAssertEqual(e.state.company(id)?.num("ig", 1), 1, "without a hold the price follows the market")
    }

    func testRivalThatClosedDoesNotComeBackAsTheSameBusiness() throws {
        var (e, id) = try engineWithCafe(weeks: 6)   // set-up takes three weeks; the market record appears the week after it opens
        e.update { s, data, _ in
            guard let co = s.company(id), let bd = data.catalog[co.type] else { return XCTFail("no company") }
            let k = Rivals.key(co)
            var mk = s.rest["mk"] ?? .object([:])
            XCTAssertFalse(mk[k].isNull)
            mk[k]["n"] = 1; mk[k]["riv"] = .array([])
            s.rest["mk"] = mk
            Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
            let first = Rivals.rivals(s, key: k)
            XCTAssertEqual(first.count, 1)
            guard !first.isEmpty else { return }
            Rivals.removeRival(&s, key: k, id: first[0].id)
            XCTAssertTrue(Rivals.rivals(s, key: k).isEmpty)
            Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
            XCTAssertTrue(Rivals.rivals(s, key: k).isEmpty, "a vacated market is not refilled at once")
            s.week = Int(s.rest["mk"]![k]["vac"].double) + 1
            Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
            let second = Rivals.rivals(s, key: k)
            XCTAssertEqual(second.count, 1)
            guard !second.isEmpty else { return }
            XCTAssertNotEqual(second[0].name, first[0].name)
            XCTAssertNotEqual(second[0].id, first[0].id)
        }
    }

    func testCampaignIsPaidForAndStoresNoCustomerPromise() throws {
        var (e, id) = try engineWithCafe(weeks: 2)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: "flyer", weeklyBudget: 20_000), .done)
        let c = try XCTUnwrap(e.state.company(id)).value("mkt")["flyer"]
        XCTAssertEqual(c["b"].double, 20_000)
        XCTAssertTrue(c["customers"].isNull, "a campaign raises awareness, it never books customers")
        for _ in 0..<(4 * 7) { e.nextDay() }
        let after = try XCTUnwrap(e.state.company(id))
        XCTAssertLessThanOrEqual(after.awareness, 100)
        XCTAssertGreaterThan(after.books.year["mkt"] ?? 0, 0, "the spend is booked")
    }
}
