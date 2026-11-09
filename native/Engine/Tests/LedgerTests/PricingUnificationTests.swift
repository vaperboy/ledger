import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private extension GameEngine {
    mutating func week() { for _ in 0..<7 { _ = nextDay() } }
}

/// Item demand uses the trade's elasticity with a kink at a reference price that moves with quality and rivals.
final class PricingUnificationTests: XCTestCase {
    func engine() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "bakery", cityID: e.state.player.cityID, fundWith: 20_000_000) else { throw XCTSkip("could not start") }
        for _ in 0..<3 { e.week() }
        return (e, id)
    }

    /// The price ratio that earns most profit per unit of the first item, found on the forecast over a fine grid.
    func bestRatio(_ engine: GameEngine, _ id: Int) -> Double {
        // Capacity is left out here (see the capacity test), so only the demand curve decides.
        var e = engine
        noCap(&e, id)
        let it = e.salesItems(companyID: id)[0]
        var best = (ratio: 1.0, profit: -Double.infinity)
        var r = 0.5
        while r <= 1.5 {
            let f = e.itemForecast(companyID: id, itemID: it.id, price: it.marketPrice * r, discountPercent: 0)
            if f.profitChange > best.profit { best = (r, f.profitChange) }
            r += 0.01
        }
        return best.ratio
    }

    func noCap(_ e: inout GameEngine, _ id: Int) {
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { var lw = s.companies[i].value("lastW"); lw["cap"] = .number(0); s.companies[i].set("lastW", lw) }
        }
    }

    func setQuality(_ e: inout GameEngine, _ id: Int, _ q: Double) {
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].quality = q } }
    }

    func setRivals(_ e: inout GameEngine, _ id: Int, priceFactor: Double) {
        e.update { s, _, _ in
            guard let co = s.company(id) else { return }
            let key = co.type + "|" + co.cityID
            var mk = s.rest["mk"] ?? .object([:])
            var m = mk[key]
            m["riv"] = .array([.object(["id": 9001, "name": "Rae's", "owner": "Rae Rival", "size": 1, "pm16": .number(priceFactor)])])
            mk[key] = m
            s.rest["mk"] = mk
        }
    }

    func testMultiplierIsOneAtMarketForEveryShape() {
        for ref in [0.8, 0.95, 1, 1.1, 1.3] {
            for ela in [0.8, 1.2, 2.2] {
                let sh = SalesItems.DemandShape(elasticity: ela, reference: ref)
                XCTAssertEqual(SalesItems.demandMultiplier(priceRatio: 1, shape: sh), 1)
                XCTAssertLessThan(SalesItems.demandMultiplier(priceRatio: 1.1, shape: sh), 1)
                XCTAssertGreaterThan(SalesItems.demandMultiplier(priceRatio: 0.9, shape: sh), 1)
            }
        }
    }

    func testDemandIsMoreElasticAboveTheReferenceThanBelow() {
        let sh = SalesItems.DemandShape(elasticity: 1.4, reference: 1.1)
        let dearer = 1 - SalesItems.demandMultiplier(priceRatio: 1.1 * 1.1, shape: sh) / SalesItems.demandMultiplier(priceRatio: 1.1, shape: sh)
        let cheaper = SalesItems.demandMultiplier(priceRatio: 1.1 / 1.1, shape: sh) / SalesItems.demandMultiplier(priceRatio: 1.1, shape: sh) - 1
        XCTAssertGreaterThan(dearer, 0)
        XCTAssertGreaterThan(dearer, cheaper, "a 10% step above loses more than the same step below gains")
    }

    func testItemsUseTheTradesElasticity() throws {
        let (e, id) = try engine()
        let co = e.state.company(id)!, w = World(state: e.state, data: e.data)
        let trades = e.data.catalog.trades.values.filter { $0.elasticity >= 0.8 }
        guard let a = trades.first, let b = trades.first(where: { $0.elasticity != a.elasticity }) else { throw XCTSkip("one elasticity only") }
        XCTAssertEqual(SalesItems.shape(co, a, w).elasticity, a.elasticity, accuracy: 1e-12)
        XCTAssertEqual(SalesItems.shape(co, b, w).elasticity, b.elasticity, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(SalesItems.shape(co, e.data.catalog[co.type]!, w).elasticity, 0.8)
    }

    func testBestPriceRisesWithQuality() throws {
        var (e, id) = try engine()
        setQuality(&e, id, 15)
        let low = bestRatio(e, id)
        setQuality(&e, id, 95)
        let high = bestRatio(e, id)
        XCTAssertGreaterThan(high, low + 0.05, "a better company can charge more: \(low) -> \(high)")
    }

    func testBestPriceFollowsRivals() throws {
        var (e, id) = try engine()
        setRivals(&e, id, priceFactor: 0.85)
        let cheapRivals = bestRatio(e, id)
        setRivals(&e, id, priceFactor: 1.25)
        let dearRivals = bestRatio(e, id)
        XCTAssertGreaterThan(dearRivals, cheapRivals + 0.05, "\(cheapRivals) -> \(dearRivals)")
    }

    func testBestPriceIsNotAFixedMultipleOfCost() throws {
        var (e, id) = try engine()
        setQuality(&e, id, 20)
        let a = bestRatio(e, id)
        setQuality(&e, id, 90)
        let b = bestRatio(e, id)
        XCTAssertNotEqual(a, b)
    }

    /// With demand above what the shop can serve, the best price is the lowest that fills capacity, which sits above the kink.
    func testCapacityPushesTheBestPriceUp() {
        let sh = SalesItems.DemandShape(elasticity: 1.4, reference: 1)
        let cost = 0.35, base = 100.0
        func best(cap: Double) -> Double {
            var top = (r: 1.0, p: -Double.infinity), r = 0.5
            while r <= 1.8 {
                let units = min(base * SalesItems.demandMultiplier(priceRatio: r, shape: sh), cap)
                let p = (r - cost) * units
                if p > top.p { top = (r, p) }
                r += 0.01
            }
            return top.r
        }
        XCTAssertGreaterThan(best(cap: 70), best(cap: 1000) + 0.05)
    }

    func testDefaultPriceIsRevenueNeutralWhateverTheReference() throws {
        var (e, id) = try engine()
        let it = e.salesItems(companyID: id)[0]
        for q in [10.0, 50, 95] {
            setQuality(&e, id, q)
            setRivals(&e, id, priceFactor: q < 50 ? 0.85 : 1.2)
            noCap(&e, id)
            let f = e.itemForecast(companyID: id, itemID: it.id, price: it.marketPrice, discountPercent: 0)
            XCTAssertEqual(f.demandChange, 0, accuracy: 1e-12)
            XCTAssertEqual(f.profitChange, 0, accuracy: 1e-6)
            XCTAssertEqual(SalesItems.demandFactor(e.state.company(id)!), 1)
        }
    }
}
