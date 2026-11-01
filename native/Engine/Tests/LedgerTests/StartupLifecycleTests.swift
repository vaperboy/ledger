import XCTest
import GameCore
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// Stage 4A: a founded startup is a real company. Builders are hired and paid like staff, the product finishes and waits for a launch decision,
/// price and marketing drive customers, the company can be sold, rounds use the cap table. Multi-seed runs report survival and revenue.
final class StartupLifecycleTests: XCTestCase {
    private func game(seed: Int, funds: Double = 5_000_000_000) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, funds, why: "Test funds") }
        return e
    }
    private func days(_ e: inout GameEngine, _ n: Int) { for _ in 0..<n { for c in e.state.companies { _ = e.approvePayroll(companyID: c.id) }; _ = e.nextDay() } }

    func testFoundedStartupIsARealCompanyWithPaidBuilders() throws {
        var e = try game(seed: 3)
        guard case .ok(let sid) = e.foundStartup(name: "Realco", sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 4) else { return XCTFail("found") }
        let co = try XCTUnwrap(e.state.company(sid))
        XCTAssertEqual(co.type, "startup")
        XCTAssertEqual(co.form, .limited)
        XCTAssertEqual(co.status, .open)
        XCTAssertEqual(co.staff.filter { $0.role == "dev" }.count, 2, "two builders hired through the ordinary hiring")
        XCTAssertGreaterThan(co.cash, 0)
        XCTAssertEqual(CapTable.table(co).total, CapTable.initialShares)
        let cash0 = co.cash
        days(&e, 7 * 6)
        XCTAssertLessThan(try XCTUnwrap(e.state.company(sid)).cash, cash0, "wages and costs are real company costs")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        let f = try XCTUnwrap(e.foundedStartups.first)
        XCTAssertEqual(f.companyID, sid)
        XCTAssertGreaterThan(try XCTUnwrap(f.product).progress, 0)
        // More builders build faster; letting them go slows it.
        let n0 = try XCTUnwrap(e.state.company(sid)).staff.count
        e.changeBuilders(startupID: sid, by: 1)
        XCTAssertEqual(try XCTUnwrap(e.state.company(sid)).staff.count, n0 + 1)
        e.changeBuilders(startupID: sid, by: -1)
        XCTAssertEqual(try XCTUnwrap(e.state.company(sid)).staff.count, n0)
    }

    func testFinishedProductWaitsForALaunchDecisionThenPriceAndMarketingDriveCustomers() throws {
        var e = try game(seed: 8)
        guard case .ok(let sid) = e.foundStartup(name: "Launchco", sector: "saas", product: "crm", model: "sub", who: "c4", seedMultiple: 4) else { return XCTFail("found") }
        var guardWeeks = 0
        while (e.foundedStartups.first?.product?.phase ?? "") != "ready" && guardWeeks < 60 { days(&e, 7); guardWeeks += 1 }
        XCTAssertEqual(e.foundedStartups.first?.product?.phase, "ready", "built in \(guardWeeks) weeks")
        let before = try XCTUnwrap(e.foundedStartups.first)
        days(&e, 14)
        XCTAssertEqual(e.foundedStartups.first?.product?.customers ?? -1, before.product?.customers ?? -2, accuracy: 0.001, "nothing is sold before the launch")
        XCTAssertEqual(e.foundedStartups.first?.product?.revenueWeekly ?? -1, 0, accuracy: 0.001)
        XCTAssertLessThan(try XCTUnwrap(e.foundedStartups.first).cash, before.cash, "wages keep running")
        let ref = before.price
        let cheap = try XCTUnwrap(e.startupLaunchPreview(startupID: sid, price: ref * 0.5))
        let dear = try XCTUnwrap(e.startupLaunchPreview(startupID: sid, price: ref * 5))
        XCTAssertGreaterThan(cheap.newCustomersWeekly, dear.newCustomersWeekly, "price moves demand")
        XCTAssertEqual(e.launchStartup(startupID: sid, price: 0), .badPrice)
        XCTAssertEqual(e.launchStartup(startupID: sid, price: ref, marketingChannel: "google", marketingWeekly: 3000), .ok)
        XCTAssertEqual(e.launchStartup(startupID: sid, price: ref), .notReady, "launch happens once")
        days(&e, 7 * 20)
        let after = try XCTUnwrap(e.foundedStartups.first)
        XCTAssertGreaterThan(after.product?.customers ?? 0, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertTrue(e.setStartupPrice(startupID: sid, price: ref * 1.2))
    }

    func testRoundsUseTheCapTableAndNoRoundTakesControl() throws {
        var e = try game(seed: 12)
        guard case .ok(let sid) = e.foundStartup(name: "Roundco", sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 2) else { return XCTFail("found") }
        days(&e, 7 * 8)
        for _ in 0..<3 {
            _ = e.pitchStartupRound(startupID: sid)
            for _ in 0..<5 { days(&e, 7) }
            if let o = e.foundedStartups.first?.offers.first {
                XCTAssertLessThanOrEqual(o.pct, 40.001, "no single round takes control")
                let terms = try XCTUnwrap(e.fundingOfferTerms(companyID: sid, offerIndex: 0))
                XCTAssertEqual(terms.companyProceeds, o.amount)
                XCTAssertEqual(terms.personalProceeds, 0)
                XCTAssertGreaterThan(terms.sharesIssued, 0)
                XCTAssertTrue(e.acceptStartupRound(startupID: sid, index: 0))
            }
        }
        let co = try XCTUnwrap(e.state.company(sid))
        XCTAssertEqual(co.ownership + co.value("holders").array.reduce(0) { $0 + $1["pct"].double }, 100, accuracy: 1e-6)
    }

    func testTheStartupCanBeSoldLikeAnyCompany() throws {
        var e = try game(seed: 5)
        guard case .ok(let sid) = e.foundStartup(name: "Sellco", sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 4) else { return XCTFail("found") }
        days(&e, 7 * 14)
        XCTAssertTrue(CompanySale.canSell(e.state, companyID: sid))
        let net0 = e.state.cash + e.state.savings
        XCTAssertTrue(e.listCompanyForSale(companyID: sid, broker: false, percent: 100))
        var accepted = false
        for _ in 0..<20 where !accepted {
            days(&e, 7)
            if let o = CompanySale.listing(e.state, companyID: sid)?.offers.first, e.acceptBuyerOffer(companyID: sid, offerID: o.id) != nil { accepted = true }
        }
        if accepted {
            XCTAssertEqual(e.state.company(sid)?.status, .sold)
            XCTAssertGreaterThan(e.state.cash + e.state.savings, net0 - 1)
            days(&e, 14)
            XCTAssertEqual(e.foundedStartups.first?.exited, true)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    /// Multi-seed outcomes of the same founding plan (two builders, 4x seed) under three launch strategies: the reference price with no support staff,
    /// the reference price with a support hire and a campaign, and three times the reference price. How many survive 100 weeks, the revenue
    /// distribution and why the others end. Printed for the report; nothing is clamped.
    func testMultiSeedSurvivalAndRevenue() throws {
        let seeds = ProcessInfo.processInfo.environment["LEDGER_PROBE_ALL"] == "1" ? Array(1...30) : Array(1...4)
        for (label, priceFactor, support, campaign) in [("reference price, no support", 1.0, false, 0.0), ("reference price, support hire + campaign", 1.0, true, 2000.0), ("3x price", 3.0, false, 0.0)] {
            var alive = 0, ended = 0, launched = 0, revenues: [Double] = [], causes: [String: Int] = [:]
            for seed in seeds {
                var e = try game(seed: seed)
                guard case .ok(let sid) = e.foundStartup(name: "S\(seed)", sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 4) else { continue }
                var weeks = 0, didLaunch = false
                while weeks < 100 {
                    days(&e, 7); weeks += 1
                    guard let f = e.foundedStartups.first else { break }
                    if !f.live { break }
                    if f.product?.phase == "ready" && !didLaunch {
                        didLaunch = true
                        _ = e.launchStartup(startupID: sid, price: f.price * priceFactor, marketingChannel: campaign > 0 ? "google" : nil, marketingWeekly: campaign)
                        if support {
                            e.update { s, d, _ in
                                let c = Hiring.search(role: "ittech", company: s.company(sid)!, mode: .network, faces: false, state: &s, data: d)
                                _ = AutoHire.hireWorker(role: "ittech", companyID: sid, candidates: c, state: &s, data: d)
                            }
                        }
                    }
                }
                let f = e.foundedStartups.first
                if f?.live == true { alive += 1 } else { ended += 1; causes[e.state.company(sid)?.status == .bust ? "ran out of cash" : "closed or sold", default: 0] += 1 }
                if f?.product?.phase == "live" { launched += 1; revenues.append(f?.product?.revenueWeekly ?? 0) }
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "seed \(seed)")
            }
            revenues.sort()
            print("STARTUP-SEEDS [\(label)] n=\(seeds.count) alive=\(alive) ended=\(ended) launched=\(launched) weeklyRevenue min/median/max=\(revenues.first ?? 0)/\(revenues.isEmpty ? 0 : revenues[revenues.count / 2])/\(revenues.last ?? 0) causes=\(causes)")
            XCTAssertEqual(alive + ended, seeds.count)
        }
    }
}
