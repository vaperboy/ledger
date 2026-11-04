import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private extension GameEngine {
    mutating func w4week() { for _ in 0..<7 { _ = nextDay() } }
}

/// Wave 4: salmon, furniture, factory, start-up, game studio, software and web agency (MADE industrial/digital and SUB).
final class Wave4Tests: XCTestCase {
    let trades = ["salmon", "furniture", "factory", "startup", "gamestudio", "webdev"]

    func start(_ trade: String, weeks: Int = 2, seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.3)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        guard id != 0 else { throw XCTSkip("could not start \(trade)") }
        for _ in 0..<weeks { e.w4week() }
        return (e, id)
    }

    func item(_ e: GameEngine, _ id: Int, _ name: String) throws -> SalesItems.Item {
        let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog[co.type])
        return try XCTUnwrap(SalesItems.items(co, bd).first { $0.name == name }, name)
    }

    func facts(_ e: GameEngine, _ id: Int, _ name: String) throws -> Wave4.Facts {
        let it = try item(e, id, name)
        return try XCTUnwrap(Wave4.facts(e.state, companyID: id, itemID: it.id, data: e.data), name)
    }

    func testRegistryHoldsExactlyTheSixTrades() {
        XCTAssertEqual(ItemWaves.w4, Set(trades))
        XCTAssertEqual(Set(Wave4.tradeIDs), Set(trades))
    }

    func testSpecsAreConsistent() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        for t in trades {
            let ts = try XCTUnwrap(Wave4.tradeSpec(t), t)
            let bd = try XCTUnwrap(e.data.catalog[t], t)
            let m = Wave4.mix(ts.items)
            XCTAssertEqual(m.q.reduce(0, +), 1, accuracy: 1e-9, t)
            XCTAssertEqual(zip(m.q, m.ratio).reduce(0.0) { $0 + $1.0 * $1.1 }, 1, accuracy: 1e-9, "\(t): revenue weights add up to 1")
            let names = (ts.items + ts.extra).map { $0.name.lowercased() }
            XCTAssertEqual(Set(names).count, names.count, "\(t): names are unique across menu and catalogue")
            XCTAssertLessThanOrEqual(ts.items.count, SalesItems.maxItems)
            XCTAssertGreaterThanOrEqual(ts.items.count, 7, "\(t): a real menu")
            let k = Wave4.calibration(ts, cogs: bd.costOfSales)
            print("W4 \(t): cost calibration \(String(format: "%.2f", k)) (1 = data already matched the books)")
            XCTAssertGreaterThan(k, 0.3, t); XCTAssertLessThan(k, 3.0, t)
            for s in ts.items + ts.extra {
                XCTAssertLessThan(Wave4.costShare(s, calibration: k), 0.9, "\(t) \(s.name): the price covers the cost by design")
                if s.model == .sub { XCTAssertGreaterThan(s.churn, 0, s.name); XCTAssertGreaterThan(s.period, 0, s.name) }
                if s.isDigital { XCTAssertGreaterThan(s.halfLife, 0, s.name) }
                if s.model == .proj && !s.isDigital && t != "furniture" && t != "factory" { XCTAssertGreaterThan(s.hours, 0, s.name) }
                if s.model == .made && !s.isDigital && t != "salmon" { XCTAssertGreaterThan(s.minutes, 0, s.name); XCTAssertGreaterThan(s.lead, 0, s.name) }
            }
        }
    }

    func testInstallGivesTheRealMenuAndKeepsTheBooksNeutral() throws {
        for t in trades {
            var (e, id) = try start(t)
            let before = e.salesItems(companyID: id)
            var made = 0
            e.update { s, d, _ in made = Wave4.install(&s, companyID: id, data: d) }
            let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog[t]), ts = try XCTUnwrap(Wave4.tradeSpec(t))
            let list = SalesItems.items(co, bd)
            XCTAssertEqual(list.map { $0.name }, ts.items.map { $0.name }, t)
            XCTAssertEqual(made, ts.items.count, t)
            XCTAssertNotEqual(before.map { $0.name }, list.map { $0.name }, "\(t): titles replaced by real items")
            XCTAssertEqual(SalesItems.demandFactor(co), 1, accuracy: 1e-12, t)
            XCTAssertEqual(SalesItems.ticketFactor(co), 1, accuracy: 1e-12, t)
            XCTAssertEqual(list.reduce(0.0) { $0 + $1.unitShare * $1.ratio }, 1, accuracy: 1e-9, t)
            let mt = SalesItems.marketTicket(co, bd, World(state: e.state, data: e.data))
            var weighted = 0.0
            for it in list {
                let r = try XCTUnwrap(ItemModels.record(co, itemID: it.id), "\(t) \(it.name) has a record")
                XCTAssertGreaterThanOrEqual(r.cost, 0, it.name)
                weighted += it.unitShare * r.cost
                XCTAssertLessThan(r.cost, mt * it.ratio, "\(t) \(it.name): costs less than it sells for")
            }
            if bd.costOfSales > 0 { XCTAssertEqual(weighted, mt * bd.costOfSales, accuracy: mt * 1e-9, "\(t): menu cost equals the books") }
            var again = -1
            e.update { s, d, _ in again = Wave4.install(&s, companyID: id, data: d) }
            XCTAssertEqual(again, 0, "\(t): idempotent")
        }
    }

    func testRecordsAreTheRightModel() throws {
        var (f, fid) = try start("furniture")
        f.update { s, d, _ in Wave4.install(&s, companyID: fid, data: d) }
        func rec(_ e: GameEngine, _ id: Int, _ name: String) throws -> ItemModels.Record {
            try XCTUnwrap(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: try item(e, id, name).id), name)
        }
        let chair = try rec(f, fid, "Dining chair"), table = try rec(f, fid, "Solid oak dining table")
        XCTAssertEqual(chair.model, .made)
        XCTAssertGreaterThan(chair.stock, 0, "made for stock")
        XCTAssertEqual(chair.leadDays, 10)
        XCTAssertEqual(table.model, .proj, "made to order")
        XCTAssertEqual(table.stock, 0)
        XCTAssertEqual(table.leadDays, 28)
        var (w, wid) = try start("webdev")
        w.update { s, d, _ in Wave4.install(&s, companyID: wid, data: d) }
        XCTAssertEqual(try rec(w, wid, "Maintenance plan").model, .sub)
        XCTAssertEqual(try rec(w, wid, "Company website build").model, .proj)
        var (g, gid) = try start("gamestudio")
        g.update { s, d, _ in Wave4.install(&s, companyID: gid, data: d) }
        XCTAssertEqual(try rec(g, gid, "Premium PC and console game").model, .proj, "a title is a development project, not a stock line")
        XCTAssertEqual(try rec(g, gid, "Live-service club").model, .sub)
    }

    func testTouchedListIsKeptAndOnlyGetsRecords() throws {
        var (e, id) = try start("furniture")
        let first = try XCTUnwrap(e.salesItems(companyID: id).first)
        e.update { s, d, _ in SalesItems.setPrice(&s, companyID: id, itemID: first.id, price: first.price * 1.1, data: d) }
        let names = e.salesItems(companyID: id).map { $0.name }
        var made = 0
        e.update { s, d, _ in made = Wave4.install(&s, companyID: id, data: d) }
        XCTAssertEqual(e.salesItems(companyID: id).map { $0.name }, names)
        XCTAssertEqual(made, names.count)
    }

    func testNothingHappensForATradeThatIsNotOptedIn() throws {
        var (e, id) = try start("furniture")
        let before = e.state
        var made = -1
        e.update { s, d, _ in made = Wave4.install(&s, companyID: id, data: d, trades: []) }
        XCTAssertEqual(made, 0)
        XCTAssertTrue(e.state == before)
    }

    func testFurnitureCostBreakdownAddsUp() throws {
        var (e, id) = try start("furniture", weeks: 6)
        e.update { s, d, _ in Wave4.install(&s, companyID: id, data: d) }
        let table = try facts(e, id, "Solid oak dining table"), chair = try facts(e, id, "Dining chair")
        XCTAssertEqual(table.kind, .order)
        XCTAssertEqual(chair.kind, .stock)
        XCTAssertEqual(table.labourMinutes, 900)
        for f in [table, chair] {
            XCTAssertEqual(f.lines.reduce(0.0) { $0 + $1.amount } + f.scrapCost, f.unitCost, accuracy: f.unitCost * 1e-9, f.name)
            XCTAssertGreaterThan(f.scrap, 0)
        }
        XCTAssertEqual(table.lines.map { $0.name }.first, "Oak boards")
        XCTAssertGreaterThan(table.price, table.unitCost)
        let fit = try facts(e, id, "Hotel and office fit-out")
        XCTAssertEqual(fit.minQty, 20)
        XCTAssertEqual(fit.retention, 0.05, accuracy: 1e-12)
    }

    func testFactoryLotsTermsAndContract() throws {
        var (e, id) = try start("factory", weeks: 4)
        e.update { s, d, _ in Wave4.install(&s, companyID: id, data: d) }
        let bd = try XCTUnwrap(e.data.catalog["factory"])
        let part = try facts(e, id, "Custom machined part"), proto = try facts(e, id, "Prototype run")
        XCTAssertEqual(part.paymentTermsWeeks, bd.paymentTermsWeeks)
        XCTAssertEqual(part.batch, 250)
        XCTAssertGreaterThan(proto.scrap, part.scrap, "a prototype run scraps more")
        let contract = try facts(e, id, "Annual supply contract")
        XCTAssertEqual(contract.kind, .subscription)
        XCTAssertTrue(contract.isContract)
        XCTAssertEqual(contract.minQty, 3)
    }

    func testWebAgencyBidAndMaintenanceSubscription() throws {
        var (e, id) = try start("webdev", weeks: 6)
        e.update { s, d, _ in Wave4.install(&s, companyID: id, data: d) }
        let site = try facts(e, id, "Company website build")
        XCTAssertEqual(site.kind, .project)
        XCTAssertEqual(site.hours, 80)
        XCTAssertEqual(site.bid, 80 * site.price, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(site.marginIfOverrun, site.marginAtBid, "overrun eats the margin")
        let maint = try facts(e, id, "Maintenance plan")
        XCTAssertEqual(maint.kind, .subscription)
        XCTAssertEqual(maint.mrr, maint.subscribers * maint.price * 52.0 / 12 / 4, accuracy: 1e-6)
        XCTAssertEqual(maint.leavingPerPeriod, maint.subscribers * 0.02, accuracy: 1e-9)
        XCTAssertGreaterThan(maint.lifetimeValue, 0)
        let hosting = try facts(e, id, "Hosting and care")
        XCTAssertGreaterThan(hosting.unitCost / hosting.price, maint.unitCost / maint.price, "hosting carries the servers")
    }

    func testGameTitleHasDevelopmentCostAndSalesCurve() throws {
        var (e, id) = try start("gamestudio", weeks: 6)
        e.update { s, d, _ in Wave4.install(&s, companyID: id, data: d) }
        let game = try facts(e, id, "Premium PC and console game"), dlc = try facts(e, id, "Downloadable content")
        XCTAssertEqual(game.kind, .title)
        XCTAssertEqual(game.devHours, 9000)
        XCTAssertEqual(game.halfLifeWeeks, 14)
        XCTAssertGreaterThan(game.devHours, dlc.devHours)
        XCTAssertEqual(game.unitLabel, "100 copies")
        XCTAssertEqual(game.remainingProfit, game.weeklyUnits * (game.price - game.unitCost) * 14 / log(2), accuracy: 1e-6)
        let club = try facts(e, id, "Live-service club")
        XCTAssertEqual(club.kind, .subscription)
    }

    func testSalmonProductsFollowTheCohorts() throws {
        var (e, id) = try start("salmon", weeks: 1)
        e.update { s, d, _ in
            Wave4.install(&s, companyID: id, data: d)
            let i = s.companyIndex(id)!
            var fm = s.companies[i].value("fm")
            fm["coh"] = .array([.object(["n": .number(100_000), "kg": .number(3.0), "age": .number(50), "dead": .number(0), "illx": .number(0), "cost": .number(0)])])
            s.companies[i].set("fm", fm)
        }
        let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog["salmon"])
        XCTAssertEqual(Wave4.harvestTonnesPerWeek(co, bd), 100_000 * 5.1 * 0.88 / 1000 / (bd.trait("grow") ?? 78), accuracy: 1e-9)
        let whole = try facts(e, id, "Whole fresh salmon"), fillet = try facts(e, id, "Fresh fillets"), smoked = try facts(e, id, "Smoked salmon")
        XCTAssertEqual(whole.kind, .fish)
        XCTAssertEqual(whole.fishInWater, 100_000)
        XCTAssertEqual(whole.averageKilos, 3.0, accuracy: 1e-9)
        XCTAssertEqual(whole.weeksToHarvest ?? -1, (bd.trait("grow") ?? 78) - 50, accuracy: 1e-9)
        XCTAssertEqual(fillet.yieldRatio, 0.55)
        XCTAssertGreaterThan(whole.weeklyUnits, 0)
        XCTAssertGreaterThan(fillet.unitCost / fillet.price, 0.3)
        XCTAssertGreaterThan(smoked.price, fillet.price)
        XCTAssertLessThan(smoked.unitCost, smoked.price, "a smoked side is sold above its cost")
    }

    func testStartupPlansAreSubscriptions() throws {
        var (e, id) = try start("startup", weeks: 3)
        e.update { s, d, _ in Wave4.install(&s, companyID: id, data: d) }
        let pro = try facts(e, id, "Pro plan"), team = try facts(e, id, "Team plan, 10 seats"), ent = try facts(e, id, "Enterprise licence, annual")
        XCTAssertEqual(pro.kind, .subscription)
        XCTAssertEqual(ent.periodWeeks, 52)
        XCTAssertGreaterThan(team.price, pro.price)
        XCTAssertLessThan(team.churnPerPeriod, pro.churnPerPeriod, "bigger accounts leave less")
        let support = try facts(e, id, "Premium support plan")
        XCTAssertGreaterThan(support.unitCost / support.price, pro.unitCost / pro.price, "support is mostly people")
    }

    func testMadeForStockRunsInBatchesWithALeadTime() throws {
        var (e, id) = try start("furniture", weeks: 6)
        e.update { s, d, _ in Wave4.install(&s, companyID: id, data: d) }
        let chair = try item(e, id, "Dining chair")
        var sawOrder = false, sawArrival = false
        var last: Int?
        for _ in 0..<20 {
            e.w4week()
            e.update { s, d, _ in if let i = s.companyIndex(id) { Wave4.weekly(&s, i, data: d) } }
            let r = try XCTUnwrap(ItemModels.record(try XCTUnwrap(e.state.company(id)), itemID: chair.id))
            XCTAssertGreaterThanOrEqual(r.stock, 0); XCTAssertGreaterThanOrEqual(r.onOrder, 0)
            XCTAssertEqual(r.onOrder % 8, 0, "whole batches of 8")
            if r.onOrder > 0 { sawOrder = true }
            if let l = last, r.stock > l { sawArrival = true }
            last = r.stock
        }
        XCTAssertTrue(sawOrder, "a batch is started when cover runs short")
        XCTAssertTrue(sawArrival, "and it arrives after the lead time")
    }

    func testSaveRoundTripOfTheRecords() throws {
        for t in trades {
            var (e, id) = try start(t)
            e.update { s, d, _ in Wave4.install(&s, companyID: id, data: d) }
            let co = try XCTUnwrap(e.state.company(id))
            XCTAssertFalse(ItemModels.records(co).isEmpty, t)
            let json = try JSONEncoder().encode(co.value("itemsv2"))
            let back = try JSONDecoder().decode(JSONValue.self, from: json)
            XCTAssertTrue(back == co.value("itemsv2"), t)
        }
    }

    // MARK: Two-year survival probe (LEDGER_WAVE4=1; slow)

    struct Result { var y1: Double; var y2: Double; var status: String }

    static func play(_ trade: String, wave: Bool, seed: Int, years: Int = 2) throws -> Result? {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.3)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            if let co = s.company(id), let bd = data.catalog[co.type], (bd.ownerFTE == 0 || bd.standardStaff.reduce(0, { $0 + $1.count }) >= 4), co.managerID == nil {
                for _ in 0..<6 {
                    let c = ManagerModel.generateCandidate(company: s.company(id), type: bd.managerType, state: &s, data: data)
                    if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.2, data: data) == .ok { break }
                }
            }
        }
        guard id != 0 else { return nil }
        for day in 0..<(years * 52 * 7) {
            BalanceProbeTests.drained {
                e.nextDay()
                for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                if wave && day % 7 == 6 { e.update { s, d, _ in if let i = s.companyIndex(id) { Wave4.weekly(&s, i, data: d) } } }
            }
        }
        guard let co = e.state.company(id) else { return nil }
        let h = co.monthlyHistory
        return Result(y1: h.prefix(12).reduce(0) { $0 + $1.profit }, y2: h.dropFirst(12).prefix(12).reduce(0) { $0 + $1.profit }, status: co.status.rawValue)
    }

    func testTwoYearProbeBeforeAndAfter() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_WAVE4"] != nil else { return }
        for t in trades {
            let before = try XCTUnwrap(Self.play(t, wave: false, seed: 11)), after = try XCTUnwrap(Self.play(t, wave: true, seed: 11))
            print(String(format: "W4 PROBE %@ | before y1 %.0f y2 %.0f %@ | after y1 %.0f y2 %.0f %@", t, before.y1, before.y2, before.status, after.y1, after.y2, after.status))
            XCTAssertEqual(after.status, before.status, t)
            XCTAssertEqual(after.y1, before.y1, accuracy: max(1, abs(before.y1) * 0.001), "\(t): the real items do not move the books")
            XCTAssertEqual(after.y2, before.y2, accuracy: max(1, abs(before.y2) * 0.001), t)
        }
    }
}
