import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private extension GameEngine {
    mutating func week() { for _ in 0..<7 { _ = nextDay() } }
}

final class FoodRecipesTests: XCTestCase {
    static let all = ["bakery", "cafe", "restaurant", "foodtruck", "brewery", "vineyard", "farm"]

    func engine(_ trade: String, weeks: Int = 6) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 150_000_000) else { throw XCTSkip("could not start \(trade)") }
        _ = e.quickSetup(companyID: id); _ = e.openCompany(companyID: id)
        var waited = 0
        while e.state.company(id)?.status != .open, waited < 60 { e.week(); waited += 1 }
        for _ in 0..<weeks { e.week() }
        return (e, id)
    }

    func testRegistryHoldsTheSevenTrades() {
        XCTAssertEqual(ItemTradeGroups.food, Set(Self.all))
        XCTAssertTrue(ItemTradeGroups.food.isSubset(of: ItemModels.optedInTrades))
        for t in Self.all { XCTAssertNotNil(FoodRecipes.recipe(trade: t, itemID: "n1", name: "Something new")) }
    }

    func testEveryTradeGetsRealProductsWithRecipeCostEqualToTheBooks() throws {
        for t in Self.all {
            var (e, id) = try engine(t)
            let revBefore = e.salesItems(companyID: id).reduce(0.0) { $0 + $1.weeklyRevenue }
            var n = 0
            e.update { s, d, _ in n = FoodRecipes.apply(&s, companyID: id, data: d) }
            let rows = e.salesItems(companyID: id)
            XCTAssertGreaterThanOrEqual(n, 5, t)
            XCTAssertEqual(rows.count, n, t)
            XCTAssertTrue(rows.allSatisfy { $0.id.hasPrefix("w3-") }, t)
            XCTAssertEqual(rows.reduce(0.0) { $0 + $1.weeklyRevenue }, revBefore, accuracy: max(1e-6, revBefore * 1e-9), "\(t): demand and revenue do not move")
            let co = e.state.company(id)!
            let bd = e.data.catalog[t]!
            var inputs = 0.0, all = 0.0, shares: [Double] = []
            for row in rows {
                let r = try XCTUnwrap(ItemModels.record(co, itemID: row.id), "\(t) \(row.name)")
                XCTAssertTrue(r.model == .made || r.model == .stk, t)
                XCTAssertGreaterThan(r.cost, 0, row.name)
                XCTAssertNotNil(r.supplierID, "\(t) \(row.name) has a supplier")
                XCTAssertGreaterThan(r.stock, 0)
                let w = row.revenueWeight
                inputs += w * r.cost / row.marketPrice
                all += w * (r.cost + r.prep) / row.marketPrice
                shares.append(r.cost / row.marketPrice)
            }
            XCTAssertEqual(inputs, bd.costOfSales, accuracy: 1e-9, "\(t) food cost equals cost of sales")
            let waste = (bd.traits["perish"] ?? 0) * 0.6 + (bd.traits["shrink"] ?? 0) * 0.3
            XCTAssertEqual(all - inputs, waste, accuracy: 1e-9, "\(t) spoilage equals perish and shrink")
            XCTAssertGreaterThan((shares.max() ?? 0) - (shares.min() ?? 0), 0.02, "\(t): items differ in food cost")
            let k = FoodRecipes.scales(trade: t, bd)
            XCTAssertTrue(k.inputs > 0.75 && k.inputs < 1.3, "\(t) authored recipes are realistic: scale \(k.inputs)")
            var again = -1
            e.update { s, d, _ in again = FoodRecipes.apply(&s, companyID: id, data: d) }
            XCTAssertEqual(again, n, "\(t) idempotent refresh")
            XCTAssertEqual(e.salesItems(companyID: id).count, n)
        }
    }

    func testCardLiveProfitAndSupplierDiscount() throws {
        var (e, id) = try engine("restaurant")
        e.update { s, d, _ in FoodRecipes.apply(&s, companyID: id, data: d) }
        let main = try XCTUnwrap(e.salesItems(companyID: id).first { $0.id == "w3-main" })
        let c = try XCTUnwrap(FoodRecipes.card(e.state, companyID: id, itemID: "w3-main", data: e.data))
        XCTAssertEqual(c.lines.count, 4)
        XCTAssertGreaterThan(c.foodCostPercent, 0.15); XCTAssertLessThan(c.foodCostPercent, 0.5)
        XCTAssertEqual(c.unitCost, c.inputCost + c.spoilageCost, accuracy: 1e-9)
        XCTAssertGreaterThan(c.capacityPerWeek, 0)
        let page = try XCTUnwrap(e.itemPage(companyID: id, itemID: "w3-main"))
        XCTAssertEqual(page.record?.model, .made)
        XCTAssertEqual(page.live.cost, c.unitCost, accuracy: 1e-6, "the page and the card show one cost")
        XCTAssertEqual(page.live.outcome, main.price > page.unitCost ? .profit : .loss)
        XCTAssertEqual(e.itemPage(companyID: id, itemID: "w3-main", price: page.unitCost * 0.5)?.live.outcome, .loss)
        XCTAssertTrue(page.statusWord.hasPrefix("In stock"))
        let wine = try XCTUnwrap(ItemModels.record(e.state.company(id)!, itemID: "w3-wine"))
        XCTAssertEqual(wine.model, .stk, "wine is bought in")
        // A hand-added item gets the trade's average recipe.
        _ = e.addSalesItem(companyID: id, name: "Pop-up supper", isService: false)
        e.update { s, d, _ in FoodRecipes.apply(&s, companyID: id, data: d) }
        XCTAssertNotNil(FoodRecipes.card(e.state, companyID: id, itemID: "n1", data: e.data))
    }

    func testCapacityLeadTimeAndHarvestNotes() throws {
        var (e, id) = try engine("vineyard")
        e.update { s, d, _ in FoodRecipes.apply(&s, companyID: id, data: d) }
        let r = try XCTUnwrap(ItemModels.record(e.state.company(id)!, itemID: "w3-red"))
        XCTAssertEqual(r.leadDays, 540)
        XCTAssertGreaterThan(r.onOrder, 0, "wine is ageing in barrels, status \(e.state.company(id)!.status), units \(e.salesItems(companyID: id).map { $0.weeklyUnits })")
        XCTAssertTrue(r.plans.contains { $0.text.contains("Vintage") })
        var (b, bid) = try engine("brewery")
        b.update { s, d, _ in FoodRecipes.apply(&s, companyID: bid, data: d) }
        let lager = try XCTUnwrap(ItemModels.record(b.state.company(bid)!, itemID: "w3-lager"))
        XCTAssertEqual(lager.leadDays, 28)
        XCTAssertGreaterThan(lager.capacity, 0)
    }

    func testWeeklyTickFollowsTheMarketAndKeepsOtherTradesUntouched() throws {
        var (e, id) = try engine("bakery")
        var other = try engine("barber", weeks: 2)
        let before = other.0.state
        other.0.update { s, d, _ in FoodRecipes.weeklyTick(&s, data: d) }
        XCTAssertTrue(other.0.state == before, "trades outside the group are untouched")
        e.update { s, d, _ in FoodRecipes.weeklyTick(&s, data: d) }
        let a = ItemModels.record(e.state.company(id)!, itemID: "w3-sourdough")!
        for _ in 0..<3 { e.week(); e.update { s, d, _ in FoodRecipes.weeklyTick(&s, data: d) } }
        let b = ItemModels.record(e.state.company(id)!, itemID: "w3-sourdough")!
        XCTAssertGreaterThan(b.cost, 0); XCTAssertEqual(a.model, b.model)
        XCTAssertEqual(b.plans.filter { $0.kind == "w3" }.count, Set(b.plans.filter { $0.kind == "w3" }.map { $0.text }).count)
        let data = try JSONEncoder().encode(e.state)
        XCTAssertTrue(try JSONDecoder().decode(GameState.self, from: data) == e.state)
    }

    /// Two years of a default-managed company per trade, once with the item records (records refreshed every week) and once without: the books are the same.
    func testTwoYearProbePerTrade() throws {
        for t in Self.all {
            var (a, ida) = try engine(t, weeks: 0)
            var (b, idb) = try engine(t, weeks: 0)
            var profitA = 0.0, profitB = 0.0
            for _ in 0..<104 {
                a.week(); b.week()
                a.update { s, d, _ in FoodRecipes.weeklyTick(&s, data: d) }
                let la = a.state.company(ida)!.value("lastW"), lb = b.state.company(idb)!.value("lastW")
                profitA += la["rev"].double - la["cogs"].double
                profitB += lb["rev"].double - lb["cogs"].double
            }
            XCTAssertEqual(profitA, profitB, accuracy: max(1, abs(profitB) * 1e-9), "\(t) revenue less cost of sales")
            XCTAssertEqual(a.state.cash, b.state.cash, accuracy: 1, "\(t) cash")
            XCTAssertTrue(Ledger.gaps(a.state).isEmpty, "\(t): \(Ledger.gaps(a.state))")
            print("FOODPROBE \(t) gross margin over 104 weeks: \(Int(profitA)) (same without the withItems: \(Int(profitB))), cash \(Int(a.state.cash))")
        }
    }
}
