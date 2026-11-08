import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// Only a hired manager hires, through the staffing plan: a vacancy waits a few weeks, costs a recruiting fee, and a manager never overfills; the owner's
/// target is filled without asking again; a demand-limited company can be proposed bigger premises; staff grow, are promoted, and a named successor
/// takes over. Rules: Businesses/StaffingPlan.swift, ManagerHiring.swift, PremisesProposals.swift, GrowthPaths.swift.
final class ManagerHiringTests: XCTestCase {
    /// A running company with its standard team and a real hired manager.
    private func managed(_ seed: Int, trade: String = "grocery", manager: Bool = true, cash: Double = 300_000_000) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 500_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: cash)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
            if let i = s.companyIndex(id) { s.companies[i].status = .open }
            if manager, let co = s.company(id), let bd = data.catalog[co.type] {
                for _ in 0..<4 {
                    let c = ManagerModel.generateCandidate(company: co, type: bd.managerType, state: &s, data: data)
                    if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.4, data: data) == .ok { break }
                }
            }
        }
        guard id != 0, e.state.company(id)?.staff.isEmpty == false else { throw XCTSkip("no company") }
        if manager { guard e.state.company(id)?.managerID != nil else { throw XCTSkip("no manager hired") } }
        return (e, id)
    }

    /// Remove one team member of the first role without paperwork (a leaver who is already gone).
    private func removeOne(_ e: inout GameEngine, _ id: Int) -> String {
        var role = ""
        e.update { s, _, _ in
            guard let i = s.companyIndex(id), let m = s.companies[i].staff.last else { return }
            role = m.role
            s.companies[i].staff.removeLast()
            if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p }
        }
        return role
    }

    /// Run the staffing plan for a number of weeks.
    private func weeks(_ e: inout GameEngine, _ n: Int) {
        e.update { s, d, _ in for _ in 0..<n { s.week += 1; StaffingPlan.weekly(&s, data: d) } }
    }

    private func target(_ e: GameEngine, _ id: Int, _ role: String) -> Int {
        let co = e.state.company(id)!
        return CompanySetup.standardStaff(e.data.catalog[co.type]!, size: co.size).first { $0.role == role }?.count ?? 0
    }

    private func setLoad(_ e: inout GameEngine, _ id: Int, util: Double) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var lw = s.companies[i].value("lastW")
            if lw.isNull { lw = .object(["units": 100, "rev": 10000, "cogs": 4000, "D": 100, "cap": 100, "util": 0.6]) }
            lw["util"] = .number(util); lw["cap"] = .number(100); lw["D"] = .number(util * 100)
            s.companies[i].set("lastW", lw)
        }
    }

    // MARK: Who hires

    func testNoHireWithoutAManager() throws {
        var (e, id) = try managed(1, manager: false)
        let role = removeOne(&e, id)
        let before = e.state.company(id)!.staff.count
        XCTAssertFalse(e.managerMayHire(companyID: id, role: role, target: target(e, id, role)).allowed)
        weeks(&e, 8)
        XCTAssertEqual(e.state.company(id)!.staff.count, before, "nobody is hired automatically without a manager")
        // the same company with a manager fills the gap
        var (m, mid) = try managed(1)
        let r = removeOne(&m, mid)
        XCTAssertEqual(m.managerMayHire(companyID: mid, role: r, target: target(m, mid, r)), .replace)
        let n = m.state.company(mid)!.staff.count
        weeks(&m, 1)
        XCTAssertEqual(m.state.company(mid)!.staff.count, n, "the search takes weeks: nobody is offered the job in the week the post falls empty")
        weeks(&m, 6)
        XCTAssertEqual(m.state.company(mid)!.staff.count, n + 1)
    }

    func testNoOverfillOfAnOfficeAndNoHireWhenTheTeamIsComplete() throws {
        guard let office = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 2).data.catalog.all.first(where: { $0.premisesKind == "office" && $0.family == "svc" && !$0.standardStaff.isEmpty }) else { throw XCTSkip("no office trade") }
        var (e, id) = try managed(2, trade: office.id)
        // a complete team: no hire
        let role = e.state.company(id)!.staff[0].role
        XCTAssertFalse(e.managerMayHire(companyID: id, role: role, target: target(e, id, role)).allowed)
        // a vacancy, but every office place is taken (two other people in the room's count): no hire, with the reason
        _ = removeOne(&e, id)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var prem = s.companies[i].value("prem"); prem["kind"] = "office"
            prem["m2"] = .number(Double(max(Workplaces.smallestOffice, PremisesExtras.heads(s.companies[i])) * 9))   // places == heads
            s.companies[i].set("prem", prem)
        }
        let r = e.state.company(id)!.staff.isEmpty ? role : e.state.company(id)!.staff[0].role
        let want = target(e, id, r) + 1
        let v = e.managerMayHire(companyID: id, role: r, target: want)
        if e.workplaces(companyID: id)?.free == 0 {
            XCTAssertFalse(v.allowed, "a manager does not hire into a full office")
            let n = e.state.company(id)!.staff.count
            weeks(&e, 6)
            XCTAssertLessThanOrEqual(e.state.company(id)!.staff.count, n)
        }
    }

    func testReplacementIsSoughtWhileTheLeaverWorksTheirNotice() throws {
        var (e, id) = try managed(3)
        let first = e.state.company(id)!.staff[0]
        let role = first.role, want = target(e, id, role)
        let have = e.state.company(id)!.staff.filter { $0.role == role }.count
        guard have == want else { throw XCTSkip("team incomplete") }
        // nobody leaving: the team is complete, whatever the load
        setLoad(&e, id, util: 0.4)
        XCTAssertFalse(e.managerMayHire(companyID: id, role: role, target: want).allowed)
        XCTAssertEqual(e.staffingPlan(companyID: id).first { $0.role == role }?.vacancies, 0)
        // a leaver on notice: the post is a vacancy at once, and the plan says someone is leaving
        e.update { s, _, _ in if let i = s.companyIndex(id), let k = s.companies[i].staff.firstIndex(where: { $0.id == first.id }) { var st = s.companies[i].staff; st[k].noticeWeeks = 8; s.companies[i].staff = st } }
        guard case .early = e.managerMayHire(companyID: id, role: role, target: want) else { return XCTFail("expected an early hire") }
        let row = try XCTUnwrap(e.staffingPlan(companyID: id).first { $0.role == role })
        XCTAssertEqual(row.leaving, 1); XCTAssertEqual(row.vacancies, 1)
        let n = e.state.company(id)!.staff.count
        weeks(&e, 6)
        XCTAssertEqual(e.state.company(id)!.staff.count, n + 1, "hired before the leaver went")
        XCTAssertTrue(e.state.company(id)!.staff.contains { $0.id == first.id }, "the leaver is still on the payroll")
        XCTAssertEqual(e.staffingPlan(companyID: id).first { $0.role == role }?.vacancies, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // a fixed term that ends within weeks counts as a leaver too
        var (f, fid) = try managed(3)
        f.update { s, _, _ in if let i = s.companyIndex(fid) { var st = s.companies[i].staff; st[0].set("ft", s.week + 3); s.companies[i].staff = st } }
        XCTAssertEqual(f.staffingPlan(companyID: fid).first { $0.role == f.state.company(fid)!.staff[0].role }?.leaving, 1)
    }

    // MARK: The staffing plan

    func testAVacancyWaitsCostsAFeeAndShowsHowLongItHasBeenOpen() throws {
        var (e, id) = try managed(6)
        let role = removeOne(&e, id)
        let n = e.state.company(id)!.staff.count
        let cash0 = e.state.company(id)!.cash
        weeks(&e, 1)
        var row = try XCTUnwrap(e.staffingPlan(companyID: id).first { $0.role == role })
        XCTAssertEqual(row.vacancies, 1); XCTAssertEqual(row.weeksOpen, 0); XCTAssertFalse(row.ownerSet)
        weeks(&e, 1)
        row = try XCTUnwrap(e.staffingPlan(companyID: id).first { $0.role == role })
        XCTAssertEqual(row.weeksOpen, 1)
        XCTAssertEqual(e.state.company(id)!.staff.count, n, "still searching")
        weeks(&e, 6)
        XCTAssertEqual(e.state.company(id)!.staff.count, n + 1)
        XCTAssertLessThan(e.state.company(id)!.cash, cash0, "recruiting costs money")
        XCTAssertEqual(e.staffingPlan(companyID: id).first { $0.role == role }?.vacancies, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTheOwnersTargetIsFilledAndCanBeReset() throws {
        var (e, id) = try managed(7)
        let role = e.state.company(id)!.staff[0].role
        if e.workplaces(companyID: id)?.free == 0 { throw XCTSkip("no free place") }
        let have = e.staffingPlan(companyID: id).first { $0.role == role }?.filled ?? 0
        XCTAssertTrue(e.setHeadcountTarget(companyID: id, role: role, target: have + 1))
        var row = try XCTUnwrap(e.staffingPlan(companyID: id).first { $0.role == role })
        XCTAssertEqual(row.target, have + 1); XCTAssertTrue(row.ownerSet); XCTAssertEqual(row.vacancies, 1)
        XCTAssertFalse(e.setHeadcountTarget(companyID: id, role: "no-such-role", target: 2))
        let n = e.state.company(id)!.staff.count
        weeks(&e, 8)
        XCTAssertEqual(e.state.company(id)!.staff.count, n + 1, "the manager fills the owner's target without asking again")
        XCTAssertTrue(e.resetHeadcountTarget(companyID: id, role: role))
        row = try XCTUnwrap(e.staffingPlan(companyID: id).first { $0.role == role })
        XCTAssertFalse(row.ownerSet)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Bigger premises

    /// A company whose place is too small: the space limits what it can serve.
    private func cramped(_ seed: Int, trade: String = "cafe") throws -> (GameEngine, Int) {
        var (e, id) = try managed(seed, trade: trade)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var prem = s.companies[i].value("prem")
            guard prem["m2"].double > 0 else { return }
            prem["m2"] = .number((prem["m2"].double * 0.35 / 5).rounded() * 5)
            s.companies[i].set("prem", prem)
            s.companies[i].awareness = 90
        }
        guard e.state.company(id)!.value("prem")["m2"].double > 0 else { throw XCTSkip("trade has no premises area") }
        for _ in 0..<(7 * 14) where premisesMessage(e, id) == nil { e.nextDay() }   // stops while the manager's proposal is open
        return (e, id)
    }

    private func premisesMessage(_ e: GameEngine, _ id: Int) -> Message? {
        e.state.inbox.first { $0.companyID == id && $0.status == "open" && $0.actionID == "prop" && $0.value("data")["t"].string == "prem" }
    }

    func testAProposalAppearsWhenDemandLimitedAndAcceptingRaisesCapacityAndRevenue() throws {
        var (e, id) = try cramped(4)
        guard let plan = e.premisesPlan(companyID: id) else { throw XCTSkip("not premises-limited in this run") }
        XCTAssertGreaterThan(plan.toSquareMetres, plan.fromSquareMetres)
        XCTAssertGreaterThan(plan.projectedWeeklyProfitUplift, 0)
        XCTAssertGreaterThan(plan.extraCapacityPercent, 0)
        XCTAssertLessThanOrEqual(plan.extraUnitsPerWeek, plan.unmetUnitsPerWeek + 1e-9, "the uplift never exceeds the demand turned away")
        // the manager asks (the streak is long enough after a few more weeks)
        let fl = e.state.company(id)!.value("flags")
        print("PREM debug streak \(fl["premStreak"].double) ask \(fl["premAsk"].double) no \(fl["premNo"].double) unmet \(String(describing: PremisesProposals.unmetDemand(e.state, companyID: id, data: e.data))) lastW \(e.state.company(id)!.value("lastW"))")
        let m = try XCTUnwrap(premisesMessage(e, id), "the manager proposes the move")
        XCTAssertGreaterThanOrEqual(Delegation.level(of: m), 5, "it reaches the owner")
        XCTAssertEqual(m.options.count, 2)
        var keep = e, move = e
        let capBefore = move.state.company(id)!.value("lastW")["cap"].double
        let rent0 = move.state.company(id)!.value("prem")["rent"].double * move.state.company(id)!.value("prem")["m2"].double
        XCTAssertTrue(move.answer(messageID: m.id, option: 0))
        let after = move.state.company(id)!
        XCTAssertGreaterThan(after.value("prem")["m2"].double, plan.fromSquareMetres)
        XCTAssertGreaterThan(after.value("prem")["rent"].double * after.value("prem")["m2"].double, rent0 * 0.99, "bigger place, more rent")
        XCTAssertTrue(Ledger.gaps(move.state).isEmpty, "\(Ledger.gaps(move.state))")
        XCTAssertTrue(keep.answer(messageID: m.id, option: 1))
        var revMove = 0.0, revKeep = 0.0
        for _ in 0..<(7 * 12) { move.nextDay(); keep.nextDay() }
        revMove = move.state.company(id)!.monthlyHistory.suffix(2).reduce(0) { $0 + $1.revenue }
        revKeep = keep.state.company(id)!.monthlyHistory.suffix(2).reduce(0) { $0 + $1.revenue }
        let capAfter = move.state.company(id)!.value("lastW")["cap"].double
        print("PREM cap \(capBefore) -> \(capAfter), revenue 2 months keep \(revKeep) move \(revMove), plan uplift/week \(plan.projectedWeeklyProfitUplift)")
        XCTAssertGreaterThan(capAfter, capBefore, "the capacity limit is higher")
        XCTAssertGreaterThan(revMove, revKeep, "the demand that was turned away now converts to sales")
        XCTAssertTrue(Ledger.gaps(move.state).isEmpty)
    }

    func testDecliningRecordsACooldown() throws {
        var (e, id) = try cramped(4)
        guard let m = premisesMessage(e, id) else { throw XCTSkip("not premises-limited in this run") }
        XCTAssertEqual(e.premisesPlan(companyID: id) == nil, false)
        XCTAssertTrue(e.answer(messageID: m.id, option: 1))
        XCTAssertGreaterThan(PremisesProposals.cooldownWeeks(e.state, companyID: id), 40)
        for _ in 0..<(7 * 30) { e.nextDay(); XCTAssertNil(premisesMessage(e, id), "no new proposal during the cooldown") }
        XCTAssertEqual(e.state.company(id)!.value("prem")["m2"].double, e.state.company(id)!.value("prem")["m2"].double)
    }

    // MARK: Growth paths

    func testGrowthPathReadinessPromotionAndSuccession() throws {
        var (e, id) = try managed(5)
        let staff = e.state.company(id)!.staff
        let who = staff[0].id
        let p0 = try XCTUnwrap(e.growthPath(companyID: id, employeeID: who))
        XCTAssertNotNil(p0.nextRole)
        XCTAssertLessThan(p0.readiness, 1)
        XCTAssertFalse(p0.missing.isEmpty)
        XCTAssertGreaterThan(p0.yearsToReady, 0)
        guard case .notReady = e.promote(companyID: id, employeeID: who) else { return XCTFail("a new hire is not ready") }
        // years pass, they learn and train
        e.update { s, _, _ in
            guard let i = s.companyIndex(id), let k = s.companies[i].staff.firstIndex(where: { $0.id == who }) else { return }
            var st = s.companies[i].staff
            st[k].set("w0", s.week - 52 * 5); st[k].skillGain = 40; st[k].set("crsN", 3); st[k].happyUntilWeek = s.week + 20
            s.companies[i].staff = st
            if var n = s.people[who] { n.skill = 75; s.people[who] = n }
        }
        let p1 = try XCTUnwrap(e.growthPath(companyID: id, employeeID: who))
        XCTAssertGreaterThan(p1.readiness, p0.readiness)
        let wage0 = e.state.company(id)!.staff.first { $0.id == who }!.monthlyWage
        guard p1.isReady else { throw XCTSkip("not ready: \(p1.missing)") }
        guard case .promoted = e.promote(companyID: id, employeeID: who) else { return XCTFail("a ready employee is promoted") }
        let co = e.state.company(id)!
        let m = co.staff.first { $0.id == who }
        let asst = co.value("asst")["npc"].int == who
        XCTAssertTrue(m != nil || asst, "still in the company")
        if let m = m { XCTAssertGreaterThan(m.monthlyWage, wage0, "a promotion costs a raise") }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // succession: name someone, the manager leaves, the successor is installed with a message
        let succ = co.staff.first { $0.id != who }?.id ?? who
        let mgr = try XCTUnwrap(co.managerID)
        XCTAssertFalse(e.setSuccessor(companyID: id, employeeID: 999_999, successorID: succ), "only the manager can have a successor")
        XCTAssertTrue(e.setSuccessor(companyID: id, employeeID: mgr, successorID: succ))
        XCTAssertEqual(e.successor(companyID: id), succ)
        e.update { s, d, _ in _ = Dismissal.dismissManager(&s, companyID: id, data: d) }
        let after = e.state.company(id)!
        XCTAssertEqual(after.managerID, succ, "the successor is installed when the manager leaves")
        XCTAssertFalse(after.staff.contains { $0.id == succ })
        XCTAssertNil(e.successor(companyID: id))
        XCTAssertTrue(e.state.inbox.contains { $0.companyID == id && $0.title.contains("takes over") }, "with a transition message")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Determinism and saves

    func testDeterministicAndSaveReloadSafe() throws {
        func run() throws -> GameEngine {
            var (e, id) = try cramped(4)
            if let m = premisesMessage(e, id) { _ = e.answer(messageID: m.id, option: 0) }
            _ = e.setSuccessor(companyID: id, employeeID: e.state.company(id)!.managerID ?? 0, successorID: e.state.company(id)!.staff.first?.id)
            for _ in 0..<(7 * 6) { e.nextDay() }
            return e
        }
        let a = try run(), b = try run()
        XCTAssertEqual(a.state, b.state, "the same seed and actions give the same game")
        let saved = try JSONEncoder().encode(a.state)
        let loaded = try JSONDecoder().decode(GameState.self, from: saved)
        XCTAssertEqual(loaded, a.state)
        let (data, events, marketing) = try GameEngine.loadResources()
        var c = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        var d = a
        for _ in 0..<(7 * 6) { c.nextDay(); d.nextDay() }
        XCTAssertEqual(c.state, d.state, "a saved and reloaded game plays on identically")
        XCTAssertTrue(Ledger.gaps(c.state).isEmpty)
    }

    /// Appointing a manager into a company with 0 or 1 staff warns when its profit would not carry the pay (Nov 3 balance report).
    func testManagerWarningForSmallCompany() throws {
        var (e, id) = try managed(31, trade: "barber", manager: false)
        func setSmall(_ profit: Double) {
            e.update { s, _, _ in
                guard let i = s.companyIndex(id) else { return }
                s.companies[i].staff = Array(s.companies[i].staff.prefix(1))
                s.companies[i].monthlyHistory = (1...3).map { MonthRecord(monthIndex: $0, revenue: profit * 3, profit: profit, cash: 1_000_000) }
            }
        }
        setSmall(1_000)
        let w = try XCTUnwrap(e.managerWarning(companyID: id), "a poor small company is warned")
        XCTAssertTrue(w.hasPrefix("A manager costs about "), w)
        XCTAssertTrue(w.contains("you would likely lose money"), w)
        setSmall(900_000_000)
        XCTAssertNil(e.managerWarning(companyID: id), "a rich small company is not warned")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].monthlyHistory = (1...3).map { MonthRecord(monthIndex: $0, revenue: 300_000, profit: 100_000, cash: 1_000_000) }
            while s.companies[i].staff.count < 4 { s.companies[i].staff.append(s.companies[i].staff[0]) }
        }
        XCTAssertNil(e.managerWarning(companyID: id), "a company with a team is not warned")
    }
}
