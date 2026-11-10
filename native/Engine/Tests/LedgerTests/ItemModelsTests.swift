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

    func testTheOrderQuantityDefaultsToTheMonthlyNeedAndCanBeEdited() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let need = e.itemMonthlyNeed(companyID: id, itemID: it.id)
        XCTAssertGreaterThanOrEqual(need, 1)
        let v = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.offers.first).vendorID
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v).isRefused)
        XCTAssertEqual(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: it.id)?.monthlyUnits, need)
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v, unitsPerMonth: need + 1).isRefused)
        XCTAssertEqual(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: it.id)?.monthlyUnits, need + 1)
        XCTAssertEqual(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v, unitsPerMonth: 0), .refused("Order at least one unit a month."))
    }

    func testThePriceShownIsThePriceAppliedForEachSupplier() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        for o in try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)).offers {
            XCTAssertEqual(o.buyPrice, o.listCost * (1 - Suppliers.discount(e.state, scope: "goods", vendorID: o.vendorID)), accuracy: 1e-9, o.vendorID)
        }
        let v = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.offers.last).vendorID
        e.update { s, _, _ in Suppliers.bumpPublic(&s, v, by: 40) }
        e.update { s, _, _ in var a = s.rest["agree"] ?? .object([:]); a["goods"] = .string(v); s.rest["agree"] = a }
        let shown = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.offers.first { $0.vendorID == v })
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v).isRefused)
        let page = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id))
        let supply = try XCTUnwrap(page.supply)
        XCTAssertEqual(supply.buyPrice, shown.buyPrice, accuracy: 1e-9)
        let r = try XCTUnwrap(page.record)
        XCTAssertEqual(page.unitCost, ItemModels.unitCost(r, weeksHeld: r.since.map { e.state.week - $0 } ?? 0, supplierDiscount: supply.discount), accuracy: 1e-9)
    }

    func testASupplierCannotBeRepickedForFourWeeksButTheFirstPickIsFree() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let offers = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)).offers
        guard offers.count > 1 else { throw XCTSkip("one supplier only") }
        XCTAssertEqual(e.itemRepickWeeksLeft(companyID: id, itemID: it.id), 0)
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: offers[0].vendorID).isRefused)
        XCTAssertEqual(e.itemRepickWeeksLeft(companyID: id, itemID: it.id), ItemModels.repickWeeks)
        XCTAssertTrue(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: offers[1].vendorID).isRefused)
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: offers[0].vendorID, unitsPerMonth: 1).isRefused, "the same supplier may change the order")
        for _ in 0..<3 { e.week() }
        XCTAssertEqual(e.itemRepickWeeksLeft(companyID: id, itemID: it.id), 1)
        XCTAssertTrue(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: offers[1].vendorID).isRefused)
        e.week()
        XCTAssertEqual(e.itemRepickWeeksLeft(companyID: id, itemID: it.id), 0)
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: offers[1].vendorID).isRefused)
        let saved = try XCTUnwrap(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: it.id))
        XCTAssertEqual(saved.supplierID, offers[1].vendorID)
        XCTAssertEqual(saved.pickedWeek, e.state.week)
    }

    func testASupplierCannotTakeMoreThanItCanSupply() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let offer = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.offers.first)
        XCTAssertGreaterThan(offer.capacityFree, 0)
        XCTAssertLessThanOrEqual(offer.capacityFree, offer.capacityTotal)
        let over = e.setItemSupplier(companyID: id, itemID: it.id, vendorID: offer.vendorID, unitsPerMonth: offer.capacityFree + 1)
        XCTAssertEqual(over, .refused("This supplier can only take \(offer.capacityFree) more units a month, you asked for \(offer.capacityFree + 1)."))
        XCTAssertNil(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: it.id)?.supplierID)
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: offer.vendorID, unitsPerMonth: offer.capacityFree).isRefused)
        let left = ItemModels.room(e.state, companyID: id, vendorID: offer.vendorID, excluding: nil, data: e.data).free
        XCTAssertEqual(left, 0)
        XCTAssertEqual(try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.supply).capacityFree, offer.capacityFree)
    }

    func testEndingASupplyCostsTwoWeeksOfTheOrderAndEitherSideCanEndIt() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let offer = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.offers.first)
        let v = offer.vendorID
        let units = max(1, min(13, offer.capacityFree))
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v, unitsPerMonth: units).isRefused)
        let supply = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.supply)
        let fee = Double(units) / (52.0 / 12.0) * supply.buyPrice * 2
        XCTAssertEqual(e.itemCancelFee(companyID: id, itemID: it.id), fee, accuracy: 1e-9)
        let before = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertFalse(e.cancelItemSupplier(companyID: id, itemID: it.id).isRefused)
        XCTAssertEqual(before - (try XCTUnwrap(e.state.company(id)).cash), fee, accuracy: 1)
        let gone = try XCTUnwrap(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: it.id))
        XCTAssertNil(gone.supplierID)
        XCTAssertEqual(gone.monthlyUnits, 0)
        XCTAssertEqual(e.cancelItemSupplier(companyID: id, itemID: it.id), .refused("There is no supplier to end."))
        for _ in 0..<4 { e.week() }
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v, unitsPerMonth: units).isRefused)
        let cash = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertFalse(e.cancelItemSupplier(companyID: id, itemID: it.id, bySupplier: true).isRefused)
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).cash, cash)
    }

    func testComputerPlayersFadeAsRealOnesJoinAndCanBeRemoved() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        let all = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)).offers.count
        XCTAssertGreaterThan(all, 0)
        e.setRealSuppliers(count: 2)
        XCTAssertEqual(try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)).offers.count, max(0, all - 2))
        e.setRealSuppliers(count: 100)
        XCTAssertTrue(try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)).offers.isEmpty)
        e.setRealSuppliers(count: 0)
        XCTAssertEqual(try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)).offers.count, all)
        let v = try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)?.offers.first).vendorID
        XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: it.id, vendorID: v).isRefused)
        XCTAssertFalse(e.fakePlayersRemoved)
        XCTAssertGreaterThanOrEqual(e.removeFakePlayers(), 1)
        XCTAssertTrue(e.fakePlayersRemoved)
        XCTAssertTrue(try XCTUnwrap(e.itemPage(companyID: id, itemID: it.id)).offers.isEmpty)
        XCTAssertNil(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: it.id)?.supplierID)
        XCTAssertTrue(e.supplierCandidates(companyID: id, scope: "goods").isEmpty)
        XCTAssertNil(e.currentGoodsSupplier(companyID: id))
    }

    func testCompanyLogosFollowFreeLevelAndBoxRules() throws {
        var (e, id) = try engine()
        let all = e.logoChoices()
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(Set(all.map { $0.id }).count, all.count)
        XCTAssertTrue(all.allSatisfy { $0.logo.asset == "logo." + $0.id })
        let free = try XCTUnwrap(all.first { $0.logo.source == .free })
        XCTAssertTrue(free.unlocked)
        XCTAssertEqual(e.setCompanyLogo(companyID: id, logoID: free.id), .applied)
        XCTAssertEqual(e.companyLogoID(companyID: id), free.id)
        let box = try XCTUnwrap(all.first { if case .box = $0.logo.source { return true } else { return false } })
        XCTAssertFalse(box.unlocked)
        XCTAssertTrue(e.setCompanyLogo(companyID: id, logoID: box.id).isRefused)
        e.grantLogo(box.id)
        XCTAssertEqual(e.setCompanyLogo(companyID: id, logoID: box.id), .applied)
        XCTAssertEqual(e.setCompanyLogo(companyID: id, logoID: "nothing"), .refused("That logo does not exist."))
        XCTAssertTrue(all.contains { if case .level = $0.logo.source { return true } else { return false } })
    }
}
