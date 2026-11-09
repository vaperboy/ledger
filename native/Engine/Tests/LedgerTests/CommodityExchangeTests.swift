import XCTest
@testable import GameCore
@testable import Businesses
@testable import Simulation

final class CommodityExchangeTests: XCTestCase {
    func testRawMaterialsAreListedOnTheExchange() throws {
        let e = try ChainsTests.engine()
        let rows = e.exchangeMarket
        for c in CommodityMarket.listed {
            XCTAssertEqual(rows.first { $0.id == PublicExchange.commodityID(c.id) }?.kind, "com", c.id)
        }
    }

    func testThePriceIsTheQuoteTimesTheIndexAndInflation() throws {
        let e = try ChainsTests.engine()
        let oil = try XCTUnwrap(CommodityMarket.def("oil"))
        let expected = oil.quote * e.state.economy.oil * e.state.economy.inflationIndex
        XCTAssertEqual(try XCTUnwrap(e.commodityPrice("oil")), expected, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(PublicExchange.fair(e.state, "com:oil")), expected, accuracy: 1e-9)
    }

    func testSupplyAgainstDemandMovesTheTarget() throws {
        let e = try ChainsTests.engine()
        let oil = try XCTUnwrap(CommodityMarket.def("oil"))
        let calm = CommodityMarket.flows(e.state, oil, shock: 0)
        XCTAssertEqual(CommodityMarket.target(demand: calm.demand, supply: calm.supply, band: oil.band), 1, accuracy: 0.05)
        let glut = CommodityMarket.flows(e.state, oil, shock: 0.3)
        XCTAssertLessThan(CommodityMarket.target(demand: glut.demand, supply: glut.supply, band: oil.band), 1)
        let short = CommodityMarket.flows(e.state, oil, shock: -0.3)
        XCTAssertGreaterThan(CommodityMarket.target(demand: short.demand, supply: short.supply, band: oil.band), 1)
    }

    func testTheExchangeKeepsPricingRawMaterialsThroughTheWeeks() throws {
        var e = try ChainsTests.engine()
        for _ in 0..<56 { _ = e.nextDay() }
        let row = try XCTUnwrap(e.exchangeMarket.first { $0.id == "com:materials" })
        XCTAssertFalse(row.halted)
        XCTAssertGreaterThan(row.close, 0)
    }
}
