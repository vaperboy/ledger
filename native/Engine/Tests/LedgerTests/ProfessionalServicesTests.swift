import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Professional services (cons, tutor, photo, law, acctfirm, mktg).
final class ProfessionalServicesTests: XCTestCase {
    static let trades = ["cons", "tutor", "photo", "law", "acctfirm", "mktg"]

    /// A competent owner as in `BalanceProbeTests.play`: the standard set-up, a manager for a team of four or more, then open.
    private func start(_ trade: String, seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.3)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            if let co = s.company(id), let bd = data.catalog[co.type], bd.standardStaff.reduce(0, { $0 + $1.count }) >= 4, co.managerID == nil {
                for _ in 0..<6 {
                    let c = ManagerModel.generateCandidate(company: s.company(id), type: bd.managerType, state: &s, data: data)
                    if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.2, data: data) == .ok { break }
                }
            }
        }
        guard id != 0 else { throw XCTSkip("could not start \(trade)") }
        // Licences and permits take a few weeks: open as soon as the checklist allows.
        for _ in 0..<100 where e.state.company(id)?.status != .open { _ = e.openCompany(companyID: id); _ = e.nextDay() }
        guard e.state.company(id)?.status == .open else { throw XCTSkip("\(trade) did not open") }
        return (e, id)
    }

    /// One week; with `withItems` the weekly step the lead hooks into `PriceMoves.weekly` runs after it.
    private func week(_ e: inout GameEngine, _ id: Int, withItems: Bool) {
        for _ in 0..<7 { _ = e.nextDay() }
        if withItems { e.update { s, d, _ in ProfessionalServices.prepare(&s, companyID: id, data: d) } }
    }

    func testRegistryAndSpecsMatchTheCatalog() throws {
        XCTAssertEqual(ItemTradeGroups.professional, Set(Self.trades))
        for t in Self.trades {
            let ts = try XCTUnwrap(ProfessionalServices.specs[t], t)
            XCTAssertTrue(ProfessionalServices.applies(t))
            XCTAssertGreaterThanOrEqual(ts.items.filter { $0.start }.count, 4, t)
            XCTAssertGreaterThanOrEqual(ts.items.count, 8, t)
            let cat = NewItemOptions.catalog[t] ?? []
            XCTAssertEqual(Set(cat.map { $0.name }), Set(ts.items.map { $0.name }), "\(t): the add-item catalog offers exactly the real service types")
            XCTAssertEqual(Set(ts.items.map { $0.id }).count, ts.items.count, "\(t): ids are unique")
            for sp in ts.items {
                XCTAssertGreaterThan(sp.share, 0); XCTAssertGreaterThan(sp.rate, 0)
                XCTAssertEqual(cat.first { $0.name == sp.name }?.isService, sp.isService, "\(sp.name)")
                XCTAssertEqual(sp.goods != nil, !sp.isService, sp.name)
            }
        }
    }

    func testSpecRolesExistAndEveryServiceEarnsAtItsPlannedUtilisation() throws {
        let data = try GameData.bundled()
        for t in Self.trades {
            let ts = try XCTUnwrap(ProfessionalServices.specs[t]); let bd = try XCTUnwrap(data.catalog[t])
            let start = ts.items.filter { $0.start }
            let total = start.reduce(0.0) { $0 + $1.share }
            let mean = start.reduce(0.0) { $0 + $1.share / total * $1.rate }
            for sp in ts.items {
                for r in sp.roles { XCTAssertNotNil(data.catalog.tables.roles[r.role], "\(t) \(sp.name): role \(r.role)") }
                guard sp.goods == nil else { continue }
                // Margin of one block at the market price, from the costs the page shows: 1 - consumables - write-off - labour / relative price.
                let ratio = sp.rate / mean
                let margin = 1 - sp.consumables - sp.writeOff - ts.labourShare * ProfessionalServices.labourFactor(sp, bd, data) / ratio
                XCTAssertGreaterThan(margin, 0, "\(t) \(sp.name) must not lose money by design at the planned utilisation")
            }
        }
    }

    func testSeedingKeepsRevenueAndMakesRecordsAndPaperTrailStaysBalanced() throws {
        for t in Self.trades {
            var (a, ia) = try start(t); var (b, ib) = try start(t)
            e_prepare(&b, ib)
            for _ in 0..<6 { week(&a, ia, withItems: false); week(&b, ib, withItems: true) }
            let la = a.state.company(ia)!.value("lastW"), lb = b.state.company(ib)!.value("lastW")
            XCTAssertEqual(la["rev"].double, lb["rev"].double, accuracy: max(1, la["rev"].double * 1e-9), "\(t): the new items do not move revenue")
            XCTAssertEqual(a.state.company(ia)!.cash, b.state.company(ib)!.cash, accuracy: 1, "\(t): nor cash")
            XCTAssertTrue(Ledger.gaps(b.state).isEmpty, t)
            let co = b.state.company(ib)!
            let rows = b.salesItems(companyID: ib)
            XCTAssertEqual(rows.map { $0.name }, ProfessionalServices.startNames(t), t)
            let recs = ItemModels.records(co)
            XCTAssertEqual(recs.count, rows.count, t)
            XCTAssertFalse(recs.contains { $0.id.hasPrefix("d") && $0.id.count <= 3 }, "no record of the old default list")
            XCTAssertTrue(recs.allSatisfy { $0.cost > 0 }, t)
            let neutral = b.state.company(ib).map { SalesItems.items($0, b.data.catalog[t]!).reduce(0.0) { $0 + $1.unitShare * $1.ratio } } ?? 0
            XCTAssertEqual(neutral, 1, accuracy: 1e-9, t)
            XCTAssertEqual(co.num("w5seed"), 1)
        }
    }

    private func e_prepare(_ e: inout GameEngine, _ id: Int) { e.update { s, d, _ in ProfessionalServices.prepare(&s, companyID: id, data: d) } }

    func testEconomicsSliderShowsLossBelowBreakEvenAndProfitAbove() throws {
        for t in Self.trades {
            var (e, id) = try start(t)
            e_prepare(&e, id)
            for _ in 0..<3 { week(&e, id, withItems: true) }
            // A steady week at the planned utilisation (a new company is often quieter, see testQuietWeeksMakeEveryBilledHourDearer).
            let planned = try XCTUnwrap(ProfessionalServices.specs[t]).plannedUtilisation
            e.update { s, _, _ in
                if let i = s.companyIndex(id) {
                    var lw = s.companies[i].value("lastW"); lw["util"] = .number(planned); lw["cap"] = .number(max(1, lw["cap"].double))
                    // whole daily sales can leave a young firm with no sold units yet: the steady week carries units too
                    lw["units"] = .number(planned * lw["cap"].double); s.companies[i].set("lastW", lw)
                }
            }
            let it = try XCTUnwrap(e.salesItems(companyID: id).first { $0.name != "Prints and albums" })
            let at = try XCTUnwrap(ProfessionalServices.economics(e.state, companyID: id, itemID: it.id, data: e.data), t)
            XCTAssertEqual(at.priceVsFair, 1, accuracy: 1e-9)
            XCTAssertEqual(at.jobPrice, at.hourlyRate * at.hoursPerJob, accuracy: 1e-6)
            XCTAssertEqual(at.live.outcome, .profit, "\(t) \(it.name) earns at the market price")
            XCTAssertEqual(at.breakEvenHourly * at.hoursPerBlock, at.unitCost, accuracy: 1e-6)
            let low = try XCTUnwrap(ProfessionalServices.economics(e.state, companyID: id, itemID: it.id, price: at.unitCost * 0.8, data: e.data))
            XCTAssertEqual(low.live.outcome, .loss); XCTAssertLessThan(low.profitPerHour, 0); XCTAssertLessThan(low.weeklyProfit, 0)
            let high = try XCTUnwrap(ProfessionalServices.economics(e.state, companyID: id, itemID: it.id, price: at.blockPrice * 1.5, data: e.data))
            XCTAssertEqual(high.live.outcome, .profit); XCTAssertGreaterThan(high.priceVsFair, 1)
            XCTAssertLessThan(high.weeklyUnits, at.weeklyUnits, "a dearer rate sells fewer hours")
            XCTAssertLessThan(high.saleProbability, at.saleProbability)
            XCTAssertLessThan(at.sliderLow, at.sliderHigh)
            XCTAssertFalse(at.roleLabel.isEmpty); XCTAssertFalse(at.text.isEmpty)
        }
    }

    func testQuietWeeksMakeEveryBilledHourDearer() throws {
        var (e, id) = try start("law")
        e_prepare(&e, id)
        for _ in 0..<2 { week(&e, id, withItems: true) }
        let itemID = e.salesItems(companyID: id)[0].id
        func cost(util: Double) -> Double {
            var x = e
            x.update { s, d, _ in
                if let i = s.companyIndex(id) {
                    var lw = s.companies[i].value("lastW"); lw["util"] = .number(util); lw["cap"] = .number(max(1, lw["cap"].double)); s.companies[i].set("lastW", lw)
                }
            }
            return ProfessionalServices.economics(x.state, companyID: id, itemID: itemID, data: x.data)!.unitCost
        }
        let planned = ProfessionalServices.specs["law"]!.plannedUtilisation
        XCTAssertGreaterThan(cost(util: planned / 2), cost(util: planned))
        XCTAssertLessThan(cost(util: 1), cost(util: planned))
    }

    func testPayOfTheRolesDecidesTheLabourCostOfAService() throws {
        let data = try GameData.bundled(); let bd = try XCTUnwrap(data.catalog["law"]); let ts = try XCTUnwrap(ProfessionalServices.specs["law"])
        let review = try XCTUnwrap(ts.items.first { $0.id == "contract" }), dispute = try XCTUnwrap(ts.items.first { $0.id == "dispute" })
        XCTAssertLessThan(ProfessionalServices.labourFactor(review, bd, data), 1, "a paralegal does most of a contract review")
        XCTAssertGreaterThan(ProfessionalServices.labourFactor(dispute, bd, data), 1, "a dispute is a lawyer's work")
    }

    func testAddedServiceTypeGetsItsRealPriceAndRecordWithoutMovingRevenue() throws {
        var (e, id) = try start("cons")
        e_prepare(&e, id)
        for _ in 0..<2 { week(&e, id, withItems: true) }
        e.update { s, d, _ in SalesItems.add(&s, companyID: id, name: "Market entry study", isService: true, data: d) }
        week(&e, id, withItems: true)
        let co = e.state.company(id)!, bd = e.data.catalog["cons"]!
        let items = SalesItems.items(co, bd)
        let added = try XCTUnwrap(items.first { $0.name == "Market entry study" })
        let r = try XCTUnwrap(ItemModels.record(co, itemID: added.id))
        XCTAssertEqual(r.model, .svc); XCTAssertEqual(r.leadDays, 28); XCTAssertGreaterThan(r.cost, 0)
        XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare * $1.ratio }, 1, accuracy: 1e-9)
        let hour = try XCTUnwrap(items.first { $0.name == "Advisory hour" })
        XCTAssertEqual(added.ratio / hour.ratio, 1.10, accuracy: 1e-9, "a study is priced at its own rate against the hour")
        XCTAssertNotNil(ProfessionalServices.economics(e.state, companyID: id, itemID: added.id, data: e.data))
    }

    func testRetainersCountClientsAndGoodsRunStock() throws {
        var (e, id) = try start("photo")
        e_prepare(&e, id)
        for _ in 0..<8 { week(&e, id, withItems: true) }
        let prints = try XCTUnwrap(e.salesItems(companyID: id).first { $0.name == "Prints and albums" })
        let r = try XCTUnwrap(ItemModels.record(e.state.company(id)!, itemID: prints.id))
        XCTAssertEqual(r.model, .made)
        XCTAssertGreaterThan(r.stock + r.onOrder, 0, "an order is always out or stock is on the shelf")
        XCTAssertGreaterThanOrEqual(r.stock, 0)
        XCTAssertEqual(r.leadDays, 5)
        let g = try XCTUnwrap(ProfessionalServices.economics(e.state, companyID: id, itemID: prints.id, data: e.data))
        XCTAssertTrue(g.isGoods); XCTAssertNil(g.clients)
        var (m, mid) = try start("mktg")
        e_prepare(&m, mid)
        for _ in 0..<3 { week(&m, mid, withItems: true) }
        let ret = try XCTUnwrap(m.salesItems(companyID: mid).first { $0.name == "Monthly retainer" })
        let eco = try XCTUnwrap(ProfessionalServices.economics(m.state, companyID: mid, itemID: ret.id, data: m.data))
        XCTAssertEqual(eco.model, .sub); XCTAssertEqual(eco.clientLabel, "Retainer clients"); XCTAssertGreaterThan(eco.churn, 0)
        XCTAssertEqual(eco.clients ?? -1, eco.jobsPerWeek * 52 / 12, accuracy: 1e-9)
    }

    func testOtherTradesAndOldSavesAreNeverTouched() throws {
        var (e, id) = try start("barber")
        let before = e.state
        e.update { s, d, _ in ProfessionalServices.prepare(&s, companyID: id, data: d) }
        XCTAssertTrue(e.state == before)
        XCTAssertTrue(e.state.company(id)!.value("w5seed").isNull)
        XCTAssertNil(ProfessionalServices.economics(e.state, companyID: id, itemID: "d0", data: e.data))
    }

    func testSaveRoundTrip() throws {
        var (e, id) = try start("acctfirm")
        e_prepare(&e, id)
        for _ in 0..<4 { week(&e, id, withItems: true) }
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertTrue(back == e.state)
        XCTAssertEqual(ItemModels.records(back.company(id)!), ItemModels.records(e.state.company(id)!))
    }

    /// Two-year survival probe of a competent owner (set up, open, nothing else) with and without the withItems. Prints profit; no clamps.
    func testTwoYearProbeEveryTradeKeepsItsProfit() throws {
        for t in Self.trades {
            var (a, ia) = try start(t, seed: 11); var (b, ib) = try start(t, seed: 11)
            e_prepare(&b, ib)
            let c0a = a.state.company(ia)!.cash
            var revA = 0.0, revB = 0.0
            for _ in 0..<104 {
                week(&a, ia, withItems: false); week(&b, ib, withItems: true)
                revA += a.state.company(ia)!.value("lastW")["rev"].double; revB += b.state.company(ib)!.value("lastW")["rev"].double
            }
            let ca = a.state.company(ia)!.cash, cb = b.state.company(ib)!.cash
            print("PROFESSIONAL probe \(t): cash change before \(Int(ca - c0a)), after \(Int(cb - c0a)); revenue before \(Int(revA)), after \(Int(revB)); status \(b.state.company(ib)!.status)")
            XCTAssertEqual(ca, cb, accuracy: max(1, abs(ca) * 1e-9), "\(t): the withItems moves no money")
            XCTAssertEqual(revA, revB, accuracy: max(1, revA * 1e-9), t)
            XCTAssertTrue(Ledger.gaps(b.state).isEmpty, t)
            if let o = try BalanceProbeTests.play(trade: t, seed: 11, years: 2) {
                print("PROFESSIONAL balance probe \(t) (the standard owner of BalanceProbeTests, withItems economics are identical): invested \(Int(o.invested)), yearly profit \(Int(o.profitY3)), value \(Int(o.value)), status \(o.status)")
            }
            let rows = b.salesItems(companyID: ib)
            let eco = rows.compactMap { ProfessionalServices.economics(b.state, companyID: ib, itemID: $0.id, data: b.data) }
            XCTAssertEqual(eco.count, rows.count, t)
            let weekly = eco.reduce(0.0) { $0 + $1.weeklyProfit }
            print("PROFESSIONAL probe \(t): items \(eco.count), sum of item profits a week \(Int(weekly)), utilisation \(eco.first?.utilisation.map { String(format: "%.2f", $0) } ?? "n/a")")
        }
    }
}
