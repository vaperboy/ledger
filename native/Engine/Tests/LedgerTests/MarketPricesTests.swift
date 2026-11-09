import XCTest
@testable import GameCore
@testable import Businesses
@testable import Simulation

final class MarketPricesTests: XCTestCase {
    private func weeks(_ e: inout GameEngine, _ n: Int) {
        for _ in 0..<(7 * n) { _ = e.nextDay() }
    }

    func testBalancedMarketStaysAtTheGoingPrice() {
        XCTAssertEqual(MarketPrices.equilibrium(demand: 100, supply: 100, backup: 60, elasticity: 1), 1, accuracy: 1e-6)
    }

    func testSurplusLowersAndShortageRaisesThePrice() {
        XCTAssertLessThan(MarketPrices.equilibrium(demand: 100, supply: 120, backup: 60, elasticity: 1), 1)
        XCTAssertGreaterThan(MarketPrices.equilibrium(demand: 100, supply: 80, backup: 60, elasticity: 1), 1)
        XCTAssertEqual(MarketPrices.equilibrium(demand: 100, supply: 100_000, backup: 60, elasticity: 1), MarketPrices.band.lowerBound)
    }

    func testOneCompanyLeavesTheMarketPriceNearTheGoingPrice() throws {
        var e = try ChainsTests.engine()
        let id = DeterminismSavesDatesTests.start(&e, "cafe")
        let co = try XCTUnwrap(e.state.company(id))
        weeks(&e, 3)
        XCTAssertEqual(MarketPrices.index(e.state, country: co.countryCode, trade: "cafe"), 1, accuracy: 0.03)
        XCTAssertGreaterThan(try XCTUnwrap(e.marketPrice(tradeID: "cafe", countryCode: co.countryCode)), 0)
    }

    func testOutsideCompaniesSellingTheSameTradePushThePriceDown() throws {
        var e = try ChainsTests.engine()
        let id = DeterminismSavesDatesTests.start(&e, "cafe")
        let co = try XCTUnwrap(e.state.company(id))
        e.setOutsideSuppliers(countryCode: co.countryCode, players: 5, companies: ["cafe": 200])
        weeks(&e, 30)
        XCTAssertLessThan(MarketPrices.index(e.state, country: co.countryCode, trade: "cafe"), 0.98)
        let info = try XCTUnwrap(e.marketPriceInfo(tradeID: "cafe", countryCode: co.countryCode))
        XCTAssertEqual(info.balanceWord, "Plentiful")
        XCTAssertEqual(info.outsideCompanies, 200)
    }

    func testTheTradePriceFollowsTheGoingPrice() throws {
        var e = try ChainsTests.engine()
        let id = DeterminismSavesDatesTests.start(&e, "cafe")
        let co = try XCTUnwrap(e.state.company(id))
        let before = try XCTUnwrap(e.marketPrice(tradeID: "cafe", countryCode: co.countryCode))
        e.update { s, _, _ in
            var m = s.rest[MarketPrices.key] ?? .object([:])
            m[MarketPrices.marketKey(country: co.countryCode, trade: "cafe")] = .object(["g": .number(1.1)])
            s.rest[MarketPrices.key] = m
        }
        let after = try XCTUnwrap(e.marketPrice(tradeID: "cafe", countryCode: co.countryCode))
        XCTAssertEqual(after / before, 1.1, accuracy: 0.02)
    }
}
