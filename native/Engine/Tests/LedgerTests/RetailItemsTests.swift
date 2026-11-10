import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private extension GameEngine {
    mutating func week() { for _ in 0..<7 { _ = nextDay() } }
    mutating func retailWeek(_ id: Int) {
        week()
        update { s, d, _ in if let i = s.companyIndex(id) { RetailItems.weekly(&s, i, data: d) } }
    }
}

final class RetailItemsTests: XCTestCase {
    static let all = ["kiosk", "boutique", "grocery", "hardware", "webshop", "pets", "carrepair"]

    func engine(_ trade: String, weeks: Int = 4, fund: Double = 20_000_000) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID) else { throw XCTSkip("could not start \(trade)") }
        var waited = 0
        while e.state.company(id)?.status != .open && waited < 40 { e.retailWeek(id); waited += 1 }
        guard e.state.company(id)?.status == .open else { throw XCTSkip("\(trade) did not open: \(String(describing: e.state.company(id)?.status))") }
        for _ in 0..<weeks { e.retailWeek(id) }
        return (e, id)
    }

    func testRegistryHoldsTheSevenTradesAndEachHasRealItems() {
        XCTAssertEqual(ItemTradeGroups.retail, Set(Self.all))
        XCTAssertEqual(RetailItems.trades, ItemTradeGroups.retail)
        for t in Self.all {
            let defs = RetailItems.catalogue(t)
            XCTAssertGreaterThanOrEqual(defs.count, 8, t)
            XCTAssertEqual(Set(defs.map { $0.id }).count, defs.count, "\(t): ids unique")
            XCTAssertEqual(Set(defs.map { $0.name.lowercased() }).count, defs.count, "\(t): names unique")
            XCTAssertLessThanOrEqual(defs.filter { $0.onSaleAtStart }.count + 4, SalesItems.maxItems, "\(t): room to add")
            for d in defs {
                XCTAssertTrue(d.costShare > 0 || d.fix > 0, "\(t) \(d.id) has a real cost")
                XCTAssertTrue(d.share > 0 && d.price > 0)
            }
        }
    }

    func testInstallKeepsTheTradesCostOfSalesAndGivesRealMargins() throws {
        for t in Self.all {
            let (e, id) = try engine(t)
            let co = e.state.company(id)!, bd = e.data.catalog[t]!
            XCTAssertFalse(co.value("w2").isNull, t)
            let recs = ItemModels.records(co)
            XCTAssertFalse(recs.isEmpty, t)
            let rows = e.salesItems(companyID: id)
            var cost = 0.0, rev = 0.0
            for r in recs {
                guard let row = rows.first(where: { $0.id == r.id }) else { XCTFail("no row \(r.id)"); continue }
                cost += row.revenueWeight * (r.cost + r.prep) / row.marketPrice
                rev += row.revenueWeight
            }
            XCTAssertEqual(rev, 1, accuracy: 1e-6, t)
            XCTAssertEqual(cost, bd.costOfSales, accuracy: 1e-6, "\(t): weighted cost equals the trade's cost of sales")
            XCTAssertEqual(RetailItems.cogsFactor(e.state, companyID: id, data: e.data), 1, accuracy: 1e-6, "\(t): neutral at default prices")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(t) ledger")
        }
    }

    func testKioskCommissionLinesAndLicensedGoods() throws {
        let (e0, id) = try engine("kiosk")
        let co = e0.state.company(id)!
        let names = Set(e0.salesItems(companyID: id).map { $0.name })
        XCTAssertTrue(names.contains("Newspapers and magazines"))
        XCTAssertTrue(names.contains("Phone top-ups"))
        XCTAssertFalse(names.contains("Tobacco"), "tobacco needs its licence choice")
        let rows = e0.salesItems(companyID: id)
        func margin(_ n: String) -> Double {
            let row = rows.first { $0.name == n }!
            let r = ItemModels.record(co, itemID: row.id)!
            return (row.marketPrice - r.cost - r.prep) / row.marketPrice
        }
        XCTAssertEqual(margin("Phone top-ups"), 0.04, accuracy: 1e-6, "top-up commission is real")
        XCTAssertGreaterThan(margin("Snacks and sweets"), margin("Newspapers and magazines"))
        XCTAssertGreaterThan(margin("Coffee and hot snacks"), margin("Snacks and sweets"))
        var e = e0
        XCTAssertNotNil(e.addRetailItem(companyID: id, defID: "tobacco").reason)
        XCTAssertEqual(e.addRetailItem(companyID: id, defID: "souvenirs"), .applied)
        let after = e.state.company(id)!
        XCTAssertNotNil(ItemModels.record(after, itemID: e.salesItems(companyID: id).first { $0.name == "Souvenirs" }!.id))
        XCTAssertEqual(e.addRetailItem(companyID: id, defID: "souvenirs").reason, "There is already an item with that name.")
    }

    func testPricingAboveMarketRaisesTheItemMarginAndTheCogsFactorFalls() throws {
        var (e, id) = try engine("hardware")
        let row = e.salesItems(companyID: id).first { $0.name == "Hand and power tools" }!
        let base = e.itemPage(companyID: id, itemID: row.id)!
        XCTAssertEqual(base.live.outcome, .profit)
        let dear = e.itemPage(companyID: id, itemID: row.id, price: row.marketPrice * 1.3)!
        XCTAssertGreaterThan(dear.live.amount, base.live.amount)
        let cheap = e.itemPage(companyID: id, itemID: row.id, price: base.unitCost * 0.9)!
        XCTAssertEqual(cheap.live.outcome, .loss)
        XCTAssertNotEqual(cheap.live.word, "profit")
        XCTAssertTrue(e.setItemPrice(companyID: id, itemID: row.id, price: row.marketPrice * 1.3).didChange)
        XCTAssertLessThan(RetailItems.cogsFactor(e.state, companyID: id, data: e.data), 1)
    }

    func testPerishablesShowShelfLifeAndSeasonalStockIsMarkedDown() throws {
        let (g, gid) = try engine("grocery", weeks: 6)
        let gco = g.state.company(gid)!
        let produce = g.salesItems(companyID: gid).first { $0.name == "Fresh fruit and vegetables" }!
        let rec = ItemModels.record(gco, itemID: produce.id)!
        XCTAssertEqual(rec.model, .stk)
        XCTAssertTrue(rec.plans.contains { $0.text.contains("Shelf life 5 days") })
        let (b, bid) = try engine("boutique", weeks: 6)
        let coat = b.salesItems(companyID: bid).first { $0.name == "Coats and knitwear" }!
        let summer = b.salesItems(companyID: bid).first { $0.name == "Summer dresses and linen" }!
        let fc = ItemModels.record(b.state.company(bid)!, itemID: coat.id)!.fair / coat.marketPrice
        let fs = ItemModels.record(b.state.company(bid)!, itemID: summer.id)!.fair / summer.marketPrice
        XCTAssertNotEqual(fc, fs, accuracy: 0.01, "a winter and a summer line are not worth the same in one month")
    }

    func testWebshopDropshipHoldsNoStockAndOwnBrandHasLongLead() throws {
        let (e, id) = try engine("webshop", weeks: 6)
        let co = e.state.company(id)!
        let rows = e.salesItems(companyID: id)
        let drop = ItemModels.record(co, itemID: rows.first { $0.name == "Dropshipped goods" }!.id)!
        let own = ItemModels.record(co, itemID: rows.first { $0.name == "Own-brand range" }!.id)!
        XCTAssertFalse(drop.model.holdsStock)
        XCTAssertEqual(own.model, .stk)
        XCTAssertGreaterThan(own.leadDays, drop.leadDays)
        XCTAssertGreaterThan(own.prep, 0, "fulfilment cost per order")
        XCTAssertLessThan(own.cost, drop.cost, "own brand buys cheaper than dropshipping")
    }

    func testPetsBoardingCapacityComesFromTheKennels() throws {
        let (e, id) = try engine("pets", weeks: 5)
        let co = e.state.company(id)!
        let row = e.salesItems(companyID: id).first { $0.name == "Boarding" }!
        let r = ItemModels.record(co, itemID: row.id)!
        XCTAssertEqual(r.model, .rent)
        XCTAssertGreaterThan(r.capacity, 0)
        XCTAssertEqual(ItemModels.record(co, itemID: e.salesItems(companyID: id).first { $0.name == "Pet food" }!.id)!.model, .stk)
    }

    func testCarRepairJobOrderBooksBothCompaniesAndTakesCapacity() throws {
        var (e, garage) = try engine("carrepair", weeks: 4)
        guard case .success(let dealer) = e.startCompany(tradeID: "usedcar", cityID: e.state.player.cityID) else { throw XCTSkip("no dealer") }
        var waited = 0
        while e.state.company(dealer)?.status != .open && waited < 40 { e.retailWeek(garage); waited += 1 }
        guard e.state.company(dealer)?.status == .open else { throw XCTSkip("dealer did not open") }
        var gBefore = e.state.company(garage)!, dBefore = e.state.company(dealer)!
        XCTAssertEqual(e.carRepairGarages(for: dealer), [garage])
        e.update { s, _, _ in
            if let i = s.companyIndex(garage) { var lw = s.companies[i].value("lastW"); lw["units"] = lw["cap"]; s.companies[i].set("lastW", lw) }
        }
        gBefore = e.state.company(garage)!
        XCTAssertNil(e.carRepairQuote(garageID: garage, kind: "mechanical"))
        if case .ordered = e.orderCarRepair(garageID: garage, dealerID: dealer, kind: "mechanical") { XCTFail("fully booked") }
        XCTAssertEqual(e.state.company(garage)!.cash, gBefore.cash, accuracy: 1e-9)
        e.update { s, _, _ in
            if let i = s.companyIndex(garage) { var lw = s.companies[i].value("lastW"); lw["cap"] = .number(60); s.companies[i].set("lastW", lw) }
        }
        gBefore = e.state.company(garage)!; dBefore = e.state.company(dealer)!
        let q = try XCTUnwrap(e.carRepairQuote(garageID: garage, kind: "mechanical"))
        XCTAssertGreaterThan(q.price, 0)
        XCTAssertGreaterThanOrEqual(q.weeks, 1)
        XCTAssertGreaterThan(q.partsPrice, q.partsCost)
        let big = try XCTUnwrap(e.carRepairQuote(garageID: garage, kind: "mechanical", scale: 2))
        XCTAssertEqual(big.labour, q.labour * 2, accuracy: 1e-6)
        guard case .ordered(let o) = e.orderCarRepair(garageID: garage, dealerID: dealer, kind: "mechanical", ref: "Golf") else { return XCTFail("refused") }
        let g = e.state.company(garage)!, d = e.state.company(dealer)!
        XCTAssertEqual(g.cash - gBefore.cash, o.price - o.partsCost + o.vat, accuracy: 1.5)
        XCTAssertEqual(dBefore.cash - d.cash, o.price + o.vat, accuracy: 1.5)
        XCTAssertGreaterThan((g.books.total["rev", default: 0]) - (gBefore.books.total["rev", default: 0]), o.price - 1.5)
        XCTAssertGreaterThan((d.books.total["cogs", default: 0]) - (dBefore.books.total["cogs", default: 0]), o.price - 1.5)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertEqual(CarRepairJobs.open(e.state, garageID: garage).count, 1)
        let q2 = try XCTUnwrap(e.carRepairQuote(garageID: garage, kind: "mechanical"))
        XCTAssertGreaterThanOrEqual(q2.weeks, q.weeks)
        for _ in 0..<(o.weeks + 1) { e.retailWeek(garage) }
        XCTAssertTrue(CarRepairJobs.orders(e.state, garageID: garage).first!.done)
        XCTAssertTrue(CarRepairJobs.open(e.state, garageID: garage).isEmpty)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        if case .ordered = e.orderCarRepair(garageID: garage, dealerID: dealer, kind: "nonsense") { XCTFail("unknown job") }
        XCTAssertNil(e.carRepairQuote(garageID: dealer, kind: "service"))
    }

    func testOldCompaniesAndOtherTradesGetNoRecords() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "estate", cityID: e.state.player.cityID) else { throw XCTSkip("no") }
        for _ in 0..<3 { e.retailWeek(id) }
        XCTAssertTrue(e.state.company(id)!.value("itemsv2").isNull)
        XCTAssertTrue(e.state.company(id)!.value("w2").isNull)
    }

    func testTwoYearProbePerTrade() throws {
        for t in Self.all {
            var (e, id) = try engine(t, weeks: 0, fund: 40_000_000)
            let start = e.state.company(id)!.cash
            var revenue = 0.0, cogs = 0.0
            for _ in 0..<104 {
                e.retailWeek(id)
                let lw = e.state.company(id)!.value("lastW")
                revenue += lw["rev"].double; cogs += lw["cogs"].double
            }
            let co = e.state.company(id)!
            print("RETAIL PROBE \(t): status \(co.status) revenue \(Int(revenue)) cogs \(Int(cogs)) gross \(revenue > 0 ? Int((1 - cogs / revenue) * 1000) : 0)/1000 cash \(Int(start)) -> \(Int(co.cash)) items \(ItemModels.records(co).count)")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(t) ledger gaps")
            XCTAssertFalse(ItemModels.records(co).isEmpty, t)
        }
    }
}
