import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

final class LaterProductTests: XCTestCase {
    private func week(_ e: inout GameEngine) { for _ in 0..<7 { _ = e.nextDay() } }

    private func range(_ e: GameEngine, _ id: Int) throws -> Double { SalesItems.rangeFactor(try XCTUnwrap(e.state.company(id))) }

    func testAProductAddedLaterGetsCustomersAndSales() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "bakery", companyName: "Test Bakery", chooseFirstItem: true)
        e.tutorialFinish()
        let id = try XCTUnwrap(e.state.companies.first).id
        let pick = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertEqual(e.chooseFirstItem(companyID: id, itemID: pick.id), .applied)
        let narrow = try range(e, id)
        XCTAssertLessThan(narrow, 1)
        XCTAssertEqual(e.setItemPrice(companyID: id, itemID: pick.id, price: pick.marketPrice * 0.95), .applied)
        XCTAssertEqual(try range(e, id), narrow, accuracy: 1e-12, "a price change does not widen the range")
        for _ in 0..<3 { week(&e) }
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).lastWeekUnits, 0, "the first product sells")
        XCTAssertEqual(try range(e, id), narrow, accuracy: 1e-12)

        XCTAssertEqual(e.addSalesItem(companyID: id, name: "Rye loaf", isService: false), .applied)
        XCTAssertGreaterThan(try range(e, id), narrow, "a second product widens the range and draws more customers")
        for _ in 0..<4 { week(&e) }

        let rows = e.salesItems(companyID: id)
        XCTAssertEqual(rows.count, 2)
        let first = try XCTUnwrap(rows.first { $0.id == pick.id }), later = try XCTUnwrap(rows.first { $0.name == "Rye loaf" })
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).lastWeekUnits, 0)
        XCTAssertGreaterThan(later.weeklyUnits, 0, "the later product has customers")
        XCTAssertGreaterThan(later.weeklyRevenue, 0, "the later product has sales")
        XCTAssertGreaterThan(first.weeklyUnits, 0, "the first product keeps selling")
        let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog[co.type])
        let shares = SalesItems.items(co, bd)
        XCTAssertEqual(shares.reduce(0.0) { $0 + $1.unitShare }, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(shares.first { $0.name == "Rye loaf" }?.unitShare ?? 0, 0.05)
        XCTAssertGreaterThan(e.itemForecast(companyID: id, itemID: later.id, price: later.price, discountPercent: 0).units, 0)
    }

    func testEachAddedProductKeepsItsShareInAVenue() throws {
        var r = try VenueItemsTests.start("gym")
        guard r.id != 0, r.e.state.company(r.id)?.status == .open else { throw XCTSkip("could not open a gym") }
        for _ in 0..<2 { VenueItemsTests.week(&r, withItems: true) }
        let id = r.id
        r.e.update { s, _, _ in if let i = s.companyIndex(id) { SalesItems.markFirstChoicePending(&s, i) } }
        let pick = try XCTUnwrap(r.e.firstItemChoices(companyID: id).first)
        XCTAssertEqual(r.e.chooseFirstItem(companyID: id, itemID: pick.id), .applied)
        XCTAssertEqual(r.e.addSalesItem(companyID: id, name: "Sauna hour", isService: true), .applied)
        func share(_ match: (SalesItems.Item) -> Bool) throws -> Double {
            let co = try XCTUnwrap(r.e.state.company(id)), bd = try XCTUnwrap(r.e.data.catalog[co.type])
            return try XCTUnwrap(SalesItems.items(co, bd).first(where: match)).unitShare
        }
        VenueItemsTests.week(&r, withItems: true)
        let own = try share { $0.name == "Sauna hour" }, first = try share { $0.id == pick.id }
        XCTAssertGreaterThan(own, 0)
        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(own + first, 1, accuracy: 1e-9)
        let it = try XCTUnwrap(r.e.salesItems(companyID: id).first { $0.id == pick.id })
        XCTAssertFalse(r.e.setItemPrice(companyID: id, itemID: pick.id, price: it.marketPrice * 1.05).isRefused)
        for _ in 0..<6 { VenueItemsTests.week(&r, withItems: true) }
        XCTAssertEqual(try share { $0.name == "Sauna hour" }, own, accuracy: 1e-9, "the split does not drift from week to week")
        XCTAssertEqual(try share { $0.id == pick.id }, first, accuracy: 1e-9)
    }
}
