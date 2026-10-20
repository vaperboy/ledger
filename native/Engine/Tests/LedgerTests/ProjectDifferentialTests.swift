import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses

/// The deterministic parts of the project model must give the original's numbers on the same companies.
/// Golden/save_projects.json and Golden/oracle_projects.json come from tools/ref/snippets/projects_oracle.js (the original game,
/// five job trades and a developer, opened and played 40 days).
///
/// Two numbers carry a deliberate native calibration (docs/BALANCE_PARITY.md, "Project businesses"): the hour value is multiplied by
/// the trade's `priceFactor` and the requests by its `demandFactor`; the test divides them out.
final class ProjectDifferentialTests: XCTestCase {
    func world() throws -> World {
        World(state: try Golden.state("save_projects"), countries: try CountryBook.bundled(realCityMarket: false), catalog: try TradeCatalog.bundled(), balance: try Balance.bundled())
    }

    func testHoursModelMatchesOriginal() throws {
        let w = try world()
        let g = try Golden.load("oracle_projects")
        var report: [String] = []
        var checked = 0
        for (idStr, e) in g.object where e["hw41"].double != 0 || e["avgH41"].double != 0 {
            guard let co = w.state.company(Int(idStr)!), let bd = w.trade(co), let spec = ProjectModel.specs[bd.id] else { report.append("missing company \(idStr)"); continue }
            checked += 1
            let dm = DemandModel.compute(co, bd, w), cp = CapacityModel.compute(co, bd, w)
            let tag = e["type"].string
            func close(_ name: String, _ mine: Double, _ theirs: Double, tol: Double = 1e-6) {
                if abs(mine - theirs) > tol * max(1, abs(theirs)) { report.append("\(tag) \(name): swift \(mine) vs original \(theirs)") }
            }
            close("demand", dm.customers, e["D"].double)
            // Capacity: the original's empty-support-role collapse to zero is a documented deliberate difference (CompanyModelDifferentialTests);
            // elsewhere the two agree within a few percent (the native staff model differs slightly in tiredness).
            if e["cap"].double > 0.05 { close("capacity", cp.capacity, e["cap"].double, tol: 0.05) }
            close("ticket multiplier", Pricing.ticketMultiplier(co, bd, w), e["ticketMult"].double)
            close("job scale", Pricing.jobScale(co), e["jobScale"].double)
            close("hour value", ProjectModel.hourValue(co, bd, w) / spec.priceFactor, e["hvl41"].double)
            close("hours a week from the original's capacity", ProjectModel.hoursPerWeek(bd, capacity: e["cap"].double), e["hw41"].double)
            // hours asked for on a Thursday (day 3): the original's log after one day
            let wd = DailyTrade.weekday(week: w.week - 1, day: 3)
            let reqShare: Double = wd < 5 ? 0.18 : wd == 5 ? 0.07 : 0.03
            let Dh = dm.customers * Pricing.jobScale(co) * bd.ticket * Knobs.effect(co, bd, "t", w) * Knobs.effect(co, bd, "tt", w) / spec.hv
            close("hours asked for", Dh * reqShare, e["Dh"].double)
            // average hours of a request depends on the mix, which depends on the hours a week the firm had before the day
            close("average hours", ProjectModel.averageHours(spec, ProjectModel.mix(co, bd)), e["avgH41"].double, tol: 1e-6)
        }
        XCTAssertEqual(checked, 5)
        XCTAssertTrue(report.isEmpty, "\n" + report.joined(separator: "\n"))
    }

    func testDevelopmentQuoteMatchesOriginal() throws {
        let w = try world()
        let g = try Golden.load("oracle_projects")
        let ctx = FinanceContext(countries: w.countries, trades: w.catalog)
        guard let (idStr, e) = g.object.first(where: { $0.value["type"].string == "realdev" }), let co = w.state.company(Int(idStr)!), let bd = w.trade(co) else { return XCTFail("no developer") }
        let home = ctx.homeCurrency(w.state)
        let half = e["starts"].array.first { $0["sz"].double == 0.5 }!
        let q = ProjectDeveloper.quote(co, bd, size: 0.5, financed: false, world: w, homeCurrency: home)
        let p = half["p"]
        XCTAssertEqual(Double(q.units), p["units"].double)
        // The original does not round these (its rounding step is for a country the save does not have in its table): compare within one step.
        XCTAssertEqual(q.land, p["land"].double, accuracy: 1000)
        XCTAssertEqual(q.build, p["build"].double, accuracy: 1000)
        XCTAssertEqual(q.unitPrice, p["price"].double, accuracy: 1000)
        // cash paid now = land + zoning fee (the original's cash change)
        XCTAssertEqual(q.cashNow, -half["cashDelta"].double, accuracy: 1000)
    }
}
