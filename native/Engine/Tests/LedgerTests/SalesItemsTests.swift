import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private extension GameEngine {
    mutating func week() { for _ in 0..<7 { _ = nextDay() } }
}

final class SalesItemsTests: XCTestCase {
    func engine(_ trade: String = "bakery", weeks: Int = 3) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { throw XCTSkip("could not start") }
        for _ in 0..<weeks { e.week() }
        return (e, id)
    }

    func testNamesAreCompanySpecificAndStable() throws {
        let (e, id) = try engine(weeks: 0)   // bakery is a recipe trade: after a week its item model installs its real items
        let items = e.salesItems(companyID: id)
        XCTAssertGreaterThanOrEqual(items.count, 3)
        let first = e.state.company(id)!.name.split(separator: " ").first.map(String.init)!
        XCTAssertTrue(items.allSatisfy { $0.name.hasPrefix(first) })
        XCTAssertTrue(items.contains { $0.name.contains("sourdough") })
        XCTAssertEqual(items.map { $0.name }, e.salesItems(companyID: id).map { $0.name })
        XCTAssertEqual(items.reduce(0.0) { $0 + $1.revenueWeight }, 1, accuracy: 1e-9)
        XCTAssertFalse(items[0].isService)
        XCTAssertFalse(e.suggestedItemName(companyID: id, isService: false).isEmpty)
        XCTAssertEqual(e.suggestedItemName(companyID: id, isService: false), e.suggestedItemName(companyID: id, isService: false))
    }

    func testDefaultsAreRevenueNeutral() throws {
        let (e, id) = try engine("estate", weeks: 12)   // a trade no item model installs real items in (bakery now gets them in its first week)
        let co = e.state.company(id)!, bd = e.data.catalog[co.type]!
        XCTAssertEqual(SalesItems.demandFactor(co), 1)
        XCTAssertEqual(SalesItems.ticketFactor(co), 1)
        let w = World(state: e.state, data: e.data)
        XCTAssertEqual(Pricing.ticket(co, bd, w), Pricing.ticket(co, bd, w, withItems: false))
        // touching a price and setting it back to market leaves the company as it was
        var b = e
        let it = b.salesItems(companyID: id)[0]
        XCTAssertEqual(b.setItemPrice(companyID: id, itemID: it.id, price: it.marketPrice), .applied)
        XCTAssertEqual(SalesItems.demandFactor(b.state.company(id)!), 1)
        XCTAssertEqual(SalesItems.ticketFactor(b.state.company(id)!), 1)
        // a new item keeps the weights balanced
        XCTAssertEqual(b.addSalesItem(companyID: id, name: "Maple loaf box", isService: false), .applied)
        let list = b.salesItems(companyID: id)
        XCTAssertEqual(list.reduce(0.0) { $0 + $1.revenueWeight }, 1, accuracy: 1e-9)
        XCTAssertEqual(SalesItems.ticketFactor(b.state.company(id)!), 1)
        XCTAssertTrue(b.addSalesItem(companyID: id, name: "maple LOAF box", isService: false).isRefused)
    }

    func testLowerPriceRaisesUnitsAndHigherLowers() throws {
        let (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let cheap = e.itemForecast(companyID: id, itemID: it.id, price: it.marketPrice * 0.8, discountPercent: 0)
        let dear = e.itemForecast(companyID: id, itemID: it.id, price: it.marketPrice * 1.2, discountPercent: 0)
        let same = e.itemForecast(companyID: id, itemID: it.id, price: it.marketPrice, discountPercent: 0)
        XCTAssertGreaterThan(cheap.units, same.units)
        XCTAssertLessThan(dear.units, same.units)
        XCTAssertGreaterThan(cheap.demandChange, 0)
        XCTAssertLessThan(dear.demandChange, 0)
        XCTAssertEqual(same.demandChange, 0, accuracy: 1e-12)
        XCTAssertEqual(same.profitChange, 0, accuracy: 1e-6)
        XCTAssertEqual(cheap.demandChange, pow(0.8, -1.5) - 1, accuracy: 1e-9)
        var b = e
        XCTAssertEqual(b.setItemPrice(companyID: id, itemID: it.id, price: it.marketPrice * 0.8), .applied)
        XCTAssertGreaterThan(b.salesItems(companyID: id)[0].demandChange, 0)
        XCTAssertGreaterThan(Pricing.demandEffect(b.state.company(id)!, e.data.catalog["bakery"]!, World(state: b.state, data: b.data)),
                             Pricing.demandEffect(e.state.company(id)!, e.data.catalog["bakery"]!, World(state: e.state, data: e.data)))
        XCTAssertTrue(b.setItemPrice(companyID: id, itemID: it.id, price: it.marketPrice * 20).isRefused)
    }

    func testUnroundedPriceIsKeptAndDiscountExpires() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let p = it.marketPrice * 1.0371234567
        XCTAssertEqual(e.setItemPrice(companyID: id, itemID: it.id, price: p), .applied)
        XCTAssertEqual(e.salesItems(companyID: id)[0].price, p, accuracy: 1e-9)
        XCTAssertEqual(e.setItemDiscount(companyID: id, itemID: it.id, percent: 10, weeks: 2), .applied)
        var row = e.salesItems(companyID: id)[0]
        XCTAssertEqual(row.discountPercent, 10)
        XCTAssertEqual(row.discountWeeksLeft, 2)
        XCTAssertGreaterThan(row.demandChange, 0)
        XCTAssertTrue(e.setItemDiscount(companyID: id, itemID: it.id, percent: 90, weeks: 2).isRefused)
        e.week()
        XCTAssertEqual(e.salesItems(companyID: id)[0].discountWeeksLeft, 1)
        e.week()
        row = e.salesItems(companyID: id)[0]
        XCTAssertEqual(row.discountWeeksLeft, 0)
        XCTAssertEqual(row.discountPercent, 0)
        XCTAssertEqual(row.price / row.marketPrice, p / it.marketPrice, accuracy: 1e-6, "the price follows the market as a share")
    }

    func testSaveReloadAndDeterminism() throws {
        var (a, id) = try engine()
        var b = a
        let it = a.salesItems(companyID: id)[1]
        for k in 0..<2 {
            var x = k == 0 ? a : b
            x.setItemPrice(companyID: id, itemID: it.id, price: it.marketPrice * 0.9)
            x.setItemDiscount(companyID: id, itemID: it.id, percent: 15, weeks: 3)
            if k == 0 { a = x } else { b = x }
        }
        let bytes = try JSONEncoder().encode(a.state)
        let loaded = try JSONDecoder().decode(GameState.self, from: bytes)
        XCTAssertTrue(loaded == a.state)
        let (data, events, marketing) = try GameEngine.loadResources()
        var c = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        for _ in 0..<4 { a.week(); b.week(); c.week() }
        XCTAssertTrue(a.state == b.state, "same inputs, same game")
        XCTAssertTrue(a.state == c.state, "reloaded game plays on the same")
        XCTAssertEqual(a.salesItems(companyID: id), c.salesItems(companyID: id))
    }

    func testOwnCompanySaleMovesCashAndProfitToTheSeller() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 90_000_000, why: "Test funds") }
        let city = e.state.player.cityID
        guard case .success(let seller) = e.startCompany(tradeID: "webdev", cityID: city, form: .limited, fundWith: 20_000_000),
              case .success(let buyer) = e.startCompany(tradeID: "cons", cityID: city, form: .limited, fundWith: 20_000_000) else { throw XCTSkip("could not start") }
        for _ in 0..<2 { e.week() }
        XCTAssertTrue(e.ownCompanyListings(forBuyer: buyer).isEmpty, "nothing is listed yet")
        let item = e.salesItems(companyID: seller)[0]
        XCTAssertEqual(e.setItemListedForGroup(companyID: seller, itemID: item.id, listed: true), .applied)
        // a two-week-old company is nearly full; the seller needs room to supply (capacity limits are tested in IntegrationBalanceTests)
        e.update { s, _, _ in let i = s.companyIndex(seller)!; var lw = s.companies[i].value("lastW"); lw["cap"] = 100; s.companies[i].set("lastW", lw) }
        let listing = try XCTUnwrap(e.ownCompanyListings(forBuyer: buyer).first)
        XCTAssertEqual(listing.sellerID, seller)
        XCTAssertEqual(listing.price, item.price, accuracy: 1e-6)
        let sellerCash = e.state.company(seller)!.cash, buyerCash = e.state.company(buyer)!.cash
        let sellerRev = e.state.company(seller)!.books.month["rev"] ?? 0
        let owned = e.state.company(buyer)!.value("eq")[listing.equipmentID]["n"].double
        XCTAssertEqual(e.buyFromOwnCompany(buyer: buyer, seller: seller, itemID: item.id, quantity: 1), .applied)
        XCTAssertLessThan(e.state.company(buyer)!.cash, buyerCash - listing.price + 1)
        XCTAssertGreaterThan(e.state.company(seller)!.cash, sellerCash)
        XCTAssertEqual((e.state.company(seller)!.books.month["rev"] ?? 0) - sellerRev, listing.price.rounded(), accuracy: 1)
        XCTAssertGreaterThan(e.state.company(buyer)!.value("eq")[listing.equipmentID]["n"].double, owned)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // the licence just bought is not offered again: the next listing (if any) fills a different need
        XCTAssertNotEqual(e.ownCompanyListings(forBuyer: buyer).first?.equipmentID, listing.equipmentID)
    }
}
