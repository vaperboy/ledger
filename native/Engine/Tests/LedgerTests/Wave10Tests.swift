import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Wave 10 (transport and logistics): services and routes as items, their economics from the books, the price slider, old saves, and a two-year probe per trade.
final class Wave10Tests: XCTestCase {
    static let all = ["taxi", "courier", "trucking", "shipping", "airline", "wh3pl"]

    struct Run { var e: GameEngine; var id: Int; var invested: Double }

    static func start(_ trade: String, seed: Int = 11) throws -> Run {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        var id = 0, invested = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 200_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            invested = (est?.total ?? 1_000_000) * 1.3
            Payments.injectCash(&s, companyID: id, amount: invested)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            if let co = s.company(id), let bd = data.catalog[co.type], (bd.ownerFTE == 0 || bd.standardStaff.reduce(0, { $0 + $1.count }) >= 4), !bd.hasTrait("noStaff"), co.managerID == nil {
                for _ in 0..<6 {
                    let c = ManagerModel.generateCandidate(company: s.company(id), type: bd.managerType, state: &s, data: data)
                    if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.2, data: data) == .ok { break }
                }
            }
        }
        var r = Run(e: e, id: id, invested: invested)
        for _ in 0..<120 where r.e.state.company(id)?.status != .open { week(&r, wave10: false) }
        return r
    }

    static func week(_ r: inout Run, wave10: Bool) {
        for _ in 0..<7 {
            r.e.nextDay()
            for m in r.e.openDecisions where m.actionID.hasPrefix("pay29") { r.e.answer(messageID: m.id, option: 0) }
        }
        let id = r.id
        if let co = r.e.state.company(id), co.status.isLive, co.cash < -50_000 {
            let top = -co.cash + 100_000
            r.e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: top) }
            r.invested += top
        }
        // The hook the lead adds beside `ItemModels.weeklyTick` in `WaveHooks.weekly`, run here by hand.
        if wave10 { r.e.update { s, d, _ in for i in s.companies.indices { Wave10.weekly(&s, i, data: d) } } }
    }

    func testRegistryHoldsTheSixTradesAndNothingElse() {
        XCTAssertEqual(ItemWaves.w10, Set(Self.all))
        XCTAssertTrue(ItemWaves.w10.isDisjoint(with: ItemWaves.w1.union(ItemWaves.w2).union(ItemWaves.w3).union(ItemWaves.w8)))
    }

    func testEveryTradeSellsServicesWithEconomics() throws {
        for t in Self.all {
            var r = try Self.start(t)
            guard r.id != 0 else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<6 { Self.week(&r, wave10: true) }
            let co = r.e.state.company(r.id)!, bd = r.e.data.catalog[t]!
            XCTAssertEqual(co.status, .open, t)
            XCTAssertFalse(co.value("w10u").isNull, t)
            let eco = Wave10.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
            XCTAssertGreaterThanOrEqual(eco.count, 3, "\(t) sells real services as items")
            let items = SalesItems.items(co, bd)
            XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare }, 1, accuracy: 1e-9, t)
            XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare * $1.ratio }, 1, accuracy: 1e-9, t)
            XCTAssertFalse(items.contains { $0.id.hasPrefix("d") }, "\(t): the title-only defaults are replaced")
            for u in eco {
                let rec = ItemModels.record(co, itemID: u.itemID)
                XCTAssertEqual(rec?.model, .svc, "\(t) \(u.name)")
                XCTAssertGreaterThan(u.capacity, 0, "\(t) \(u.name)")
                XCTAssertGreaterThan(u.fixedWeekly, 0, "\(t) \(u.name)")
                XCTAssertGreaterThan(u.costPerPeriod, 0, "\(t) \(u.name)")
                XCTAssertEqual(rec!.cost, u.costPerPeriod, accuracy: 1e-6 * max(1, u.costPerPeriod), "\(t) record cost follows the books")
                XCTAssertEqual(ItemModels.liveProfit(price: u.breakEvenRate * 1.2, cost: u.costPerPeriod).outcome, .profit, "\(t) \(u.name)")
                XCTAssertEqual(ItemModels.liveProfit(price: u.breakEvenRate * 0.8, cost: u.costPerPeriod).outcome, .loss, "\(t) \(u.name)")
                XCTAssertEqual(Wave10.info(r.e.state, companyID: r.id, itemID: u.itemID, data: r.e.data)?.kind, "service")
                XCTAssertFalse(rec!.history.isEmpty, "\(t) \(u.name) history")
            }
            XCTAssertTrue(Ledger.gaps(r.e.state).isEmpty, "\(t): \(Ledger.gaps(r.e.state))")
        }
    }

    func testFleetTradesCarryTheFleetsOwnCosts() throws {
        for t in ["taxi", "trucking", "airline", "shipping"] {
            var r = try Self.start(t)
            guard r.id != 0 else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<3 { Self.week(&r, wave10: true) }
            let eco = Wave10.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
            XCTAssertFalse(eco.isEmpty, t)
            XCTAssertTrue(eco.allSatisfy { $0.fixedParts.contains { $0.label == "Depreciation" || $0.label == "Lease payments" } }, t)
            XCTAssertTrue(eco.allSatisfy { $0.fixedParts.contains { $0.label == "Wages, premises and overheads" } }, t)
        }
    }

    func testOldSavesAndOtherTradesAreUntouched() throws {
        var r = try Self.start("taxi")
        for _ in 0..<3 { Self.week(&r, wave10: false) }
        let co = r.e.state.company(r.id)!
        XCTAssertTrue(co.value("w10u").isNull); XCTAssertTrue(co.value("itemsv2").isNull); XCTAssertTrue(co.value("items27").isNull)
        var other = try Self.start("bakery")
        for _ in 0..<2 { Self.week(&other, wave10: true) }
        XCTAssertTrue(other.e.state.company(other.id)!.value("w10u").isNull)
    }

    func testSecondSyncChangesNothingAndKeepsOwnerPrices() throws {
        var r = try Self.start("courier")
        for _ in 0..<3 { Self.week(&r, wave10: true) }
        let item = Wave10.allEconomics(r.e.state, companyID: r.id, data: r.e.data).first!.itemID
        let market = SalesItems.rows(r.e.state, companyID: r.id, data: r.e.data).first { $0.id == item }!.marketPrice
        r.e.update { s, d, _ in SalesItems.setPrice(&s, companyID: r.id, itemID: item, price: market * 1.2, data: d) }
        r.e.update { s, d, _ in Wave10.sync(&s, companyID: r.id, data: d) }
        let before = r.e.state
        r.e.update { s, d, _ in Wave10.sync(&s, companyID: r.id, data: d) }
        XCTAssertEqual(r.e.state.company(r.id)!.value("items27"), before.company(r.id)!.value("items27"))
        XCTAssertEqual(SalesItems.items(r.e.state.company(r.id)!, r.e.data.catalog["courier"]!).first { $0.id == item }!.priceMultiplier, 1.2, accuracy: 1e-9)
    }

    /// Two years of a competent owner per trade, with and without the wave: no trade becomes unprofitable by design. Prints profit per year.
    func testTwoYearProbePerTrade() throws {
        for t in Self.all {
            var base = try Self.start(t), wave = try Self.start(t)
            guard base.id != 0 else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<104 { Self.week(&base, wave10: false); Self.week(&wave, wave10: true) }
            func profit(_ r: Run) -> (Double, Double, Double) {
                let h = r.e.state.company(r.id)!.monthlyHistory
                return (h.prefix(12).reduce(0) { $0 + $1.profit }, h.suffix(12).reduce(0) { $0 + $1.profit }, r.e.state.company(r.id)!.cash)
            }
            let b = profit(base), w = profit(wave)
            print(String(format: "W10PROBE %@ | before y1 %.0f y2 %.0f cash %.0f | after y1 %.0f y2 %.0f cash %.0f | invested %.0f", t, b.0 / 1000, b.1 / 1000, b.2 / 1000, w.0 / 1000, w.1 / 1000, w.2 / 1000, wave.invested / 1000))
            XCTAssertEqual(w.1, b.1, accuracy: max(1, abs(b.1) * 0.02), "\(t): the wave must not change what the trade earns at default prices")
            XCTAssertTrue(Ledger.gaps(wave.e.state).isEmpty, "\(t)")
        }
    }
}
