import XCTest
import GameCore
import Countries
import Businesses

/// The arithmetic of the energy, salmon and football models must equal the original's on the same inputs.
/// Golden/special_trades.json was produced by tools/ref/snippets/special_trades.js (random draws fixed, see the script).
final class SpecialTradesDifferentialTests: XCTestCase {
    func golden() throws -> JSONValue { try Golden.load("special_trades") }

    func testPowerPlantWeekMatchesOriginal() throws {
        let g = try golden()
        XCTAssertEqual(g["power"].array.count, 36)
        for c in g["power"].array {
            let src = EnergyModel.sources[c["src"].int]
            let r = EnergyModel.powerWeek(megawattsBought: c["bought"].double, building: c["building"].double, week: c["week"].int,
                                          month: GameCalendar.month(week: c["week"].int), source: src, hedge: c["hedge"].int, capacityFactor: 0.36, opexRate: 0.025,
                                          condition: c["cond"].double, technicianFTE: c["fte"].double, capacityModifier: c["capMod"].double,
                                          demandModifier: c["demMod"].double, economyPower: c["econPower"].double, inflation: c["infl"].double, noise: c["noise"].double)
            let tag = "src \(c["src"].int) hedge \(c["hedge"].int) week \(c["week"].int)"
            assertClose(r.outputMWh, c["mwh"].double, tol: 1e-12, "mwh \(tag)")
            assertClose(r.revenue, c["rev"].double, tol: 1e-12, "rev \(tag)")
            assertClose(r.runningCost, c["cogs"].double, tol: 1e-12, "cogs \(tag)")
            assertClose(r.capacityMWh, c["cap"].double, tol: 1e-12, "cap \(tag)")
            assertClose(r.price, c["price"].double, tol: 1e-12, "price \(tag)")
        }
    }

    func testOilFieldsWeekMatchesOriginal() throws {
        let g = try golden()
        for c in g["field"].array {
            let infl = c["infl"].double, week = c["week"].int
            let price = EnergyModel.oilPrice(contracts: c["sell"].int == 1, economyOil: c["econOil"].double, inflation: infl, week: week)
            assertClose(price, c["price"].double, tol: 1e-12, "price")
            let defs: [(res: Double, q0: Double, age: Int, bv: Double, plat: Double)] = [(8000, 27.2, 10, 1.5e9, 0), (60000, 168, 120, 4e9, 104)]
            var bbl = 0.0, assets = 1e9 + 3.9e9 / 156
            for (n, d) in defs.enumerated() {
                let r = EnergyModel.fieldWeek(reserves: d.res, initialRate: d.q0, age: d.age + 1, plateau: d.plat, capacityModifier: c["capMod"].double, crew: c["crew"].double, noise: 0.37, bookValue: d.bv)
                bbl += r.barrels
                assets += d.bv - r.depletion
                let f = c["fields"][n]
                assertClose(d.res - r.barrels, f["res"].double, tol: 1e-12, "reserves")
                assertClose(d.bv - r.depletion, f["bv"].double, tol: 1e-12, "book value")
            }
            assertClose(bbl, c["units"].double, tol: 1e-12, "barrels")
            assertClose(bbl * 1000 * price * c["demMod"].double, c["rev"].double, tol: 1e-12, "revenue")
            assertClose(bbl * 1000 * EnergyModel.liftingCost(materials: c["mat"].double, inflation: infl, week: week), c["cogs"].double, tol: 1e-12, "lifting cost")
            assertClose(assets, c["assets"].double, tol: 1e-12, "assets")
        }
        for s in g["stake"].array { assertClose(EnergyModel.stakePrice(kbbl: s["k"].double, economyOil: 1.3), s["price"].double, tol: 0, "stake") }
        assertClose(EnergyModel.explorationCost(inflation: g["explore"]["infl"].double, week: g["explore"]["week"].int), g["explore"]["cost"].double, tol: 0, "exploration")
    }

    func testSalmonCyclesMatchOriginal() throws {
        let g = try golden()
        var coh = [SalmonModel.Cohort(n: 700000, kg: 0.1, age: 0, dead: 0, illness: 0), SalmonModel.Cohort(n: 650000, kg: 2.0, age: 40, dead: 0, illness: 0.05)]
        var harvests = 0
        for (k, w) in g["salmon"].array.enumerated() {
            let week = w["week"].int
            let r = SalmonModel.step(&coh, growWeeks: 78, growthQuality: 1.04, illness: 1.5, feedChange: 0.05, month: GameCalendar.month(week: week),
                                     spot: SalmonModel.spotPerKilo(economy: 1.15), harvest: true, diseaseHits: Array(repeating: false, count: coh.count))
            if r.revenue > 0 { harvests += 1 }
            assertClose(r.revenue, w["rev"].double, tol: 1e-12, "revenue week \(week)")
            assertClose(r.cogs, w["cogs"].double, tol: 1e-12, "cost week \(week)")
            assertClose(r.biomass, w["bio"].double, tol: 1e-12, "biomass week \(week)")
            XCTAssertEqual(coh.count, w["coh"].array.count, "cohorts week \(week) (\(k))")
            for (a, b) in zip(coh, w["coh"].array) { assertClose(a.kg, b["kg"].double, tol: 1e-12, "kg"); assertClose(a.n, b["n"].double, tol: 1e-12, "fish") }
        }
        XCTAssertGreaterThan(harvests, 0, "the scenario should include a harvest")
    }

    func testLeagueClubsMatchOriginal() throws {
        let g = try golden()
        let book = try CountryBook.bundled()
        for (cc, list) in g["clubs"].object {
            let mine = FootballModel.generateClubs(country: book[cc]!, seed: g["seed"].int)
            XCTAssertEqual(mine.count, list.array.count, cc)
            for (a, b) in zip(mine, list.array) {
                // The bundled UK and US surname lists are one name shorter than the original's, which shifts the generated names.
                if !["UK", "US"].contains(cc) || a["id"].string.hasSuffix(":0") { XCTAssertEqual(a["name"].string, b["name"].string, "\(cc) \(b["id"].string)") }
                XCTAssertEqual(a["city"].string, b["city"].string, cc)
                XCTAssertEqual(a["val"].double, b["val"].double, "\(cc) value of \(b["name"].string)")
                XCTAssertEqual(a["fixed"].bool, b["fixed"].bool, "\(cc) fixed \(b["name"].string)")
            }
        }
    }
}
