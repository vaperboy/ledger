import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

final class SalesLimitTests: XCTestCase {
    private func freshCafe() throws -> (GameEngine, Int) {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "C")
        return (e, try XCTUnwrap(e.state.companies.first?.id))
    }

    private func setLastWeek(_ e: inout GameEngine, _ id: Int, units: Double, demand: Double, capacity: Double) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            let util: Double = capacity > 0 ? units / capacity : 0
            s.companies[i].set("lastW", .object(["units": .number(units), "rev": 0, "cogs": 0, "D": .number(demand), "cap": .number(capacity), "util": .number(util)]))
        }
    }

    func testCapacityIsTheLimitOnlyWhenItIsUsedUp() {
        XCTAssertEqual(SalesLimit.reading(units: 30, demand: 150, capacity: 100), .held)
        XCTAssertEqual(SalesLimit.reading(units: 97, demand: 150, capacity: 100), .capacity)
        XCTAssertEqual(SalesLimit.reading(units: 60, demand: 62, capacity: 100), .demand)
        XCTAssertEqual(SalesLimit.reading(units: 10, demand: 62, capacity: 100), .held)
        XCTAssertEqual(SalesLimit.reading(units: 0, demand: 40, capacity: 0), .stopped)
        XCTAssertEqual(SalesLimit.reading(units: 0, demand: 0, capacity: 0), .unknown)
    }

    func testAThirdUsedCapacityIsNotCalledTheLimit() throws {
        var (e, id) = try freshCafe()
        XCTAssertEqual(e.state.company(id)?.status, .open)
        XCTAssertTrue(e.data.balance.firstYear.untended(e.state))
        setLastWeek(&e, id, units: 30, demand: 150, capacity: 100)
        let f = try XCTUnwrap(e.operationsFigures(companyID: id))
        XCTAssertEqual(f.capacityUse ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(f.limit.kind, .held)
        XCTAssertEqual(f.limit.name, "Prices not set")
        XCTAssertFalse(f.limit.text.contains("Capacity"))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(e.companyHealth(co).limitedBy, "Prices not set")
        let slack = e.insights(for: co, limit: 20).first { $0.id == "slack" }
        XCTAssertEqual(slack?.text.contains("Held back"), true)
        XCTAssertFalse(e.insights(for: co, limit: 20).contains { $0.id == "cap" })
    }

    func testTheLimitFollowsWhatLastWeekShowed() throws {
        var (e, id) = try freshCafe()
        setLastWeek(&e, id, units: 97, demand: 150, capacity: 100)
        var limit = try XCTUnwrap(e.operationsFigures(companyID: id)).limit
        XCTAssertEqual(limit.kind, .capacity)
        XCTAssertEqual(limit.text, "Capacity is the limit: customers are turned away")
        var h = e.companyHealth(try XCTUnwrap(e.state.company(id)))
        XCTAssertEqual(h.limitedBy, h.bottleneck ?? "Capacity")

        setLastWeek(&e, id, units: 40, demand: 45, capacity: 100)
        limit = try XCTUnwrap(e.operationsFigures(companyID: id)).limit
        XCTAssertEqual(limit.kind, .demand)
        h = e.companyHealth(try XCTUnwrap(e.state.company(id)))
        XCTAssertEqual(h.limitedBy, "Demand")

        setLastWeek(&e, id, units: 0, demand: 45, capacity: 0)
        limit = try XCTUnwrap(e.operationsFigures(companyID: id)).limit
        XCTAssertEqual(limit.kind, .stopped)
        XCTAssertTrue(limit.text.hasPrefix("Served no one last week"))
    }

    func testWeekHistoryKeepsWhatWasServed() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 21)
        e.update { s, _, _ in Ledger.move(&s, .me, 40_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { return XCTFail("start") }
        _ = e.quickSetup(companyID: id)
        for _ in 0..<(7 * 12) { e.nextDay() }
        let f = try XCTUnwrap(e.operationsFigures(companyID: id))
        let last = try XCTUnwrap(f.weeks.last)
        let lw = try XCTUnwrap(e.state.company(id)).value("lastW")
        XCTAssertEqual(last.served, lw["units"].double, accuracy: 1e-9)
        XCTAssertEqual(f.capacityUse ?? -1, last.capacityUse, accuracy: 1e-9)
    }

    func testSettingAnItemPriceEndsTheUntendedStart() throws {
        var (e, id) = try freshCafe()
        XCTAssertTrue(e.data.balance.firstYear.untended(e.state))
        XCTAssertFalse(PlayerGoals.stepDone("sell", e.state))
        let item = try XCTUnwrap(e.salesItems(companyID: id).first)
        XCTAssertEqual(e.setItemPrice(companyID: id, itemID: item.id, price: item.marketPrice * 1.05), .applied)
        XCTAssertTrue(PlayerGoals.stepDone("sell", e.state))
        for _ in 0..<10 { e.nextDay() }
        XCTAssertFalse(e.data.balance.firstYear.untended(e.state), "a price set on the sales screen counts as choosing how to sell")
    }

    func testAPriceSetBeforeCountsForTheGoal() throws {
        var (e, id) = try freshCafe()
        let item = try XCTUnwrap(e.salesItems(companyID: id).first)
        e.update { s, d, _ in SalesItems.setPrice(&s, companyID: id, itemID: item.id, price: item.marketPrice * 0.9, data: d) }
        XCTAssertEqual(e.state.company(id)?.value("chose").int, 0)
        XCTAssertTrue(PlayerGoals.stepDone("sell", e.state))
    }
}
