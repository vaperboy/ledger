import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Wave 8 (RENT trades): units as items, their economics from the books, the rate slider, old saves, and a two-year probe of a competent owner per trade.
final class Wave8Tests: XCTestCase {
    static let all = ["resrent", "comrent", "parking", "carrental", "hotel", "pcbang"]

    struct Run { var e: GameEngine; var id: Int; var invested: Double }

    /// A started company with the standard set-up; a rental company also buys the best of its four listings with a 60% mortgage.
    static func start(_ trade: String, seed: Int = 11) throws -> Run {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        var id = 0, invested = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
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
        // Paperwork takes a few weeks: the company is played (no wave) until it opens.
        for _ in 0..<40 where r.e.state.company(id)?.status != .open { week(&r, wave8: false) }
        // A rental company that set up without a building buys the best of its four listings with a 60% mortgage.
        let rid = r.id
        r.e.update { s, data, _ in
            if let co = s.company(rid), let bd = data.catalog[co.type], bd.family == "rent", co.properties.isEmpty,
               let l = RentalModel.listings(co, bd, World(state: s, data: data)).sorted(by: { $0.grossYield > $1.grossYield }).first {
                Payments.injectCash(&s, companyID: rid, amount: l.price * 0.5)
                _ = RentalModel.buy(&s, companyID: rid, listing: l, loanToValue: 0.6, data: data)
            }
        }
        return r
    }

    static func week(_ r: inout Run, wave8: Bool) {
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
        // The hook the lead adds beside `ItemModels.weeklyTick` in `PriceMoves.weekly`, run here by hand.
        if wave8 { r.e.update { s, d, _ in for i in s.companies.indices { Wave8.weekly(&s, i, data: d) } } }
    }

    func testRegistryHoldsTheSixTradesAndNothingElse() {
        XCTAssertEqual(ItemWaves.w8, Set(Self.all))
        XCTAssertTrue(ItemWaves.w8.isDisjoint(with: ItemWaves.w1.union(ItemWaves.w2).union(ItemWaves.w3)))
    }

    func testEveryTradeHasUnitsAsItemsWithEconomics() throws {
        for t in Self.all {
            var r = try Self.start(t)
            guard r.id != 0 else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<6 { Self.week(&r, wave8: true) }
            let co = r.e.state.company(r.id)!
            XCTAssertFalse(co.value("w8u").isNull, t)
            let eco = Wave8.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
            XCTAssertFalse(eco.isEmpty, "\(t) has no rentable units as items")
            for u in eco {
                let rec = ItemModels.record(co, itemID: u.itemID)
                XCTAssertEqual(rec?.model, .rent, "\(t) \(u.name)")
                XCTAssertGreaterThan(u.units, 0, "\(t) \(u.name)")
                XCTAssertGreaterThan(u.capacity, 0, "\(t) \(u.name)")
                XCTAssertGreaterThan(u.fixedWeekly, 0, "\(t) \(u.name)")
                XCTAssertGreaterThan(u.costPerPeriod, 0, "\(t) \(u.name)")
                XCTAssertEqual(rec!.cost, u.costPerPeriod, accuracy: 1e-6 * max(1, u.costPerPeriod), "\(t) record cost follows the books")
                // The live slider: a rate above the break-even rate is a profit, below it a loss, and the break-even rate has no profit or loss.
                XCTAssertEqual(ItemModels.liveProfit(price: u.breakEvenRate * 1.2, cost: u.costPerPeriod).outcome, .profit, "\(t) \(u.name)")
                XCTAssertEqual(ItemModels.liveProfit(price: u.breakEvenRate * 0.8, cost: u.costPerPeriod).outcome, .loss, "\(t) \(u.name)")
                XCTAssertFalse(rec!.history.isEmpty, "\(t) \(u.name) occupancy history")
            }
            XCTAssertTrue(Ledger.gaps(r.e.state).isEmpty, "\(t): \(Ledger.gaps(r.e.state))")
        }
    }

