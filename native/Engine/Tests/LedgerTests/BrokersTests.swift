import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation
@testable import Businesses

final class BrokersTests: XCTestCase {
    private let ids = ["travel", "insbroker", "finbroker"]

    private func game(_ trade: String, seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 900_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) else { return }
            id = i
            _ = Payments.injectCash(&s, companyID: id, amount: 6_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        if id == 0 { throw XCTSkip("no company") }
        return (e, id)
    }

    private func noGaps(_ e: GameEngine, _ what: String) { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(what): \(Ledger.gaps(e.state))") }

    func testTradesAreWiredIntoTheTables() throws {
        let cat = try TradeCatalog.bundled()
        let docs = cat.tables.raw["DOCS"], kinds = cat.tables.raw["EQ_KINDS"]
        for id in ids {
            let t = try XCTUnwrap(cat[id], id)
            XCTAssertTrue(cat.order.contains(id), "\(id) is in the menu")
            XCTAssertEqual(t.family, "svc")
            XCTAssertGreaterThan(t.normalDemand, 0)
            for s in t.standardStaff { XCTAssertNotNil(cat.tables.roles[s.role], "\(id) role \(s.role)") }
            for d in t.documents { XCTAssertFalse(docs[d].isNull, "\(id) document \(d)") }
            for e in t.equipment { XCTAssertFalse(kinds[id][e.id].isNull, "\(id) equipment kind \(e.id)") }
            XCTAssertTrue(t.documents.contains("professional_indemnity"), "\(id) needs indemnity cover")
            XCTAssertTrue(t.equipment.contains { $0.id == "crm" && $0.isRequired }, "\(id) needs a CRM")
            XCTAssertTrue(NewItemOptions.catalog[id]?.count ?? 0 >= 6, "\(id) item catalogue")
        }
        XCTAssertTrue(try XCTUnwrap(cat["travel"]).equipment.contains { $0.id == "bs" && $0.isRequired })
        XCTAssertTrue(try XCTUnwrap(cat["insbroker"]).equipment.contains { $0.id == "cmp" && $0.isRequired })
        XCTAssertTrue(try XCTUnwrap(cat["travel"]).documents.contains("travel_bond"))
        for (trade, role) in [("travel", "tcons"), ("insbroker", "insadv"), ("finbroker", "mortadv")] {
            XCTAssertTrue(cat.tables.salesRoles.contains(role))
            XCTAssertEqual(PayPlans.modes(role: role, trade: trade, salesRoles: cat.tables.salesRoles), ["fix", "mix", "com"])
        }
    }

    func testCommissionTermsAreRealistic() {
        let cfg = Brokers.config["trades"]
        for l in cfg["travel"]["lines"].array {
            let r = l["com"]
            if l["id"].string == "pkg" { XCTAssertEqual(r[0].double, 0.08); XCTAssertEqual(r[1].double, 0.12) }
            else { XCTAssertEqual(r[0].double, 0.05); XCTAssertEqual(r[1].double, 0.09) }
        }
        for l in cfg["insbroker"]["lines"].array {
            XCTAssertGreaterThanOrEqual(l["com"][0].double, 0.10); XCTAssertLessThanOrEqual(l["com"][1].double, 0.20)
            XCTAssertGreaterThanOrEqual(l["ren"][0].double, 0.05); XCTAssertLessThanOrEqual(l["ren"][1].double, 0.10)
            XCTAssertLessThan(l["retention"].double, 1)
        }
        for l in cfg["finbroker"]["lines"].array {
            XCTAssertGreaterThanOrEqual(l["com"][0].double, 0.005); XCTAssertLessThanOrEqual(l["com"][1].double, 0.01)
            XCTAssertGreaterThan(l["decline"].double, 0)
        }
    }

    func testTravelPaysAfterTheTripAndCancelledBookingsEarnOnlyTheFee() throws {
        var (e, id) = try game("travel")
        e.update { s, data, _ in
            s.week = 20
            let i = s.companyIndex(id)!
            var b = Brokers.Book()
            b.deals = [Brokers.Deal(id: 1, line: "pkg", due: s.week, cancelWeek: 0, value: 30_000, commission: 3_000, fee: 0, supplier: 0, procuration: 0, trail: 0, sold: 0),
                       Brokers.Deal(id: 2, line: "pkg", due: s.week + 9, cancelWeek: 0, value: 30_000, commission: 3_000, fee: 0, supplier: 0, procuration: 0, trail: 0, sold: 0),
                       Brokers.Deal(id: 3, line: "pkg", due: s.week + 5, cancelWeek: s.week, value: 20_000, commission: 2_000, fee: 0, supplier: 0, procuration: 0, trail: 0, sold: 0)]
            let cfg = Brokers.config["trades"]["travel"]
            let bd = data.catalog["travel"]!
            let rev = Brokers.settle(&s, i, bd, cfg, &b, scale: 1, quality: 0.5, active: [])
            XCTAssertEqual(rev, 3_000 + 20_000 * cfg["cancelFee"].double, accuracy: 0.001)
            XCTAssertEqual(b.deals.map { $0.id }, [2])
            XCTAssertEqual(b.stat["cancel"], 1)
        }
    }

    func testOwnAirlinePaysTheCommissionWithRealMoney() throws {
        var (e, id) = try game("travel")
        var airline = 0
        e.update { s, data, ctx in
            guard case .success(let a) = CompanySetup.create(&s, tradeID: "airline", cityID: s.player.cityID, data: data, context: ctx) else { return }
            airline = a
            _ = Payments.injectCash(&s, companyID: a, amount: 5_000_000)
            s.companies[s.companyIndex(a)!].status = .open
        }
        guard airline != 0 else { throw XCTSkip("no airline") }
        e.update { s, data, _ in
            let i = s.companyIndex(id)!, ai = s.companyIndex(airline)!
            XCTAssertEqual(Brokers.ownSupplier(s, buyer: s.companies[i], trade: "airline"), airline)
            // Both companies draw on the one account, so each side is read from its own cash flow.
            func flow(_ id: Int) -> Double { s.cashFlow["co\(id)"] ?? 0 }
            let agency0 = flow(id), air0 = flow(airline), account = s.cash
            var b = Brokers.Book()
            b.deals = [Brokers.Deal(id: 1, line: "flt", due: s.week, cancelWeek: 0, value: 7_000, commission: 490, fee: 0, supplier: airline, procuration: 0, trail: 0, sold: 0)]
            let rev = Brokers.settle(&s, i, data.catalog["travel"]!, Brokers.config["trades"]["travel"], &b, scale: 1, quality: 0.5, active: [])
            XCTAssertEqual(rev, 0, "the airline's payment is booked at once, not through the week's takings")
            XCTAssertEqual(flow(id) - agency0, 490, accuracy: 0.5)
            XCTAssertEqual(air0 - flow(airline), 490, accuracy: 0.5)
            XCTAssertEqual(s.cash, account, accuracy: 0.5, "money between two own companies leaves the account unchanged")
        }
        noGaps(e, "airline pays commission")
    }

    func testInsuranceFirstYearThenRenewalWithClawbackAndLapses() throws {
        var (e, id) = try game("insbroker")
        e.update { s, data, _ in
            let i = s.companyIndex(id)!
            let cfg = Brokers.config["trades"]["insbroker"]
            let bd = data.catalog["insbroker"]!
            var b = Brokers.Book()
            b.cohorts = [Brokers.Cohort(line: "motor", start: s.week - 26, count: 100, premium: 700_000, first: 84_000, recurring: 42_000, index: s.economy.inflationIndex)]
            let cash0 = s.companies[i].cash
            let rev = Brokers.settleInsurance(&s, i, cfg, &b, quality: 0.5, active: [])
            XCTAssertEqual(rev, 0)
            let f = 0.07 / 52
            XCTAssertEqual(b.cohorts[0].count, 100 * (1 - f), accuracy: 1e-9)
            XCTAssertEqual(cash0 - s.companies[i].cash, 84_000 * f * 0.5, accuracy: 1.0, "unearned half of the commission on the cancelled share is clawed back")
            XCTAssertGreaterThan(b.stat["claw"] ?? 0, 0)
            b.cohorts = [Brokers.Cohort(line: "motor", start: s.week - 52, count: 100, premium: 700_000, first: 0, recurring: 42_000, index: s.economy.inflationIndex)]
            let renewed = Brokers.settleInsurance(&s, i, cfg, &b, quality: 0.5, active: [])
            XCTAssertEqual(renewed, 42_000 * 0.80, accuracy: 0.01)
            XCTAssertEqual(b.cohorts[0].count, 80, accuracy: 1e-9)
            _ = bd
        }
        noGaps(e, "insurance book")
    }

    func testLoansPayTrailAndEarlyRepaymentClawsBack() throws {
        var (e, id) = try game("finbroker")
        e.update { s, data, _ in
            let i = s.companyIndex(id)!
            let cfg = Brokers.config["trades"]["finbroker"]
            var b = Brokers.Book()
            b.cohorts = [Brokers.Cohort(line: "mort", start: s.week - 13, count: 10, premium: 30_000_000, first: 200_000, recurring: 60_000, index: 1)]
            let cash0 = s.companies[i].cash
            let rev = Brokers.settleLoans(&s, i, cfg, &b)
            XCTAssertGreaterThan(rev, 14_000, "a quarter of the yearly trail")
            XCTAssertLessThan(rev, 15_100)
            XCTAssertGreaterThan(cash0 - s.companies[i].cash, 0, "early repayment claws back")
            XCTAssertLessThan(b.cohorts[0].count, 10)
        }
        noGaps(e, "loan book")
    }

    func testFinanceApplicationsAreDeclinedMoreWhenMoneyIsDear() throws {
        var (e, id) = try game("finbroker")
        var cheap = 0.0, dear = 0.0
        e.update { s, data, _ in
            let co = s.companies[s.companyIndex(id)!]
            let cfg = Brokers.config["trades"]["finbroker"]
            let line = cfg["lines"][3]
            for (rate, which) in [(0.02, 0), (0.09, 1)] {
                s.economy.policyRate = rate
                var b = Brokers.Book()
                var r = HashedRandom("probe")
                for _ in 0..<2000 { _ = Brokers.place(&s, co, data.catalog["finbroker"]!, cfg, line, &b, scale: 1, quality: 0.5, active: [], &r) }
                if which == 0 { cheap = b.stat["decl"] ?? 0 } else { dear = b.stat["decl"] ?? 0 }
            }
        }
        XCTAssertGreaterThan(dear, cheap)
        XCTAssertGreaterThan(cheap, 400, "about a quarter are declined")
    }

    func testEndToEndTwoYears() throws {
        let seeds = (ProcessInfo.processInfo.environment["LEDGER_BROKERS_SEEDS"]?.split(separator: ",").compactMap { Int($0) }) ?? [11]
        for trade in (ProcessInfo.processInfo.environment["LEDGER_BROKERS_COMPARE"]?.split(separator: ",").map(String.init) ?? ids) { for seed in seeds {
            var (e, id) = try game(trade, seed: seed)
            _ = e.openCompany(companyID: id)
            if let c = e.searchManagers(companyID: id)?.first { _ = e.hireManager(personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.2) }
            for _ in 0..<(2 * 52 * 7) {
                e.nextDay()
                for m in e.openDecisions where m.actionID.hasPrefix("pay29") || ["prop", "mgrraise", "mgrpoach", "staffx"].contains(m.actionID) { e.answer(messageID: m.id, option: 0) }
                if let co = e.state.company(id), co.status.isLive, co.cash < -50_000 { e.update { s, _, _ in _ = Payments.injectCash(&s, companyID: id, amount: -co.cash + 100_000) } }
            }
            let co = try XCTUnwrap(e.state.company(id))
            let h = co.monthlyHistory
            let y1 = h.prefix(12), y2 = h.suffix(12)
            let sum = Brokers.summary(co, week: e.state.week)
            print(String(format: "BROKERS seed %d ", seed), terminator: "")
            print(String(format: "BROKERS %@ status=%@ year1 revenue %.0f profit %.0f | year2 revenue %.0f profit %.0f | cash %.0f | placed %.0f cancelled %.0f declined %.0f | in force %.0f book %.0f recurring/yr %.0f pending %.0f clawed back %.0f",
                         trade, co.status.rawValue, y1.reduce(0) { $0 + $1.revenue }, y1.reduce(0) { $0 + $1.profit }, y2.reduce(0) { $0 + $1.revenue }, y2.reduce(0) { $0 + $1.profit },
                         co.cash, sum.placed, sum.cancelled, sum.declined, sum.inForce, sum.bookValue, sum.recurringYearly, sum.pendingCommission, sum.clawedBack))
            let lw = co.value("lastW")
            print(String(format: "BROKERS %@ last week: demand %.1f capacity %.1f units %.1f revenue %.0f; staff %d; weekly fixed costs calibrated %.0f", trade, lw["D"].double, lw["cap"].double, lw["units"].double, lw["rev"].double,
                         co.staff.count, e.data.catalog[trade]?.weeklyFixedCosts ?? 0))
            XCTAssertTrue(co.status == .open, "\(trade) survives: \(co.status)")
            XCTAssertGreaterThan(sum.placed, 100, "\(trade) placed business")
            XCTAssertGreaterThan(sum.commissionEarned, 0)
            if trade != "travel" { XCTAssertGreaterThan(sum.inForce, 0, "\(trade) has a book") }
            noGaps(e, "\(trade) after two years")
        } }
    }
}
