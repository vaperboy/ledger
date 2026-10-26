import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

/// Accounting rules: input VAT on repairs and leases, employer on-cost on perks, football disposals, salmon stock, project retention, the inflation index.
final class ModelRulesTests: XCTestCase {
    private func cafe(seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { XCTFail("start"); throw CocoaError(.fileReadUnknown) }
        return (e, id)
    }

    func testInputVATIsReclaimedWhenRegisteredAndACostWhenNot() throws {
        var (e, id) = try cafe()
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            let rate = World(state: s, data: d).country(s.companies[i]).vat.standard
            var cash = s.companies[i].cash
            let oth0 = s.companies[i].books.week["oth"] ?? 0
            Vat.input(&s, companyIndex: i, net: 1000, data: d)   // below the threshold: not registered
            XCTAssertEqual(cash - s.companies[i].cash, (1000 * rate).rounded(), accuracy: 1)
            XCTAssertEqual((s.companies[i].books.week["oth"] ?? 0) - oth0, (1000 * rate).rounded(), accuracy: 1, "unreclaimable VAT is a cost")
            var docs = s.companies[i].value("docs"); docs["vat"] = .object(["st": .string("ok")]); s.companies[i].set("docs", docs)
            let before = s.companies[i].vatBalance; cash = s.companies[i].cash
            Vat.input(&s, companyIndex: i, net: 1000, data: d)
            XCTAssertEqual(before - s.companies[i].vatBalance, (1000 * rate).rounded(), accuracy: 1, "registered: reclaimed through the VAT account")
            XCTAssertEqual(cash - s.companies[i].cash, (1000 * rate).rounded(), accuracy: 1)
        }
    }

    func testPerksCarryEmployerOnCost() throws {
        var (e, id) = try cafe()
        var pid = 0
        e.update { s, d, _ in pid = Hiring.generateCandidate(role: "barista", company: s.company(id), tier: "mid", state: &s, data: d).id }
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: 300_000, terms: Hiring.Terms()), .ok)
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            s.companies[i].status = .open
            let perk = StaffPerks.all.first { $0.id != "car" && $0.monthlyCost > 0 && !$0.groups.isEmpty }!
            _ = StaffPerks.toggle(&s, companyID: id, perk: perk.id)
            let w = World(state: s, data: d), co = s.companies[i], k = w.country(co)
            let monthly = StaffPerks.onPerks(co).filter { $0.id != "car" }.reduce(0) { $0 + StaffPerks.monthlyCost(co, $1, currency: w.currency(co)) }
            let cash = co.cash
            StaffPerks.weekly(&s, data: d)
            let paid = cash - s.companies[i].cash
            XCTAssertGreaterThan(monthly, 0)
            XCTAssertEqual(paid, (monthly * 12 / 52 * (1 + k.employerOnCost(monthlyWage: k.medianMonthlyWage))).rounded(), accuracy: 1)
        }
    }

    func testInflationIndexGrowsByTheWeeksRate() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        XCTAssertEqual(e.state.economy.inflationIndex, 1, "the reference economy starts at 1")
        e.update { s, d, _ in
            for _ in 0..<5 {
                let before = s.economy.inflationIndex
                WorldWeek.economy(&s, data: d)
                XCTAssertEqual(s.economy.inflationIndex, before * pow(1 + s.economy.inflation, 1.0 / 52), accuracy: 1e-12)
            }
            XCTAssertEqual(World(state: s, data: d).inflationIndex, s.economy.inflationIndex)
        }
    }

    func testSalmonSmoltIsStockUntilHarvest() throws {
        var e = try SpecialTradesTests.engine("NO", seed: 5)
        let id = SpecialTradesTests.start(&e, "salmon", extra: 200_000_000)
        for _ in 0..<(7 * 80) where (e.state.company(id)?.value("fm")["coh"].array.isEmpty ?? true) { e.nextDay() }
        for _ in 0..<7 { e.nextDay() }
        let co = e.state.company(id)!
        let cohorts = co.value("fm")["coh"].array
        XCTAssertFalse(cohorts.isEmpty)
        let carried = cohorts.reduce(0) { $0 + $1["cost"].double }
        XCTAssertGreaterThan(carried, 0)
        XCTAssertEqual(co.inventory, carried, accuracy: 5, "the cohorts' cost is the company's stock")
        XCTAssertEqual(co.books.year["cogs"] ?? 0, 0, accuracy: 1, "nothing is expensed before the harvest")
        XCTAssertGreaterThan(co.inventory, 0)
    }

    func testClubSaleWritesOffTheSoldPlayersBookValueOnce() throws {
        var e = try SpecialTradesTests.engine("NO", seed: 11)
        guard case .ok(let id) = e.foundClub(countryCode: "NO") else { return XCTFail("club") }
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var fm = s.companies[i].value("fm")
            fm["sq"] = 10; fm["book"] = 300; fm["amort"] = .array([.object(["a": 10, "left": 30])])
            s.companies[i].set("fm", fm)
            s.addMessage(kind: "ask", from: "Club", title: "Bid", body: "", companyID: id, tone: "n", status: "open", options: [.option("Sell"), .option("Keep")],
                         action: "club24", data: .object(["who": "A", "to": "B", "fee": 500, "pts": 5, "xw": 0.01]), expiresWeek: s.week + 2)
            s.companies[i].books.week = [:]
            FootballModel.answerBid(&s, message: s.inbox.last!, option: 0)
            let fm2 = s.companies[i].value("fm")
            XCTAssertEqual(fm2["book"].double, 150, accuracy: 1e-9)
            XCTAssertEqual(fm2["amort"][0]["a"].double, 5, accuracy: 1e-9)
            XCTAssertEqual(s.companies[i].books.week["rev"] ?? 0, 350, accuracy: 1e-9, "fee less the written-off book value, booked once")
        }
    }

    func testRetentionIsHeldAsAReceivableUntilCompletionPlusDefectPeriod() throws {
        var (e, id) = try cafe()
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            let bd = d.catalog["construction"]!
            XCTAssertEqual(bd.trait("retention"), 0.05)
            XCTAssertEqual(d.catalog["plumber"]!.trait("retention") ?? 0, 0)
            let vr = 0.2, share = 1 - bd.businessShare
            s.companies[i].receivables = []
            var ctx = CompanyWeek.WeekContext(units: 1, rev: 1000, cogs: 0, D: 1, cap: 1, util: 0.5, price: 1000, paidDuringWeek: 950 * (1 + vr) * share)
            ctx.retentionHeld = [77: 50]
            let cash = s.companies[i].cash
            CompanyWeek.book(&s, i, bd, ctx, vat: vr, data: d)
            XCTAssertEqual(s.companies[i].cash - cash, 0, accuracy: 2, "the held-back share is not received")
            let held = s.companies[i].receivables.first { $0.flag("held") }
            XCTAssertNotNil(held)
            XCTAssertEqual(held?.amount ?? 0, 50 * (1 + vr), accuracy: 1.5)
            var done = CompanyWeek.WeekContext(units: 0, rev: 0, cogs: 0, D: 1, cap: 1, util: 0.5, price: 1, paidDuringWeek: 0)
            done.retentionReleased = [77]
            CompanyWeek.book(&s, i, bd, done, vat: vr, data: d)
            let r = s.companies[i].receivables.first { $0.int("pj") == 77 }!
            XCTAssertFalse(r.flag("held"))
            XCTAssertEqual(r.dueWeek, s.week + 26)
        }
    }
}
