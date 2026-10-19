import XCTest
import GameCore
import Businesses

final class TradeCatalogTests: XCTestCase {
    func testCatalogHasAllTradesOfTheOriginal() throws {
        let cat = try TradeCatalog.bundled()
        XCTAssertEqual(cat.trades.count, 67)
        XCTAssertEqual(cat.order.count, 65)  // the menu lists 65; the holding company and football club are created elsewhere
        XCTAssertNotNil(cat["cafe"]); XCTAssertNotNil(cat["hold"]); XCTAssertNotNil(cat["club"])
        XCTAssertEqual(Set(cat.all.map { $0.family }), ["svc", "venue", "retail", "project", "prod", "logi", "rent", "fin", "energy"])
    }

    /// A trade without stored numbers is calibrated from its own data; with a sensible result.
    func testCalibrationFormulaWorksForNewTrades() throws {
        let cat = try TradeCatalog.bundled()
        var t = try XCTUnwrap(cat["cafe"])
        t.normalDemand = 0; t.normalCapacity = 0; t.weeklyFixedCosts = 0
        TradeCatalog.calibrate(&t, tables: cat.tables)
        XCTAssertGreaterThan(t.normalDemand, 0)
        assertClose(t.normalCapacity, t.normalDemand / 0.95, tol: 1e-12)
        // For cafes the recalculation agrees with the stored original values.
        assertClose(t.normalDemand, cat["cafe"]!.normalDemand, tol: 1e-9)
    }

    func testCalibrationMatchesOriginalForEveryTrade() throws {
        let cat = try TradeCatalog.bundled()
        let g = try Golden.load("trades_calibrated")
        for (id, t) in cat.trades {
            let e = g[id]
            if e["Dc"].isNull { continue }
            assertClose(t.normalDemand, e["Dc"].double, tol: 1e-9, "\(id) Dc")
            assertClose(t.normalCapacity, e["capD"].double, tol: 1e-9, "\(id) capD")
            if !e["F"].isNull { assertClose(t.weeklyFixedCosts, e["F"].double, tol: 1e-9, "\(id) F") }
            if !e["vc"].isNull { assertClose(t.variableCostShare, e["vc"].double, tol: 1e-9, "\(id) vc") }
        }
    }

    func testTradeFieldsAreRead() throws {
        let cat = try TradeCatalog.bundled()
        let cafe = try XCTUnwrap(cat["cafe"])
        XCTAssertEqual(cafe.name, "Café")
        XCTAssertEqual(cafe.family, "venue")
        XCTAssertEqual(cafe.ticket, 98)
        XCTAssertEqual(cafe.standardStaff.map { $0.role }, ["barista", "cook", "helper"])
        XCTAssertEqual(cafe.knobs.first?.id, "menu")
        XCTAssertTrue(cafe.equipment.contains { $0.isRequired })
    }
}
