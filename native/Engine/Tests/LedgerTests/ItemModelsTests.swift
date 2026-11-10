import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private extension GameEngine {
    mutating func week() { for _ in 0..<7 { _ = nextDay() } }
}

final class ItemModelsTests: XCTestCase {
    /// A trade no item trade group opts in (open at once, sells goods), so these tests cover the foundation whichever groups are on. Pick another if a group adopts it.
    static let trade = "cardealer"
    func engine(_ trade: String = ItemModelsTests.trade, weeks: Int = 8) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: 20_000_000) else { throw XCTSkip("could not start") }
        for _ in 0..<weeks { e.week() }
        XCTAssertEqual(e.state.company(id)?.status, .open, "the throwaway trade must be open for these tests")
        return (e, id)
    }

    func testRegistryIsTheTradeGroupsAndAnEmptySetMigratesNothing() throws {
        XCTAssertEqual(ItemModels.optedInTrades, ItemTradeGroups.all)
        var (e, id) = try engine()
        let before = e.state
        e.update { s, d, _ in XCTAssertEqual(ItemModels.migrateOptedIn(&s, data: d, trades: []), 0) }
        XCTAssertTrue(e.state == before)
        XCTAssertTrue(e.state.company(id)!.value("itemsv2").isNull)
    }

    func testLiveProfitAndLossWordsAndNeverZeroForRealFigures() {
        let p = ItemModels.liveProfit(price: 120, cost: 100)
        XCTAssertEqual(p.outcome, .profit); XCTAssertEqual(p.word, "profit"); XCTAssertEqual(p.amount, 20, accuracy: 1e-9)
        let l = ItemModels.liveProfit(price: 90, cost: 100)
        XCTAssertEqual(l.outcome, .loss); XCTAssertEqual(l.word, "loss"); XCTAssertEqual(l.amount, -10, accuracy: 1e-9)
        let tiny = ItemModels.liveProfit(price: 100.004, cost: 100)
        XCTAssertEqual(tiny.outcome, .profit)
        XCTAssertNotEqual(tiny.amount, 0)
        XCTAssertEqual(ItemModels.liveProfit(price: 100, cost: 100).outcome, .breakEven)
        let c = ItemModels.liveProfit(price: 100, cost: 80, sellingShare: 0.1)
        XCTAssertEqual(c.amount, 10, accuracy: 1e-9)
        XCTAssertEqual(c.margin, 0.1, accuracy: 1e-9)
    }

    func testUnitCostAddsPrepHoldingAndSupplierDiscount() {
        var r = ItemModels.Record(id: "x", model: .brk)
        r.cost = 1000; r.prep = 200; r.holdingPerWeek = 10
        XCTAssertEqual(ItemModels.unitCost(r), 1200, accuracy: 1e-9)
        XCTAssertEqual(ItemModels.unitCost(r, weeksHeld: 5), 1250, accuracy: 1e-9)
        XCTAssertEqual(ItemModels.unitCost(r, weeksHeld: 0, supplierDiscount: 0.1), 1100, accuracy: 1e-9)
    }

    func testSaleProbabilityFallsWithPriceAndHasNoArtificialBounds() {
        let at = ItemModels.saleProbability(price: 100, fair: 100)
        XCTAssertEqual(at, 1 - exp(-ItemModels.baseSaleRate), accuracy: 1e-12)
        var last = 2.0
        for m in stride(from: 0.2, through: 5.0, by: 0.2) {
            let p = ItemModels.saleProbability(price: 100 * m, fair: 100)
            XCTAssertLessThan(p, last); XCTAssertGreaterThan(p, 0); XCTAssertLessThan(p, 1)
            last = p
        }
        XCTAssertEqual(ItemModels.saleProbability(price: 0, fair: 100), 1)
        XCTAssertEqual(ItemModels.saleProbability(price: 100, fair: 0), 0)
        XCTAssertNotNil(ItemModels.expectedWeeks(price: 100, fair: 100))
    }

    func testMigrationRoundTripAndOldItemsUnchanged() throws {
        var (e, id) = try engine()
        let itemsBefore = e.state.company(id)!.value("items27")
        let rowsBefore = e.salesItems(companyID: id)
        var made = 0
        e.update { s, d, _ in made = ItemModels.migrateOptedIn(&s, data: d, trades: [Self.trade]) }
        XCTAssertEqual(made, rowsBefore.count)
        var again = -1
        e.update { s, d, _ in again = ItemModels.migrate(&s, companyID: id, data: d) }
        XCTAssertEqual(again, 0, "idempotent")
        let co = e.state.company(id)!
        XCTAssertTrue(co.value("items27") == itemsBefore, "the old item record is not touched")
        XCTAssertEqual(e.salesItems(companyID: id), rowsBefore)
        let recs = ItemModels.records(co)
        XCTAssertEqual(recs.count, rowsBefore.count)
        XCTAssertTrue(recs.allSatisfy { $0.model == .stk && $0.cost > 0 && $0.stock == 0 })
        // The record cost equals the cost the books already assume, so the live figure is the same before and after migrating.
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertTrue(back == e.state)
        XCTAssertEqual(ItemModels.records(back.company(id)!), recs)
    }

    func testLiveProfitOfOldItemEqualsMigratedItem() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let old = ItemModels.liveProfit(e.state, companyID: id, itemID: it.id, price: it.price, data: e.data)!
        XCTAssertGreaterThan(old.cost, 0)
        e.update { s, d, _ in ItemModels.migrate(&s, companyID: id, data: d) }
        let new = ItemModels.liveProfit(e.state, companyID: id, itemID: it.id, price: it.price, data: e.data)!
        XCTAssertEqual(old.amount, new.amount, accuracy: 1e-6)
    }

    func testStockHistoryAndPlans() throws {
        var (e, id) = try engine()
        let itemID = e.salesItems(companyID: id)[0].id
        e.update { s, d, _ in
            ItemModels.migrate(&s, companyID: id, data: d)
            ItemModels.receive(&s, companyID: id, itemID: itemID, units: 5)
            XCTAssertEqual(ItemModels.take(&s, companyID: id, itemID: itemID, units: 9), 5)
            ItemModels.receive(&s, companyID: id, itemID: itemID, units: 3)
            ItemModels.addPlan(&s, companyID: id, itemID: itemID, kind: "reserve", text: "Held for a customer")
        }
        var r = ItemModels.record(e.state.company(id)!, itemID: itemID)!
        XCTAssertEqual(r.stock, 3); XCTAssertEqual(r.plans.count, 1); XCTAssertNotNil(r.since)
        for _ in 0..<3 { e.week() }
        r = ItemModels.record(e.state.company(id)!, itemID: itemID)!
        XCTAssertEqual(r.history.count, 3)
        XCTAssertTrue(r.history.allSatisfy { $0.units >= 0 })
    }

    func testItemPageForOldAndMigratedItems() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let old = e.itemPage(companyID: id, itemID: it.id)!
        XCTAssertNil(old.record); XCTAssertFalse(old.offers.isEmpty); XCTAssertNil(old.supply)
        XCTAssertEqual(old.statusWord, "On sale")
        XCTAssertGreaterThan(old.saleProbability, 0)
        e.update { s, d, _ in ItemModels.migrate(&s, companyID: id, data: d) }
        let page = e.itemPage(companyID: id, itemID: it.id)!
        XCTAssertNotNil(page.record)
        XCTAssertEqual(page.statusWord, "Sold out")
        XCTAssertFalse(page.offers.isEmpty)
        let low = e.itemPage(companyID: id, itemID: it.id, price: page.unitCost * 0.5)!
        XCTAssertEqual(low.live.outcome, .loss)
        let v = page.offers[0].vendorID
        if case .refused(let why) = e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v) { XCTFail(why) }
        XCTAssertEqual(e.itemPage(companyID: id, itemID: it.id)!.supply?.vendorID, v)
    }

    func testChoosingASupplierForAnItemWithoutARecordCreatesIt() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        XCTAssertEqual(e.supplyAsk(companyID: id, itemID: it.id), .item)
        let v = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.offers.first).vendorID
        XCTAssertNil(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: it.id))
        if case .refused(let why) = e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v) { XCTFail(why) }
        XCTAssertNotNil(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: it.id))
        XCTAssertEqual(e.itemPage(companyID: id, itemID: it.id)?.supply?.vendorID, v)
    }

    func testAServiceNeedsNoItemSupplier() throws {
        var (e, id) = try engine("barber", weeks: 3)
        let it = try XCTUnwrap(e.salesItems(companyID: id).first { $0.isService })
        XCTAssertTrue(try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)).offers.isEmpty)
        XCTAssertEqual(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: "V-UK-0"), .refused("This item needs no supplier."))
        let hasMaterials = e.supplyLines(companyID: id).flatMap { $0.rows }.contains { $0.id == "mat" && $0.canSwitch }
        XCTAssertEqual(e.supplyAsk(companyID: id, itemID: it.id), hasMaterials ? .line("mat") : nil)
    }
}
