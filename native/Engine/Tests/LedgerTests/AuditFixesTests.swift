import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Events
@testable import Simulation

/// Fixes from the connectivity and calculations audits (first steps, trophies, payroll on-cost, VAT penalty, held week money, inbox actions).
final class AuditFixesTests: XCTestCase {
    private func cafe(seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { XCTFail("start"); throw CocoaError(.fileReadUnknown) }
        return (e, id)
    }

    private func hireOne(_ e: inout GameEngine, _ id: Int, wage: Double? = nil) {
        var pid = 0, ask = 0.0
        e.update { s, d, _ in let p = Hiring.generateCandidate(role: "barista", company: s.company(id), tier: "mid", state: &s, data: d); pid = p.id; ask = p.askingMonthlyWage }
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: wage ?? ask * 1.2, terms: Hiring.Terms()), .ok)
    }

    // MARK: First steps and trophies

    func testFirstStepsCanAllCompleteInOrder() throws {
        var (e, id) = try cafe()
        let cur = e.homeCurrency
        func done(_ step: String) -> Bool { e.firstStepRewards?.first { $0.id == step }?.done == true }
        func claim(_ step: String) { XCTAssertTrue(done(step), "\(step) should be done"); XCTAssertNotNil(e.claimFirstStep(id: step), "\(step) reward"); _ = cur }
        XCTAssertFalse(done("week"), "no week has been played yet")
        claim("co")
        hireOne(&e, id)
        claim("staff")
        for _ in 0..<(7 * 12) where !(e.state.company(id)?.status == .open && done("week")) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
        XCTAssertEqual(e.state.company(id)?.status, .open)
        claim("open")
        XCTAssertTrue(done("week"), "the week report is stored under 'w' and counts")
        claim("week")
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].priceLevel = 1 }
        claim("sell")
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].set("mkt", .object(["flyer": .object(["b": 500])])) }
        claim("ad")
        e.update { s, _, _ in
            s.addMessage(kind: "decision", from: "Test", title: "Decide", body: "", companyID: id, tone: "n", status: "open", options: [.option("A", ""), .option("B", "")], expiresWeek: s.week + 3)
        }
        let mid = e.state.inbox.first { $0.title == "Decide" }!.id
        e.update { s, _, _ in  // an ignored decision that expired does not count
            let k = s.inbox.firstIndex { $0.id == mid }!; s.inbox[k].set("status", "done"); s.inbox[k].set("pick", -1); s.inbox[k].set("auto", 1)
        }
        XCTAssertFalse(done("inbox"), "an expired decision is not an answered one")
        e.update { s, _, _ in let k = s.inbox.firstIndex { $0.id == mid }!; s.inbox[k].set("pick", 0); s.inbox[k].set("auto", 0) }
        claim("inbox")
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].ownerMonthlySalary = 100_000 }
        claim("pay")
        e.update { s, _, _ in var c = s.companies[s.companyIndex(id)!]; c.monthlyHistory = [MonthRecord(monthIndex: 1, revenue: 10, profit: 5, cash: 10)]; s.companies[s.companyIndex(id)!] = c }
        claim("profit")
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].set("asst", .object(["npc": 1])) }
        claim("mgr")
        XCTAssertTrue(e.firstStepRewards?.allSatisfy { $0.claimed } == true)
    }

    func testEveryTrophyGroupIsOnTheWall() {
        let listed = Set(Trophies.groups.map { $0.id })
        for t in Trophies.all { XCTAssertTrue(listed.contains(t.group), "trophy \(t.id) is in group \(t.group), which the achievements screen does not list") }
        XCTAssertEqual(Trophies.all.filter { $0.group == "market" }.count, 9)
    }

    // MARK: Employer on-cost

    func testOneEmployerOnCostForPayrollAndQuotes() throws {
        let book = try CountryBook.bundled()
        for code in ["UK", "US", "DE", "PL", "NO"] {
            let c = book.countries.first { $0.code == code }!
            XCTAssertEqual(c.payrollFactor(monthlyWage: c.medianMonthlyWage), c.employerCostFactor, accuracy: 1e-9, code)
        }
        let uk = book.countries.first { $0.code == "UK" }!
        XCTAssertEqual(uk.employerOnCost(monthlyWage: 1000), uk.employerSocial + uk.employerPension + uk.employerInjury, accuracy: 1e-12)
    }

    func testMexicoPayrollFollowsTheContributionTableByWage() throws {
        let book = try CountryBook.bundled()
        let mx = book.countries.first { $0.code == "MX" }!
        let med = mx.medianMonthlyWage
        XCTAssertEqual(mx.payrollFactor(monthlyWage: med), mx.employerCostFactor, accuracy: 1e-9)
        XCTAssertLessThan(mx.payrollFactor(monthlyWage: med * 10), mx.employerCostFactor - 0.05, "capped contributions cost less on a high wage")
        // and the books use it
        var e = try GameEngine.newGame(countryCode: "MX", playerName: "T", seed: 5)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 200_000_000) else { return XCTFail("start") }
        hireOne(&e, id, wage: med * 10)
        let co = e.state.company(id)!
        let est = CompanyCosts.standingWeeklyPayroll(co, country: mx)
        let expected = co.staff.reduce(0.0) { $0 + $1.monthlyWage * 12 / 52 * (1 + mx.leaveWeeks / 52 * 0.3) * mx.payrollFactor(monthlyWage: $1.monthlyWage) }
        XCTAssertTrue(co.staff.contains { $0.monthlyWage > med * 5 })
        XCTAssertEqual(est, expected, accuracy: 1e-6)
    }

    func testPayrollEstimateIncludesLeaveCoverLikeTheAccrual() throws {
        var (e, id) = try cafe()
        hireOne(&e, id)
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            let country = World(state: s, data: d).country(s.companies[i])
            let est = Payday.weeklyWageCost(s.companies[i], country: country)
            let booked = CompanyCosts.wages(&s, companyIndex: i, d.catalog[s.companies[i].type]!, data: d)
            XCTAssertGreaterThan(est, 0)
            XCTAssertEqual(est, booked, accuracy: 1e-6, "the estimate and the accrual are the same function")
        }
    }

    // MARK: VAT penalty

    func testVatPenaltyIsChargedOnceOnTheNewUnpaidAmount() throws {
        var (e, id) = try cafe()
        e.update { s, d, c in
            let i = s.companyIndex(id)!
            let freq = max(1, c.country(of: s.companies[i], s).vatFilingMonths == 0 ? 2 : c.country(of: s.companies[i], s).vatFilingMonths)
            while GameCalendar.monthIndex(week: s.week) % freq != freq - 1 { s.week += 1 }
            Ledger.set(&s, .company(id), to: -1e9)   // no room to pay anything
            s.companies[i].vatBalance = 125_000
            s.companies[i].set("vatOver", 105_000)   // earlier arrears, penalty and interest included
            MonthEnd.closeMonth(&s, companyIndex: i, data: d, context: c)
            XCTAssertEqual(s.companies[i].vatBalance, 126_000, accuracy: 1, "5% of the 20,000 new unpaid VAT, not of the whole 125,000")
        }
    }

    // MARK: Week money held back

    /// Play until the company has money from this week still held back (the company trades, so its weekly change is not zero).
    private func playToHeldMoney(_ e: inout GameEngine, _ id: Int) {
        hireOne(&e, id)
        for _ in 0..<(7 * 30) {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if e.state.company(id)?.status == .open, e.state.day == 1, abs(Ledger.heldRemainders(e.state)[id] ?? 0) > 50 { return }
        }
    }

    func testHeldWeekMoneyIsSettledWhenACompanyIsWoundUp() throws {
        var (e, id) = try cafe()
        playToHeldMoney(&e, id)
        let held = Ledger.heldRemainders(e.state)[id] ?? 0
        XCTAssertNotEqual(held, 0, "part of the week's change is still held on day 1")
        let before = e.state.companies[e.state.companyIndex(id)!].cash
        XCTAssertTrue(e.windUpCompany(companyID: id))
        XCTAssertNil(Ledger.heldRemainders(e.state)[id], "nothing is left held for a company that is gone")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        _ = before
        for _ in 0..<7 { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertEqual(e.state.company(id)?.cash ?? 0, 0, accuracy: 1)
    }

    func testGapCheckShowsMoneyHeldForAGoneCompany() throws {
        var (e, id) = try cafe()
        playToHeldMoney(&e, id)
        XCTAssertNotEqual(Ledger.heldRemainders(e.state)[id] ?? 0, 0)
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].status = .sold }   // gone without settling
        XCTAssertFalse(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Inbox and subscriptions

    func testUnknownInboxActionIsNotMarkedAnswered() throws {
        var (e, id) = try cafe()
        e.update { s, _, _ in
            s.addMessage(kind: "ask", from: "Test", title: "Mystery", body: "", companyID: id, tone: "n", status: "open", options: [.option("Yes", "")], action: "nope99", data: .null, expiresWeek: s.week + 5)
        }
        let mid = e.state.inbox.first { $0.title == "Mystery" }!.id
        XCTAssertFalse(e.answer(messageID: mid, option: 0))
        XCTAssertEqual(e.state.inbox.first { $0.id == mid }?.status, "open")
    }

    func testPausedSoftwarePlansDoNotChargeWhileClosed() throws {
        var (e, id) = try cafe()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var eq = s.companies[i].value("eq"); eq["testsoft"] = .object(["sub": .object(["fee": 5200, "tier": 0])]); s.companies[i].set("eq", eq)
            s.companies[i].status = .open
        }
        func closedWeekCost(pause: Bool) -> Double {
            var g = e
            XCTAssertEqual(g.closeCompany(companyID: id, weeks: 4, pauseSubscriptions: pause), .ok)
            var cost = 0.0
            g.update { s, d, _ in
                let i = s.companyIndex(id)!
                let before = s.companies[i].books.total["oth"] ?? 0
                CompanyWeek.closedWeek(&s, i, d.catalog[s.companies[i].type]!, d)
                cost = (s.companies[i].books.total["oth"] ?? 0) - before
            }
            return cost
        }
        let paused = closedWeekCost(pause: true), running = closedWeekCost(pause: false)
        XCTAssertEqual(running - paused, 5200.0 * 12 / 52, accuracy: 1.5)
    }
}
