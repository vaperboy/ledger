import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private extension GameEngine {
    mutating func w7week() { for _ in 0..<7 { _ = nextDay() } }
}

/// Construction, electrician, plumber, handyman, engineering office, security (PROJ and job-contract model).
final class JobContractsTests: XCTestCase {
    let trades = ["construction", "electrician", "plumber", "handy", "engcons", "security"]

    func start(_ trade: String, weeks: Int = 2, seed: Int = 7, setup: Bool = false) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { throw XCTSkip("could not start \(trade)") }
        if setup { e.update { s, d, _ in _ = CompanySetup.quickSetup(&s, companyID: id, data: d) } }
        for _ in 0..<weeks { e.w7week() }
        return (e, id)
    }

    func facts(_ name: String, _ e: GameEngine, _ id: Int) throws -> JobContracts.Facts {
        let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog[co.type])
        let it = try XCTUnwrap(SalesItems.items(co, bd).first { $0.name == name }, name)
        return try XCTUnwrap(JobContracts.facts(e.state, companyID: id, itemID: it.id, data: e.data))
    }

    /// A company that has traded: last week's customers set (a fresh test company has no staff to serve anyone yet).
    func traded(_ e: inout GameEngine, _ id: Int, units: Double) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("lastW", .object(["units": .number(units), "rev": .number(0), "cogs": .number(0), "D": .number(units), "cap": .number(units * 2), "util": .number(0.5)]))
        }
    }

    func testRegistryHoldsExactlyTheSixTrades() {
        XCTAssertEqual(ItemTradeGroups.jobs, Set(trades))
        XCTAssertEqual(Set(JobContracts.tradeIDs), Set(trades))
    }

    func testSpecsAreConsistentWithTheBooks() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        for t in trades {
            let ts = try XCTUnwrap(JobContracts.tradeSpec(t), t)
            let bd = try XCTUnwrap(e.data.catalog[t], t)
            let m = JobContracts.mix(ts.items)
            XCTAssertEqual(m.q.reduce(0, +), 1, accuracy: 1e-9, t)
            XCTAssertEqual(zip(m.q, m.ratio).reduce(0.0) { $0 + $1.0 * $1.1 }, 1, accuracy: 1e-9, "\(t): revenue weights add up to 1")
            let names = (ts.items + ts.extra).map { $0.name.lowercased() }
            XCTAssertEqual(Set(names).count, names.count, "\(t): names are unique across menu and catalogue")
            XCTAssertLessThanOrEqual(ts.items.count, SalesItems.maxItems)
            let target = JobContracts.targetCostShare(bd), k = JobContracts.calibration(ts, target: target)
            print("W7 \(t): books cost share \(String(format: "%.2f", target)), calibration \(String(format: "%.2f", k)) (1 = the data already matched)")
            if target > 0 { XCTAssertGreaterThan(k, 0.3, t); XCTAssertLessThan(k, 2.5, t) } else { XCTAssertEqual(k, 0, t) }
            for s in ts.items + ts.extra {
                XCTAssertLessThan(JobContracts.costShare(s, calibration: k), 0.9, "\(t) \(s.name): the price covers the cost by design")
                if s.isStock { XCTAssertGreaterThan(s.lead, 0, s.name) } else {
                    XCTAssertGreaterThan(s.hours, 0, s.name); XCTAssertFalse(s.crew.isEmpty, s.name)
                }
                if s.model == .sub { XCTAssertGreaterThan(s.visits, 0, s.name) }
                XCTAssertEqual(s.phases.reduce(0.0) { $0 + $1.share }, s.phases.isEmpty ? 0 : 1, accuracy: 1e-9, "\(t) \(s.name): phases add up")
            }
        }
    }

    func testInstallGivesTheRealMenuAndKeepsTheBooksNeutral() throws {
        for t in trades {
            var (e, id) = try start(t, weeks: 0)   // the weekly hook installs the items by itself: install on a fresh company
            let before = e.salesItems(companyID: id)
            var made = 0
            e.update { s, d, _ in made = JobContracts.install(&s, companyID: id, data: d) }
            let co = try XCTUnwrap(e.state.company(id))
            let bd = try XCTUnwrap(e.data.catalog[t])
            let ts = try XCTUnwrap(JobContracts.tradeSpec(t))
            let list = SalesItems.items(co, bd)
            XCTAssertEqual(list.map { $0.name }, ts.items.map { $0.name }, t)
            XCTAssertEqual(made, ts.items.count, t)
            XCTAssertNotEqual(before.map { $0.name }, list.map { $0.name }, "\(t): titles replaced by real jobs")
            XCTAssertEqual(SalesItems.demandFactor(co), 1, accuracy: 1e-12, t)
            XCTAssertEqual(SalesItems.ticketFactor(co), 1, accuracy: 1e-12, t)
            XCTAssertEqual(list.reduce(0.0) { $0 + $1.unitShare * $1.ratio }, 1, accuracy: 1e-9, t)
            let mt = SalesItems.marketTicket(co, bd, World(state: e.state, data: e.data))
            var weighted = 0.0
            print("W7 \(t): going ticket \(Int(mt))")
            for it in list {
                let r = try XCTUnwrap(ItemModels.record(co, itemID: it.id), "\(t) \(it.name) has a record")
                weighted += it.unitShare * r.cost
                let price = mt * it.ratio
                let f = try XCTUnwrap(JobContracts.facts(e.state, companyID: id, itemID: it.id, data: e.data))
                print(String(format: "W7   %@ | price %.0f | materials %.0f | labour %.0f (%.1f h, %.1f/h) | profit %.0f | max/wk %.1f | util %.2f | start %.0f d", it.name, price,
                             r.cost, f.labourCost, f.hours, f.costPerHour, f.profit, f.maxPerWeek, f.utilisation, f.startInDays))
                XCTAssertGreaterThan(r.prep + r.cost, 0, it.name)
                XCTAssertLessThan(r.cost, price, "\(t) \(it.name): materials cost less than the price")
            }
            XCTAssertEqual(weighted, mt * JobContracts.targetCostShare(bd), accuracy: mt * 1e-9, "\(t): menu cost equals the books")
            var again = -1
            e.update { s, d, _ in again = JobContracts.install(&s, companyID: id, data: d) }
            XCTAssertEqual(again, 0, "\(t): idempotent")
        }
    }

    func testModelsAndTheQuoteBreakdown() throws {
        var (e, id) = try start("electrician", weeks: 4)
        e.update { s, d, _ in JobContracts.install(&s, companyID: id, data: d) }
        let call = try facts("Call-out and fault finding", e, id), rewire = try facts("Rewire (3-bed house)", e, id)
        let fuse = try facts("Fuse board replacement", e, id), plan = try facts("Annual safety inspection plan", e, id)
        XCTAssertEqual(call.model, .svc); XCTAssertEqual(rewire.model, .proj); XCTAssertEqual(plan.model, .sub)
        XCTAssertTrue(call.isCallout); XCTAssertFalse(rewire.isCallout)
        XCTAssertLessThanOrEqual(call.startInDays, 1, "a call-out does not wait in the queue")
        XCTAssertGreaterThanOrEqual(rewire.startInDays, Double(rewire.leadDays), "a scheduled job waits for its lead time at least")
        XCTAssertGreaterThan(rewire.hours, fuse.hours)
        XCTAssertGreaterThan(rewire.crewSize, call.crewSize)
        XCTAssertEqual(rewire.materialsCharge, rewire.materialsCost * (1 + rewire.markup), accuracy: 1e-9, "materials at cost plus markup")
        XCTAssertGreaterThan(rewire.markup, 0)
        XCTAssertEqual(rewire.fullCost, rewire.materialsCost + (rewire.fullCost - rewire.materialsCost), accuracy: 1e-9)
        XCTAssertGreaterThan(rewire.fullCost, rewire.materialsCost + rewire.labourCost - 1e-9, "labour and callbacks are in the real cost")
        XCTAssertEqual(rewire.profit, rewire.price - rewire.fullCost, accuracy: 1e-9)
        XCTAssertGreaterThan(rewire.warrantyRate, 0)
        XCTAssertEqual(rewire.phases.count, 3)
        XCTAssertEqual(rewire.phases.reduce(0.0) { $0 + $1.amount }, rewire.price, accuracy: 1e-6)
        XCTAssertFalse(rewire.document.isEmpty)
        XCTAssertTrue(plan.isRecurring)
        XCTAssertEqual(plan.recurringPerPeriod, plan.members * plan.visitsPerPeriod * plan.price, accuracy: 1e-6)
        // The live profit and loss of the item page uses the same real cost.
        let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog["electrician"])
        let it = try XCTUnwrap(SalesItems.items(co, bd).first { $0.name == "Rewire (3-bed house)" })
        let lp = try XCTUnwrap(ItemModels.liveProfit(e.state, companyID: id, itemID: it.id, price: rewire.price * 0.5, data: e.data))
        XCTAssertEqual(lp.cost, rewire.fullCost, accuracy: 1e-6)
        XCTAssertEqual(lp.outcome, rewire.price * 0.5 > rewire.fullCost ? .profit : .loss)
        XCTAssertEqual(ItemModels.liveProfit(e.state, companyID: id, itemID: it.id, price: rewire.fullCost, data: e.data)?.outcome, .breakEven)
    }

    func testConstructionPhasesSubcontractorsAndRetention() throws {
        var (e, id) = try start("construction", weeks: 6, setup: true)
        e.update { s, d, _ in JobContracts.install(&s, companyID: id, data: d) }
        traded(&e, id, units: 3)
        let ext = try facts("House extension", e, id), roof = try facts("Roof repair", e, id), maint = try facts("Maintenance contract (per month)", e, id)
        XCTAssertEqual(ext.phases.count, 5)
        XCTAssertGreaterThan(ext.phases.reduce(0.0) { $0 + $1.subcontract }, 0, "subcontractors on the extension")
        XCTAssertGreaterThan(ext.retention, 0)
        XCTAssertGreaterThan(ext.jobWeeks, roof.jobWeeks)
        XCTAssertGreaterThan(ext.leadDays, roof.leadDays)
        XCTAssertTrue(maint.isContract)
        XCTAssertGreaterThan(maint.crewFTE, 0)
    }

    func testSecurityContractHoursAndMonitoring() throws {
        var (e, id) = try start("security", weeks: 6, setup: true)
        e.update { s, d, _ in JobContracts.install(&s, companyID: id, data: d) }
        traded(&e, id, units: 400)
        let site = try facts("Guard hours, site contract (per month)", e, id), temp = try facts("Guard hour (temporary, event)", e, id)
        let mon = try facts("Alarm monitoring contract", e, id), cctv = try facts("CCTV install", e, id)
        XCTAssertTrue(site.isContract)
        XCTAssertGreaterThan(site.members, 0, "sites on contract")
        XCTAssertEqual(site.crewHoursPerWeek, site.weeklyJobs * site.hours, accuracy: 1e-9)
        XCTAssertGreaterThan(site.crewFTE, 0)
        XCTAssertGreaterThan(site.price, 0)
        XCTAssertLessThan(site.leadDays, 15)
        XCTAssertGreaterThan(temp.price, site.price, "temporary hours cost more than the site contract")
        XCTAssertTrue(mon.isRecurring)
        XCTAssertGreaterThan(cctv.materialsCost, 0, "CCTV carries its equipment")
        XCTAssertGreaterThan(cctv.price, temp.price)
    }

    func testHandyKitStockRunsDownAndIsReordered() throws {
        var (e, id) = try start("handy", weeks: 6, setup: true)
        // the kit only sells down once the company is open and has traded a full week of its own cycle
        var extra = 0
        while (e.state.company(id)?.status != .open || e.state.company(id)?.value("lastW")["units"].double ?? 0 <= 0), extra < 30 { e.w7week(); extra += 1 }
        XCTAssertEqual(e.state.company(id)?.status, .open, "handy should have opened")
        e.update { s, d, _ in JobContracts.install(&s, companyID: id, data: d) }
        var sawOrder = false, sawArrival = false
        var last: Int?
        for _ in 0..<16 {
            e.w7week()
            e.update { s, d, _ in if let i = s.companyIndex(id) { JobContracts.weekly(&s, i, data: d) } }
            let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog["handy"])
            let it = try XCTUnwrap(SalesItems.items(co, bd).first { $0.name == "Tool and materials kit" })
            let r = try XCTUnwrap(ItemModels.record(co, itemID: it.id))
            XCTAssertEqual(r.model, .stk)
            XCTAssertGreaterThanOrEqual(r.stock, 0); XCTAssertGreaterThanOrEqual(r.onOrder, 0)
            if r.onOrder > 0 { sawOrder = true }
            if let l = last, r.stock > l { sawArrival = true }
            last = r.stock
        }
        XCTAssertTrue(sawOrder); XCTAssertTrue(sawArrival)
    }

    func testWeeklyKeepsLabourCostAtTodaysPay() throws {
        var (e, id) = try start("plumber", weeks: 4)
        e.update { s, d, _ in JobContracts.install(&s, companyID: id, data: d) }
        let name = "Bathroom install"
        let before = try facts(name, e, id)
        e.update { s, d, _ in
            if let i = s.companyIndex(id) { JobContracts.weekly(&s, i, data: d) }
        }
        let after = try facts(name, e, id)
        XCTAssertEqual(after.fullCost, before.fullCost, accuracy: before.fullCost * 0.02, "stable within a week")
        XCTAssertGreaterThan(after.labourCost, 0)
    }

    func testTouchedListIsKeptAndOnlyGetsRecords() throws {
        var (e, id) = try start("handy", weeks: 0)
        let first = try XCTUnwrap(e.salesItems(companyID: id).first)
        e.update { s, d, _ in SalesItems.setPrice(&s, companyID: id, itemID: first.id, price: first.price * 1.1, data: d) }
        let names = e.salesItems(companyID: id).map { $0.name }
        var made = 0
        e.update { s, d, _ in made = JobContracts.install(&s, companyID: id, data: d) }
        XCTAssertEqual(e.salesItems(companyID: id).map { $0.name }, names, "the player's own list stays")
        XCTAssertEqual(made, names.count)
    }

    func testNothingHappensForATradeThatIsNotOptedIn() throws {
        var (e, id) = try start("electrician")
        let before = e.state
        var made = -1
        e.update { s, d, _ in made = JobContracts.install(&s, companyID: id, data: d, trades: []) }
        XCTAssertEqual(made, 0)
        XCTAssertTrue(e.state == before)
        let other = try start("barber").0
        XCTAssertNil(JobContracts.facts(other.state, companyID: other.state.companies.first?.id ?? 0, itemID: "d0", data: other.data))
    }

    func testSaveRoundTripOfTheRecords() throws {
        var (e, id) = try start("construction")
        e.update { s, d, _ in JobContracts.install(&s, companyID: id, data: d) }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertFalse(ItemModels.records(co).isEmpty)
        let json = try JSONEncoder().encode(co.value("itemsv2"))
        let back = try JSONDecoder().decode(JSONValue.self, from: json)
        XCTAssertTrue(back == co.value("itemsv2"))
    }

    // MARK: Two-year survival probe (LEDGER_JOBS_PROBE=1; slow)

    struct Result { var y1: Double; var y2: Double; var status: String }

    static func play(_ trade: String, withItems: Bool, seed: Int, years: Int = 2) throws -> Result? {
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
                if withItems && day % 7 == 6 { e.update { s, d, _ in if let i = s.companyIndex(id) { JobContracts.weekly(&s, i, data: d) } } }
            }
        }
        guard let co = e.state.company(id) else { return nil }
        let h = co.monthlyHistory
        return Result(y1: h.prefix(12).reduce(0) { $0 + $1.profit }, y2: h.dropFirst(12).prefix(12).reduce(0) { $0 + $1.profit }, status: co.status.rawValue)
    }

    func testTwoYearProbeBeforeAndAfter() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_JOBS_PROBE"] != nil else { return }
        for t in trades {
            let before = try XCTUnwrap(Self.play(t, withItems: false, seed: 11)), after = try XCTUnwrap(Self.play(t, withItems: true, seed: 11))
            print(String(format: "W7 PROBE %@ | before y1 %.0f y2 %.0f %@ | after y1 %.0f y2 %.0f %@", t, before.y1, before.y2, before.status, after.y1, after.y2, after.status))
            XCTAssertEqual(after.status, before.status, t)
            XCTAssertEqual(after.y1, before.y1, accuracy: max(1, abs(before.y1) * 0.001), "\(t): the real menu does not move the books")
            XCTAssertEqual(after.y2, before.y2, accuracy: max(1, abs(before.y2) * 0.001), t)
        }
    }
}
