import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Wave 9 (venues with capacity tickets and passes): real items with their own costs, the profit and loss slider, the house edge, the club's ticket level, old
/// saves, and a two-year probe of a competent owner per trade.
final class Wave9Tests: XCTestCase {
    static let all = ["nightclub", "casino", "fun", "skires", "indoorski", "gym", "club"]

    struct Run { var e: GameEngine; var id: Int; var invested: Double }

    static func start(_ trade: String, seed: Int = 11) throws -> Run {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        var id = 0, invested = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
            if trade == "club" {
                let c = data.countries.resolve("UK", orHome: s.homeCountryCode)
                if case .ok(let i) = FootballModel.found(&s, country: c, cityID: nil, data: data) { id = i }
                return
            }
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
        for _ in 0..<40 where r.id != 0 && r.e.state.company(r.id)?.status != .open { week(&r, wave9: false) }
        return r
    }

    static func week(_ r: inout Run, wave9: Bool) {
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
        if wave9 { r.e.update { s, d, _ in for i in s.companies.indices { Wave9.weekly(&s, i, data: d) } } }
    }

    func testRegistryHoldsTheSevenTradesAndNothingElse() {
        XCTAssertEqual(ItemWaves.w9, Set(Self.all))
        XCTAssertTrue(ItemWaves.w9.isDisjoint(with: ItemWaves.w1.union(ItemWaves.w2).union(ItemWaves.w3).union(ItemWaves.w8)))
    }

