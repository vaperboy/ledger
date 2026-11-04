import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private extension GameEngine {
    mutating func w6week() { for _ in 0..<7 { _ = nextDay() } }
}

/// Wave 6: barber, driving school, physio, dental, car cleaning, cleaning company (SVC appointment and crew model).
final class Wave6Tests: XCTestCase {
    let trades = ["barber", "drivsk", "physio", "dental", "carclean", "cleaning"]

    func start(_ trade: String, weeks: Int = 2, seed: Int = 7, setup: Bool = false) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { throw XCTSkip("could not start \(trade)") }
        if setup { e.update { s, d, _ in _ = CompanySetup.quickSetup(&s, companyID: id, data: d) } }
        for _ in 0..<weeks { e.w6week() }
        return (e, id)
    }

    func testRegistryHoldsExactlyTheSixTrades() {
        XCTAssertEqual(ItemWaves.w6, Set(trades))
        XCTAssertEqual(Set(Wave6.tradeIDs), Set(trades))
    }

    func testSpecsAreConsistentWithTheBooks() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        for t in trades {
            let ts = try XCTUnwrap(Wave6.tradeSpec(t), t)
            let bd = try XCTUnwrap(e.data.catalog[t], t)
            let m = Wave6.mix(ts.items)
            XCTAssertEqual(m.q.reduce(0, +), 1, accuracy: 1e-9, t)
            XCTAssertEqual(zip(m.q, m.ratio).reduce(0.0) { $0 + $1.0 * $1.1 }, 1, accuracy: 1e-9, "\(t): revenue weights add up to 1")
            let names = (ts.items + ts.extra).map { $0.name.lowercased() }
            XCTAssertEqual(Set(names).count, names.count, "\(t): names are unique across menu and catalogue")
            XCTAssertLessThanOrEqual(ts.items.count, SalesItems.maxItems)
            let k = Wave6.calibration(ts, cogs: bd.costOfSales)
            print("W6 \(t): cost calibration \(String(format: "%.2f", k)) (1 = the data already matched the books)")
            XCTAssertGreaterThan(k, 0.5, t); XCTAssertLessThan(k, 2.0, t)
            for s in ts.items + ts.extra {
                XCTAssertLessThan(Wave6.costShare(s, calibration: k), 0.9, "\(t) \(s.name): the price covers the cost by design")
                if s.isRetail { XCTAssertGreaterThan(s.lead, 0, s.name) } else { XCTAssertGreaterThan(s.minutes, 0, s.name) }
                if s.model == .sub { XCTAssertGreaterThan(s.visits, 0, s.name) }
            }
            XCTAssertTrue(ts.items.contains { $0.isRetail } || t == "cleaning" || t == "drivsk", "\(t) sells something stocked or is a pure service")
        }
    }

    func testInstallGivesTheRealMenuAndKeepsTheBooksNeutral() throws {
        for t in trades {
            var (e, id) = try start(t, weeks: 0)
            let before = e.salesItems(companyID: id)
            var made = 0
            e.update { s, d, _ in made = Wave6.install(&s, companyID: id, data: d) }
            let co = try XCTUnwrap(e.state.company(id))
            let bd = try XCTUnwrap(e.data.catalog[t])
            let ts = try XCTUnwrap(Wave6.tradeSpec(t))
            let list = SalesItems.items(co, bd)
            XCTAssertEqual(list.map { $0.name }, ts.items.map { $0.name }, t)
            XCTAssertEqual(made, ts.items.count, t)
            XCTAssertNotEqual(before.map { $0.name }, list.map { $0.name }, "\(t): titles replaced by real services")
            XCTAssertEqual(SalesItems.demandFactor(co), 1, accuracy: 1e-12, t)
            XCTAssertEqual(SalesItems.ticketFactor(co), 1, accuracy: 1e-12, t)
            XCTAssertEqual(list.reduce(0.0) { $0 + $1.unitShare * $1.ratio }, 1, accuracy: 1e-9, t)
            // The weighted cost of the whole menu is the trade's cost-of-sales share of the going ticket: the books do not move.
            let mt = SalesItems.marketTicket(co, bd, World(state: e.state, data: e.data))
            var weighted = 0.0
            for it in list {
                let r = try XCTUnwrap(ItemModels.record(co, itemID: it.id), "\(t) \(it.name) has a record")
                XCTAssertGreaterThan(r.cost, 0, it.name)
                weighted += it.unitShare * r.cost
                XCTAssertLessThan(r.cost, mt * it.ratio, "\(t) \(it.name): costs less than it sells for")
            }
            XCTAssertEqual(weighted, mt * bd.costOfSales, accuracy: mt * 1e-9, "\(t): menu cost equals the books")
            var again = -1
            e.update { s, d, _ in again = Wave6.install(&s, companyID: id, data: d) }
            XCTAssertEqual(again, 0, "\(t): idempotent")
        }
    }

    func testRecordsAreTheRightModel() throws {
        var (e, id) = try start("dental")
        e.update { s, d, _ in Wave6.install(&s, companyID: id, data: d) }
        let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog["dental"])
        func rec(_ name: String) throws -> ItemModels.Record {
            let it = try XCTUnwrap(SalesItems.items(co, bd).first { $0.name == name }, name)
            return try XCTUnwrap(ItemModels.record(co, itemID: it.id))
        }
        XCTAssertEqual(try rec("Recall plan").model, .sub)
        XCTAssertEqual(try rec("Dental products").model, .stk)
        XCTAssertGreaterThan(try rec("Dental products").stock, 0)
        XCTAssertEqual(try rec("Crown").model, .svc)
        // A crown carries the lab fee, a check-up only a little consumable: per-item margins differ.
        let crown = try rec("Crown"), check = try rec("Check-up and scale")
        let list = SalesItems.items(co, bd)
        let rCrown = try XCTUnwrap(list.first { $0.name == "Crown" }).ratio, rCheck = try XCTUnwrap(list.first { $0.name == "Check-up and scale" }).ratio
        XCTAssertGreaterThan(crown.cost / rCrown, check.cost / rCheck)
    }

    func testTouchedListIsKeptAndOnlyGetsRecords() throws {
        var (e, id) = try start("barber", weeks: 0)
        let first = try XCTUnwrap(e.salesItems(companyID: id).first)
        e.update { s, d, _ in SalesItems.setPrice(&s, companyID: id, itemID: first.id, price: first.price * 1.1, data: d) }
        let names = e.salesItems(companyID: id).map { $0.name }
        var made = 0
        e.update { s, d, _ in made = Wave6.install(&s, companyID: id, data: d) }
        XCTAssertEqual(e.salesItems(companyID: id).map { $0.name }, names, "the player's own list stays")
        XCTAssertGreaterThanOrEqual(made, 0)
    }

    func testNothingHappensForATradeThatIsNotOptedIn() throws {
        var (e, id) = try start("barber")
        let before = e.state
        var made = -1
        e.update { s, d, _ in made = Wave6.install(&s, companyID: id, data: d, trades: []) }
        XCTAssertEqual(made, 0)
        XCTAssertTrue(e.state == before)
    }

    func testFactsForAServiceARecurringPlanAndAContract() throws {
        var (e, id) = try start("barber", weeks: 6)
        e.update { s, d, _ in Wave6.install(&s, companyID: id, data: d) }
        func facts(_ name: String, _ eng: GameEngine, _ cid: Int) throws -> Wave6.Facts {
            let co = try XCTUnwrap(eng.state.company(cid)), bd = try XCTUnwrap(eng.data.catalog[co.type])
            let it = try XCTUnwrap(SalesItems.items(co, bd).first { $0.name == name }, name)
            return try XCTUnwrap(Wave6.facts(eng.state, companyID: cid, itemID: it.id, data: eng.data))
        }
        let colour = try facts("Colour and toner", e, id), cut = try facts("Cut and finish", e, id)
        XCTAssertEqual(colour.minutes, 120)
        XCTAssertGreaterThan(colour.unitCost, cut.unitCost, "colour uses real product")
        XCTAssertGreaterThan(colour.noShowRate, 0)
        XCTAssertGreaterThan(colour.rebookRate, 0)
        XCTAssertNotNil(colour.profitPerResourceHour)
        XCTAssertGreaterThan(cut.maxPerWeek, colour.maxPerWeek, "a colour takes four times the chair")
        let member = try facts("Grooming membership", e, id)
        XCTAssertTrue(member.isRecurring)
        XCTAssertGreaterThan(member.members, 0)
        XCTAssertEqual(member.recurringPerPeriod, member.members * member.visitsPerPeriod * member.price, accuracy: 1e-6)
        let products = try facts("Styling products", e, id)
        XCTAssertNil(products.profitPerResourceHour)
        XCTAssertGreaterThan(products.stock, 0)

        var (c, cid) = try start("cleaning", weeks: 6)
        c.update { s, d, _ in Wave6.install(&s, companyID: cid, data: d) }
        let office = try facts("Office contract (per month)", c, cid)
        XCTAssertTrue(office.isContract)
        XCTAssertGreaterThan(office.members, 0, "sites on contract")
        XCTAssertGreaterThan(office.crewFTE, 0)
        XCTAssertNil(Wave6.facts(c.state, companyID: cid, itemID: "nope", data: c.data))
    }

    func testReminderSystemCutsNoShows() throws {
        var (e, id) = try start("physio", weeks: 4)
        e.update { s, d, _ in Wave6.install(&s, companyID: id, data: d) }
        let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog["physio"])
        let it = try XCTUnwrap(SalesItems.items(co, bd).first { $0.name == "Treatment session" })
        var f = try XCTUnwrap(Wave6.facts(e.state, companyID: id, itemID: it.id, data: e.data))
        let base = Wave6.tradeSpec("physio")!.noShow
        XCTAssertEqual(f.noShowRate, f.remindersOn ? base * (1 - Wave6.tradeSpec("physio")!.reminderCut) : base, accuracy: 1e-12)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var eq = s.companies[i].value("eq"); eq["ehr"] = .object(["n": .number(1)]); s.companies[i].set("eq", eq)
        }
        f = try XCTUnwrap(Wave6.facts(e.state, companyID: id, itemID: it.id, data: e.data))
        XCTAssertTrue(f.remindersOn)
        XCTAssertEqual(f.noShowRate, base * (1 - Wave6.tradeSpec("physio")!.reminderCut), accuracy: 1e-12)
    }

    func testRetailStockRunsDownAndIsReorderedWithALeadTime() throws {
        var (e, id) = try start("carclean", weeks: 6, setup: true)
        e.update { s, d, _ in Wave6.install(&s, companyID: id, data: d) }
        var sawOrder = false, sawArrival = false
        var last: Int?
        for _ in 0..<40 {
            e.w6week()   // the company is open: the engine's own weekly hook (WaveHooks) ticks it, no manual tick
            let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog["carclean"])
            let it = try XCTUnwrap(SalesItems.items(co, bd).first { $0.name == "Car care products" })
            let r = try XCTUnwrap(ItemModels.record(co, itemID: it.id))
            XCTAssertGreaterThanOrEqual(r.stock, 0); XCTAssertGreaterThanOrEqual(r.onOrder, 0)
            if r.onOrder > 0 { sawOrder = true }
            if let l = last, r.stock > l { sawArrival = true }
            last = r.stock
        }
        XCTAssertTrue(sawOrder, "an order is placed when cover runs short")
        XCTAssertTrue(sawArrival, "and it arrives")
    }

    func testSaveRoundTripOfTheRecords() throws {
        var (e, id) = try start("dental")
        e.update { s, d, _ in Wave6.install(&s, companyID: id, data: d) }
        let co = try XCTUnwrap(e.state.company(id))
        let recs = ItemModels.records(co)
        XCTAssertFalse(recs.isEmpty)
        let json = try JSONEncoder().encode(co.value("itemsv2"))
        let back = try JSONDecoder().decode(JSONValue.self, from: json)
        XCTAssertTrue(back == co.value("itemsv2"))
    }

    // MARK: Two-year survival probe (LEDGER_WAVE6=1; slow)

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
                if wave && day % 7 == 6 { e.update { s, d, _ in if let i = s.companyIndex(id) { Wave6.weekly(&s, i, data: d) } } }
            }
        }
        guard let co = e.state.company(id) else { return nil }
        let h = co.monthlyHistory
        return Result(y1: h.prefix(12).reduce(0) { $0 + $1.profit }, y2: h.dropFirst(12).prefix(12).reduce(0) { $0 + $1.profit }, status: co.status.rawValue)
    }

    func testTwoYearProbeBeforeAndAfter() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_WAVE6"] != nil else { return }
        for t in trades {
            let before = try XCTUnwrap(Self.play(t, wave: false, seed: 11)), after = try XCTUnwrap(Self.play(t, wave: true, seed: 11))
            print(String(format: "W6 PROBE %@ | before y1 %.0f y2 %.0f %@ | after y1 %.0f y2 %.0f %@", t, before.y1, before.y2, before.status, after.y1, after.y2, after.status))
            XCTAssertEqual(after.status, before.status, t)
            XCTAssertEqual(after.y1, before.y1, accuracy: max(1, abs(before.y1) * 0.001), "\(t): the real menu does not move the books")
            XCTAssertEqual(after.y2, before.y2, accuracy: max(1, abs(before.y2) * 0.001), t)
        }
    }
}
