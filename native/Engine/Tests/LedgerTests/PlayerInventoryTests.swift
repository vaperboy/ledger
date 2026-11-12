import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation
@testable import Businesses

final class PlayerInventoryTests: XCTestCase {
    private func game(trade: String? = nil, seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds"); s.rest["ldr"] = nil }
        guard let trade else { return (e, 0) }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID) else { throw XCTSkip("no company") }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        // Licences can still be on their way; these tests need a trading company, not the opening wait.
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return (e, id)
    }

    // Companies share the one account, so what a company itself paid or received is read from its own cash flow.
    private func flow(_ e: GameEngine, _ id: Int) -> Double { e.state.cashFlow["co\(id)"] ?? 0 }

    private func balanced(_ e: GameEngine, _ what: String) { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(what): \(Ledger.gaps(e.state))") }

    private func wire(id: String = "w1", kind: String = "car", seen: Double = 0.8, cond: Double = 0.4, base: Double = 100_000) -> JSONValue {
        .object(["id": .string(id), "kind": .string(kind), "title": .string("Test car"), "family": "car_s", "ref": "car_s", "lux": .bool(false), "age": 5, "km": 80_000,
                 "seen": .number(seen), "cond": .number(cond), "base": .number(base)])
    }

    private func item(_ id: String = "x1", kind: String = "car", cond: Double = 0.4, seen: Double = 0.8, base: Double = 2_000_000, paid: Double = 900_000) -> InventoryItem {
        InventoryItem(id: id, kind: kind, title: "Old \(kind)", family: "car_s", ref: "car_s", age: 6, km: 90_000, seen: seen, cond: cond, base: base, paid: paid, luxury: false,
                      lock: "", repairDue: 0, repairTo: 0, repairShop: 0)
    }

    func testPurchaseSettlementPaysOnceAndDeliversTheItem() throws {
        var (e, _) = try game()
        let cur = e.homeCurrencyCode
        let price = 80_000.0
        let paidInternal = e.internalAmount(price, currency: cur)
        let cash0 = e.state.cash
        XCTAssertEqual(e.holdForDeal(dealID: "d1", amount: paidInternal, label: "Held"), .applied)
        XCTAssertEqual(e.state.cash, cash0 - paidInternal, accuracy: 1)
        XCTAssertEqual(e.inventoryHeld(dealID: "d1"), paidInternal, accuracy: 0.01)
        let row = OnlineSettlement(id: "s1", amount: 0, currency: cur, kind: "market_purchase", label: "You bought Test car.",
                                   meta: .object(["dealID": "d1", "price": .number(price), "item": wire(), "title": "Bought: Test car", "tone": "good"]))
        XCTAssertEqual(e.bookOnlineSettlements([row]), ["s1"])
        XCTAssertEqual(e.bookOnlineSettlements([row]), ["s1"])
        XCTAssertEqual(e.inventoryItems.count, 1)
        let got = try XCTUnwrap(e.inventoryItem("w1"))
        XCTAssertEqual(got.kind, "car")
        XCTAssertEqual(got.paid, paidInternal, accuracy: 1)
        XCTAssertLessThan(got.cond, got.seen, "the real condition is below what it looked like")
        XCTAssertTrue(e.inventoryHeld(dealID: "d1") == 0)
        XCTAssertEqual(e.state.cash, cash0 - paidInternal, accuracy: 2, "paid once, not twice")
        XCTAssertTrue(e.state.inbox.contains { $0.body.contains("worse shape") }, "the buyer is told about the hidden condition")
        balanced(e, "purchase")
    }

    func testPurchaseAtAnotherPriceSettlesTheDifference() throws {
        var (e, _) = try game()
        let cur = e.homeCurrencyCode
        let cash0 = e.state.cash
        e.holdForDeal(dealID: "d2", amount: e.internalAmount(1_000, currency: cur), label: "Held")
        let row = OnlineSettlement(id: "s2", amount: 0, currency: cur, kind: "market_purchase", label: "Bought.", meta: .object(["dealID": "d2", "price": 800, "item": wire(id: "w2")]))
        _ = e.bookOnlineSettlements([row])
        XCTAssertEqual(e.state.cash, cash0 - e.internalAmount(800, currency: cur), accuracy: 2, "the special price is what was paid")
        XCTAssertEqual(e.inventoryItem("w2")?.paid ?? 0, e.internalAmount(800, currency: cur), accuracy: 2)
    }

    func testRefundReturnsOnlyWhatWasHeld() throws {
        var (e, _) = try game()
        let cur = e.homeCurrencyCode
        let cash0 = e.state.cash
        e.holdForDeal(dealID: "d3", amount: 5_000_000, label: "Held")
        XCTAssertEqual(e.state.cash, cash0 - 5_000_000, accuracy: 1)
        let refund = OnlineSettlement(id: "r1", amount: 0, currency: cur, kind: "market_refund", label: "Your money is back.", meta: .object(["dealID": "d3"]))
        _ = e.bookOnlineSettlements([refund])
        XCTAssertEqual(e.state.cash, cash0, accuracy: 1)
        let again = OnlineSettlement(id: "r2", amount: 0, currency: cur, kind: "market_refund", label: "Your money is back.", meta: .object(["dealID": "d3"]))
        _ = e.bookOnlineSettlements([again])
        XCTAssertEqual(e.state.cash, cash0, accuracy: 1, "a second refund for the same deal pays nothing")
        balanced(e, "refund")
    }

    func testSaleRemovesTheItemAndPaysTheSeller() throws {
        var (e, _) = try game()
        let cur = e.homeCurrencyCode
        e.update { s, _, _ in PlayerInventory.add(&s, self.item("x9")); PlayerInventory.lockForListing(&s, id: "x9", listingID: "lst") }
        XCTAssertTrue(e.inventoryItem("x9")?.isListed ?? false)
        XCTAssertNotNil(e.inventoryListingProblem(itemID: "x9"))
        let cash0 = e.state.cash
        let row = OnlineSettlement(id: "m1", amount: 120_000, currency: cur, kind: "market_sale", label: "Sold.", meta: .object(["itemID": "x9", "title": "Sold: Old car"]))
        _ = e.bookOnlineSettlements([row])
        XCTAssertNil(e.inventoryItem("x9"))
        XCTAssertEqual(e.state.cash, cash0 + e.internalAmount(120_000, currency: cur), accuracy: 2)
        balanced(e, "sale")
    }

    func testClosedListingUnlocksTheItem() throws {
        var (e, _) = try game()
        e.update { s, _, _ in PlayerInventory.add(&s, self.item("x8")); PlayerInventory.lockForListing(&s, id: "x8", listingID: "lst") }
        let row = OnlineSettlement(id: "u1", amount: 0, currency: e.homeCurrencyCode, kind: "market_unlist", label: "Back in your inventory.", meta: .object(["itemID": "x8"]))
        _ = e.bookOnlineSettlements([row])
        XCTAssertTrue(e.inventoryItem("x8")?.isFree ?? false)
        XCTAssertNil(e.inventoryListingProblem(itemID: "x8"))
    }

    func testNoticeBecomesAnInboxMessageWithTheMarketplaceLink() throws {
        var (e, _) = try game()
        let n0 = e.state.inbox.count
        let row = OnlineSettlement(id: "n1", amount: 0, currency: e.homeCurrencyCode, kind: "market_notice", label: "Someone wants to buy your car.", meta: .object(["title": "Deal request: Old car", "tone": "n"]))
        _ = e.bookOnlineSettlements([row])
        XCTAssertEqual(e.state.inbox.count, n0 + 1)
        let m = try XCTUnwrap(e.state.inbox.first)
        XCTAssertEqual(m.title, "Deal request: Old car")
        XCTAssertEqual(m.appLink, "marketplace")
    }

    func testListingPayloadRoundTripsThroughTheCurrency() throws {
        var (e, _) = try game()
        e.update { s, _, _ in PlayerInventory.add(&s, self.item("x7", base: 3_000_000)) }
        let payload = try XCTUnwrap(e.inventoryListingPayload(itemID: "x7"))
        XCTAssertEqual(payload["id"].string, "x7")
        XCTAssertEqual(payload["kind"].string, "car")
        let back = PlayerInventory.fromWire(e.state, wire: payload, price: 1_000, currency: e.homeCurrencyCode, data: e.data)
        XCTAssertEqual(back.base, 3_000_000, accuracy: 3_000_000 * 0.001)
        XCTAssertEqual(back.cond, 0.4, accuracy: 1e-9)
        XCTAssertEqual(back.seen, 0.8, accuracy: 1e-9)
    }

    func testRepairRaisesConditionAndValueAfterTheWork() throws {
        var (e, _) = try game()
        e.update { s, _, _ in PlayerInventory.add(&s, self.item("r1", cond: 0.35)) }
        let before = try XCTUnwrap(e.inventoryItem("r1"))
        let offers = e.inventoryRepairOffers(itemID: "r1")
        XCTAssertEqual(offers.map { $0.shopID }, [0])
        let offer = try XCTUnwrap(offers.first)
        XCTAssertGreaterThan(offer.valueGain, offer.price, "a car repair pays for itself")
        let cash0 = e.state.cash
        XCTAssertEqual(e.startInventoryRepair(itemID: "r1", shopID: 0), .applied)
        XCTAssertEqual(e.state.cash, cash0 - offer.price, accuracy: 1)
        XCTAssertTrue(e.inventoryItem("r1")?.inRepair ?? false)
        XCTAssertNotNil(e.inventoryListingProblem(itemID: "r1"), "cannot be listed mid-repair")
        XCTAssertTrue(e.startInventoryRepair(itemID: "r1", shopID: 0).isRefused)
        for _ in 0..<(7 * (offer.weeks + 1)) { _ = e.nextDay() }
        let after = try XCTUnwrap(e.inventoryItem("r1"))
        XCTAssertTrue(after.isFree)
        XCTAssertGreaterThanOrEqual(after.cond, PlayerInventory.repairTarget - 1e-9)
        XCTAssertGreaterThan(after.value, before.value + offer.price * 0.9)
        XCTAssertTrue(e.inventoryRepairOffers(itemID: "r1").isEmpty, "nothing left to repair")
    }

    func testOwnRepairShopIsCheaperAndEarnsTheRevenue() throws {
        var (e, shop) = try game(trade: "carrepair")
        e.update { s, _, _ in PlayerInventory.add(&s, self.item("r2", cond: 0.3)) }
        let offers = e.inventoryRepairOffers(itemID: "r2")
        XCTAssertTrue(offers.contains { $0.shopID == shop })
        let own = try XCTUnwrap(offers.first { $0.shopID == shop }), outside = try XCTUnwrap(offers.first { $0.shopID == 0 })
        XCTAssertLessThan(own.price, outside.price)
        XCTAssertLessThanOrEqual(own.weeks, outside.weeks)
        let shopFlow0 = flow(e, shop), me0 = e.state.cashFlow["me"] ?? 0
        let cash0 = e.state.cash
        XCTAssertEqual(e.startInventoryRepair(itemID: "r2", shopID: shop), .applied)
        XCTAssertEqual(me0 - (e.state.cashFlow["me"] ?? 0), own.price, accuracy: 1, "the owner pays the garage's price")
        XCTAssertEqual(flow(e, shop) - shopFlow0, own.price * (1 - PlayerInventory.partsShare), accuracy: 1, "the garage was paid and bought the parts")
        XCTAssertEqual(cash0 - e.state.cash, own.price * PlayerInventory.partsShare, accuracy: 1, "only the parts leave the one account")
        XCTAssertTrue(e.state.company(shop)?.transactions.contains { $0["l"].string.hasPrefix("Repair of") && abs($0["a"].double - own.price) < 1 } ?? false, "the garage books the revenue")
        balanced(e, "own repair")
    }

    func testStockingTheDealershipMovesTheCarAtCostAndKeepsItsCondition() throws {
        var (e, dealer) = try game(trade: "usedcar")
        let lot = try XCTUnwrap(e.usedCarLot(companyID: dealer))
        guard lot.free > 0 else { throw XCTSkip("no lot space") }
        e.update { s, _, _ in PlayerInventory.add(&s, self.item("d1", cond: 0.7, seen: 0.7, paid: 1_000_000)); PlayerInventory.add(&s, self.item("d2", kind: "boat")) }
        XCTAssertNotNil(e.inventoryStockProblem(itemID: "d2", companyID: dealer), "a dealer sells cars and vans")
        let cash0 = e.state.cash, co0 = flow(e, dealer), me0 = e.state.cashFlow["me"] ?? 0
        XCTAssertEqual(e.stockInventoryItem(itemID: "d1", companyID: dealer), .applied)
        XCTAssertNil(e.inventoryItem("d1"))
        XCTAssertEqual((e.state.cashFlow["me"] ?? 0) - me0, 1_000_000, accuracy: 1, "the owner is paid what the car cost")
        XCTAssertEqual(co0 - flow(e, dealer), 1_000_000, accuracy: 1, "the dealer buys it at cost")
        XCTAssertEqual(e.state.cash, cash0, accuracy: 1, "moving a car between the owner and an own company leaves the one account unchanged")
        let stock = try XCTUnwrap(e.state.company(dealer)).value("stk").array
        XCTAssertEqual(stock.count, 1)
        let car = try XCTUnwrap(stock.first)
        XCTAssertEqual(car["cost"].double, 1_000_000, accuracy: 0.01)
        XCTAssertEqual(car["wear"].double, 0.3, accuracy: 1e-9)
        balanced(e, "stock")
    }

    func testDealerRepairRaisesTheWearAndFairValueOfAStockedCar() throws {
        var (e, dealer) = try game(trade: "usedcar")
        guard (e.usedCarLot(companyID: dealer)?.free ?? 0) > 0 else { throw XCTSkip("no lot space") }
        e.update { s, _, _ in PlayerInventory.add(&s, self.item("d3", cond: 0.4, seen: 0.4, paid: 500_000)) }
        XCTAssertEqual(e.stockInventoryItem(itemID: "d3", companyID: dealer), .applied)
        var wearBefore = 0.0, fairBefore = 0.0, wearAfter = 0.0, fairAfter = 0.0
        let stocked = try XCTUnwrap(e.state.company(dealer)?.value("stk").array.first, "the car is on the lot")
        e.update { s, d, _ in
            guard let i = s.companyIndex(dealer) else { return XCTFail("no dealer") }
            var car = stocked
            car["job"] = .object(["due": .number(Double(s.week)), "sup": 0, "sn": "An independent garage", "price": 1_000, "from": .number(Double(s.week))])
            wearBefore = car["wear"].double; fairBefore = car["fair"].double
            XCTAssertTrue(UsedCarDealer.finishJob(&s, i, &car, data: d))
            wearAfter = car["wear"].double; fairAfter = car["fair"].double
        }
        XCTAssertLessThan(wearAfter, wearBefore)
        XCTAssertGreaterThan(fairAfter, fairBefore)
    }

    func testLuxuryPieceGoesToTheInventoryAndBackToTheCollection() throws {
        var (e, _) = try game()
        e.update { s, _, _ in XCTAssertEqual(Luxury.buy(&s, itemID: "c10"), .ok) }
        let piece = try XCTUnwrap(Luxury.pieces(e.state).first)
        XCTAssertNil(e.luxurySaleProblem(pieceID: piece.id))
        XCTAssertEqual(e.moveLuxuryToInventory(pieceID: piece.id), .applied)
        XCTAssertTrue(Luxury.pieces(e.state).isEmpty)
        let it = try XCTUnwrap(e.inventoryItems.first)
        XCTAssertEqual(it.kind, "car")
        XCTAssertTrue(it.luxury)
        XCTAssertTrue(e.inventoryCanKeepLuxury(itemID: it.id))
        XCTAssertEqual(e.keepInventoryLuxury(itemID: it.id), .applied)
        XCTAssertEqual(Luxury.pieces(e.state).count, 1)
        XCTAssertTrue(e.inventoryItems.isEmpty)
        balanced(e, "luxury")
    }

    func testHomesCannotBeListed() throws {
        var (e, _) = try game()
        e.update { s, _, _ in XCTAssertEqual(Luxury.buy(&s, itemID: "h3"), .ok) }
        let piece = try XCTUnwrap(Luxury.pieces(e.state).first)
        XCTAssertNotNil(e.luxurySaleProblem(pieceID: piece.id))
        XCTAssertTrue(e.moveLuxuryToInventory(pieceID: piece.id).isRefused)
    }

    func testInventorySurvivesASaveAndAnOldSaveHasNone() throws {
        var (e, _) = try game()
        XCTAssertTrue(e.inventoryItems.isEmpty)
        let old = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertTrue(PlayerInventory.items(old).isEmpty)
        e.update { s, _, _ in PlayerInventory.add(&s, self.item("p1", cond: 0.5)); PlayerInventory.lockForListing(&s, id: "p1", listingID: "L1") }
        e.holdForDeal(dealID: "dd", amount: 1_000, label: "Held")
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        let it = try XCTUnwrap(PlayerInventory.item(loaded, id: "p1"))
        XCTAssertEqual(it, e.inventoryItem("p1"))
        XCTAssertEqual(it.listingID, "L1")
        XCTAssertEqual(PlayerInventory.holds(loaded)["dd"], 1_000)
    }

    func testHoldNeedsCashAndIsNotTakenTwice() throws {
        var (e, _) = try game()
        let cash0 = e.state.cash
        XCTAssertTrue(e.holdForDeal(dealID: "big", amount: cash0 + 1, label: "Held").isRefused)
        XCTAssertEqual(e.state.cash, cash0)
        XCTAssertEqual(e.holdForDeal(dealID: "once", amount: 500, label: "Held"), .applied)
        XCTAssertEqual(e.holdForDeal(dealID: "once", amount: 500, label: "Held"), .applied)
        XCTAssertEqual(e.state.cash, cash0 - 500, accuracy: 1)
        XCTAssertEqual(e.releaseDealHold(dealID: "once"), 500, accuracy: 0.01)
        XCTAssertEqual(e.state.cash, cash0, accuracy: 1)
    }
}