    func testEveryTradeSellsRealItemsWithEconomics() throws {
        for t in Self.all {
            var r = try Self.start(t)
            guard r.id != 0, r.e.state.company(r.id)?.status == .open else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<8 { Self.week(&r, wave9: true) }
            let co = r.e.state.company(r.id)!, bd = r.e.data.catalog[t]!
            XCTAssertFalse(co.value("w9u").isNull, t)
            let eco = Wave9.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
            XCTAssertGreaterThanOrEqual(eco.count, 5, "\(t) sells too few things")
            let items = SalesItems.items(co, bd)
            XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare }, 1, accuracy: 1e-9, t)
            XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare * $1.ratio }, 1, accuracy: 1e-9, t)
            XCTAssertFalse(items.contains { $0.id.hasPrefix("d") }, "\(t): the title-only defaults are replaced")
            for e in eco where e.weeklyRevenue > 0 {
                let rec = ItemModels.record(co, itemID: e.itemID)
                XCTAssertNotNil(rec, "\(t) \(e.name)")
                XCTAssertGreaterThan(e.costPerSale, 0, "\(t) \(e.name)")
                XCTAssertEqual(rec!.cost, e.costPerSale, accuracy: 1e-6 * max(1, e.costPerSale), "\(t) \(e.name) record cost follows the books")
                XCTAssertEqual(ItemModels.liveProfit(price: e.breakEvenPrice * 1.2, cost: e.costPerSale).outcome, .profit, "\(t) \(e.name)")
                XCTAssertEqual(ItemModels.liveProfit(price: e.breakEvenPrice * 0.8, cost: e.costPerSale).outcome, .loss, "\(t) \(e.name)")
                XCTAssertFalse(rec!.history.isEmpty, "\(t) \(e.name) history")
            }
            XCTAssertTrue(eco.contains { $0.isSub } || t == "nightclub" || t == "casino", "\(t) has a pass or membership")
            XCTAssertTrue(Ledger.gaps(r.e.state).isEmpty, "\(t): \(Ledger.gaps(r.e.state))")
        }
    }

    func testCasinoGamesCarryTheHouseEdge() throws {
        var r = try Self.start("casino")
        guard r.id != 0 else { throw XCTSkip("could not start casino") }
        for _ in 0..<4 { Self.week(&r, wave9: true) }
        let eco = Wave9.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        let slots = eco.first { $0.itemID == "w9:slots" }!, bj = eco.first { $0.itemID == "w9:bj" }!
        XCTAssertGreaterThan(slots.edge, bj.edge)
        XCTAssertEqual(slots.playedPerSale, slots.price / slots.edge, accuracy: 1e-9)
        XCTAssertGreaterThan(bj.playedPerSale, slots.playedPerSale / 5, "a low edge means more played per unit won")
    }

    func testCostOfSalesFactorIsOneAtDefaultAndFollowsThePrice() throws {
        var r = try Self.start("nightclub")
        guard r.id != 0 else { throw XCTSkip("could not start nightclub") }
        for _ in 0..<4 { Self.week(&r, wave9: true) }
        XCTAssertEqual(Wave9.cogsFactor(r.e.state, companyID: r.id, data: r.e.data), 1)
        let market = SalesItems.rows(r.e.state, companyID: r.id, data: r.e.data).first { $0.id == "w9:bar" }!.marketPrice
        r.e.update { s, d, _ in SalesItems.setPrice(&s, companyID: r.id, itemID: "w9:bar", price: market * 1.3, data: d) }
        XCTAssertLessThan(Wave9.cogsFactor(r.e.state, companyID: r.id, data: r.e.data), 1, "a dearer pour costs the bar the same")
        r.e.update { s, d, _ in SalesItems.setPrice(&s, companyID: r.id, itemID: "w9:bar", price: market * 0.7, data: d) }
        XCTAssertGreaterThan(Wave9.cogsFactor(r.e.state, companyID: r.id, data: r.e.data), 1)
    }

    func testClubTicketPriceMovesTheTicketLevelAndItsItemsAreAttributed() throws {
        var r = try Self.start("club")
        guard r.id != 0 else { throw XCTSkip("could not start club") }
        for _ in 0..<30 { Self.week(&r, wave9: true) }
        let co = r.e.state.company(r.id)!
        XCTAssertEqual(Wave9.clubTixShift(co), 0)
        let eco = Wave9.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertEqual(Set(eco.map { $0.itemID }), ["w9:match", "w9:season", "w9:box", "w9:merch", "w9:spons"])
        XCTAssertGreaterThan(eco.first { $0.itemID == "w9:match" }!.weeklyRevenue, 0)
        XCTAssertFalse(co.value("fm").isNull, "the club's own records are kept")
        let market = SalesItems.rows(r.e.state, companyID: r.id, data: r.e.data).first { $0.id == "w9:match" }!.marketPrice
        r.e.update { s, d, _ in SalesItems.setPrice(&s, companyID: r.id, itemID: "w9:match", price: market * 1.2, data: d) }
        XCTAssertGreaterThan(Wave9.clubTixShift(r.e.state.company(r.id)!), 0)
    }

    func testOldSavesAndOtherTradesAreUntouched() throws {
        var r = try Self.start("gym")
        guard r.id != 0 else { throw XCTSkip("could not start gym") }
        for _ in 0..<3 { Self.week(&r, wave9: false) }
        // Once the lead wires `Wave9.weekly` into `WaveHooks.weekly` the engine sets the items up itself, so this checks the reads only: they change nothing.
        let co = r.e.state.company(r.id)!
        let stateBefore = r.e.state
        XCTAssertEqual(Wave9.cogsFactor(r.e.state, companyID: r.id, data: r.e.data), 1)
        XCTAssertEqual(Wave9.clubTixShift(co), 0)
        XCTAssertTrue(r.e.state == stateBefore)
        var other = try Self.start("bakery")
        for _ in 0..<2 { Self.week(&other, wave9: true) }
        XCTAssertTrue(other.e.state.company(other.id)!.value("w9u").isNull)
    }

    func testSecondSyncChangesNothingAndKeepsOwnerPrices() throws {
        var r = try Self.start("skires")
        guard r.id != 0 else { throw XCTSkip("could not start skires") }
        for _ in 0..<3 { Self.week(&r, wave9: true) }
        let market = SalesItems.rows(r.e.state, companyID: r.id, data: r.e.data).first { $0.id == "w9:day" }!.marketPrice
        r.e.update { s, d, _ in SalesItems.setPrice(&s, companyID: r.id, itemID: "w9:day", price: market * 1.2, data: d) }
        r.e.update { s, d, _ in Wave9.sync(&s, companyID: r.id, data: d) }
        let before = r.e.state.company(r.id)!.value("items27")
        r.e.update { s, d, _ in Wave9.sync(&s, companyID: r.id, data: d) }
        XCTAssertEqual(r.e.state.company(r.id)!.value("items27"), before)
        XCTAssertEqual(SalesItems.items(r.e.state.company(r.id)!, r.e.data.catalog["skires"]!).first { $0.id == "w9:day" }!.priceMultiplier, 1.2, accuracy: 1e-9)
    }

    /// Two years of a competent owner per trade, with and without the wave: no trade becomes unprofitable by design. Prints profit per year.
    func testTwoYearProbePerTrade() throws {
        for t in Self.all {
            var base = try Self.start(t), wave = try Self.start(t)
            guard base.id != 0, wave.id != 0 else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<104 { Self.week(&base, wave9: false); Self.week(&wave, wave9: true) }
            func profit(_ r: Run) -> (Double, Double, Double) {
                let h = r.e.state.company(r.id)!.monthlyHistory
                return (h.prefix(12).reduce(0) { $0 + $1.profit }, h.suffix(12).reduce(0) { $0 + $1.profit }, r.e.state.company(r.id)!.cash)
            }
            let b = profit(base), w = profit(wave)
            print(String(format: "W9PROBE %@ | before y1 %.0f y2 %.0f cash %.0f | after y1 %.0f y2 %.0f cash %.0f | invested %.0f", t, b.0 / 1000, b.1 / 1000, b.2 / 1000, w.0 / 1000, w.1 / 1000, w.2 / 1000, wave.invested / 1000))
            XCTAssertEqual(w.1, b.1, accuracy: max(1, abs(b.1) * 0.02), "\(t): the wave must not change what the trade earns at default prices")
            XCTAssertTrue(Ledger.gaps(wave.e.state).isEmpty, "\(t)")
        }
    }
}