    func testHotelRoomTypesAddUpToTheRoomsAndKeepRevenueWeightsAtOne() throws {
        var r = try Self.start("hotel")
        for _ in 0..<3 { Self.week(&r, wave8: true) }
        let co = r.e.state.company(r.id)!, bd = r.e.data.catalog["hotel"]!
        let types = Wave8.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertEqual(types.count, 4)
        let rooms = co.value("eq")["rooms"]["n"].double + co.value("lease")["rooms"].double
        XCTAssertEqual(types.reduce(0.0) { $0 + $1.units }, rooms, accuracy: 1e-9)
        let items = SalesItems.items(co, bd)
        XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare }, 1, accuracy: 1e-9)
        XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare * $1.ratio }, 1, accuracy: 1e-9)
        XCTAssertTrue(items.contains { $0.name == "Breakfast add-on" })
        XCTAssertFalse(items.contains { $0.id.hasPrefix("d") }, "the title-only defaults are replaced")
    }

    func testRentalCarsAreOneItemEachWithTheirOwnDepreciationAndFinance() throws {
        var r = try Self.start("carrental")
        for _ in 0..<3 { Self.week(&r, wave8: true) }
        let co = r.e.state.company(r.id)!
        let cars = Wave8.allEconomics(r.e.state, companyID: r.id, data: r.e.data).filter { $0.itemID.hasPrefix("w8u:v") }
        XCTAssertEqual(cars.count, co.value("veh").array.count)
        XCTAssertTrue(cars.allSatisfy { $0.fixedParts.contains { $0.label == "Depreciation" && $0.weekly > 0 } })
        XCTAssertTrue(cars.allSatisfy { $0.per == "day" && $0.capacity == 7 })
    }

    func testBuildingItemRateMovesRentAndVacancy() throws {
        var a = try Self.start("resrent"), b = try Self.start("resrent")
        for _ in 0..<2 { Self.week(&a, wave8: true); Self.week(&b, wave8: true) }
        let pid = a.e.state.company(a.id)!.properties.first!.id
        let item = "w8u:p\(pid)"
        let market = SalesItems.rows(a.e.state, companyID: a.id, data: a.e.data).first { $0.id == item }!.marketPrice
        b.e.update { s, d, _ in SalesItems.setPrice(&s, companyID: b.id, itemID: item, price: market * 1.4, data: d) }
        XCTAssertEqual(Wave8.rateMultiplier(b.e.state.company(b.id)!, b.e.data.catalog["resrent"]!, propertyID: pid), 1.4, accuracy: 1e-9)
        for _ in 0..<26 { Self.week(&a, wave8: true); Self.week(&b, wave8: true) }
        let va = a.e.state.company(a.id)!.properties.first!.vacancy, vb = b.e.state.company(b.id)!.properties.first!.vacancy
        XCTAssertGreaterThan(vb, va, "a dearer rate fills fewer flats")
        let ea = Wave8.economics(a.e.state, companyID: a.id, itemID: item, data: a.e.data)!, eb = Wave8.economics(b.e.state, companyID: b.id, itemID: item, data: b.e.data)!
        XCTAssertEqual(eb.rate / ea.rate, 1.4, accuracy: 0.05, "the rate shown is the rent charged")
        XCTAssertLessThan(eb.occupancy, ea.occupancy)
    }

    func testOldSavesAndOtherTradesAreUntouched() throws {
        var r = try Self.start("hotel")
        for _ in 0..<3 { Self.week(&r, wave8: false) }   // the weekly hook runs inside the company week (WaveHooks)
        let co = r.e.state.company(r.id)!
        XCTAssertEqual(Wave8.rateMultiplier(co, r.e.data.catalog["hotel"]!, propertyID: 1), 1, "at the default rate nothing changes")
        var other = try Self.start("bakery")
        for _ in 0..<2 { Self.week(&other, wave8: true) }
        XCTAssertTrue(other.e.state.company(other.id)!.value("w8u").isNull)
    }

    func testSecondSyncChangesNothingAndKeepsOwnerPrices() throws {
        var r = try Self.start("pcbang")
        for _ in 0..<3 { Self.week(&r, wave8: true) }
        let item = Wave8.allEconomics(r.e.state, companyID: r.id, data: r.e.data).first!.itemID
        let market = SalesItems.rows(r.e.state, companyID: r.id, data: r.e.data).first { $0.id == item }!.marketPrice
        r.e.update { s, d, _ in SalesItems.setPrice(&s, companyID: r.id, itemID: item, price: market * 1.2, data: d) }
        var before = r.e.state
        r.e.update { s, d, _ in Wave8.sync(&s, companyID: r.id, data: d) }
        before = r.e.state
        r.e.update { s, d, _ in Wave8.sync(&s, companyID: r.id, data: d) }
        XCTAssertEqual(r.e.state.company(r.id)!.value("items27"), before.company(r.id)!.value("items27"))
        XCTAssertEqual(SalesItems.items(r.e.state.company(r.id)!, r.e.data.catalog["pcbang"]!).first { $0.id == item }!.priceMultiplier, 1.2, accuracy: 1e-9)
    }

    /// Two years of a competent owner per trade, with and without the wave: no trade becomes unprofitable by design. Prints profit per year.
    func testTwoYearProbePerTrade() throws {
        for t in Self.all {
            var base = try Self.start(t), wave = try Self.start(t)
            guard base.id != 0 else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<104 { Self.week(&base, wave8: false); Self.week(&wave, wave8: true) }
            func profit(_ r: Run) -> (Double, Double, Double) {
                let h = r.e.state.company(r.id)!.monthlyHistory
                return (h.prefix(12).reduce(0) { $0 + $1.profit }, h.suffix(12).reduce(0) { $0 + $1.profit }, r.e.state.company(r.id)!.cash)
            }
            let b = profit(base), w = profit(wave)
            print(String(format: "W8PROBE %@ | before y1 %.0f y2 %.0f cash %.0f | after y1 %.0f y2 %.0f cash %.0f | invested %.0f", t, b.0 / 1000, b.1 / 1000, b.2 / 1000, w.0 / 1000, w.1 / 1000, w.2 / 1000, wave.invested / 1000))
            XCTAssertEqual(w.1, b.1, accuracy: max(1, abs(b.1) * 0.02), "\(t): the wave must not change what the trade earns at default rates")
            XCTAssertTrue(Ledger.gaps(wave.e.state).isEmpty, "\(t)")
        }
    }
}
