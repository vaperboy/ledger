import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class HiringRebuildTests: XCTestCase {
    private func company(_ seed: Int, trade: String) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: 100_000_000) else { throw XCTSkip("start") }
        return (e, id)
    }

    private func candidate(_ e: inout GameEngine, _ id: Int, role: String) -> Person {
        var p = Person(raw: [:])
        e.update { s, d, _ in p = Hiring.generateCandidate(role: role, company: s.company(id), faces: false, state: &s, data: d) }
        return p
    }

    private func hireOne(_ e: inout GameEngine, _ id: Int, role: String) throws -> Int {
        for _ in 0..<6 {
            let p = candidate(&e, id, role: role)
            if e.hire(personID: p.id, companyID: id, monthlyWage: p.askingMonthlyWage * 1.6) == .ok { return p.id }
        }
        throw XCTSkip("could not hire")
    }

    private func nextTradeWithOffice(_ e: GameEngine) throws -> String {
        guard let t = e.data.catalog.all.first(where: { $0.premisesKind == "office" && $0.family == "svc" }) else { throw XCTSkip("no office trade") }
        return t.id
    }

    func testOfficeCapacityIsDerivedFromSizeAndRefusesWhenFull() throws {
        let (e0, _) = try company(1, trade: "cafe")
        let trade = try nextTradeWithOffice(e0)
        var (e, id) = try company(1, trade: trade)
        XCTAssertEqual(Workplaces.places(kind: "office", squareMetres: 10), 2)
        XCTAssertEqual(Workplaces.places(kind: "office", squareMetres: 54), 6)
        XCTAssertNil(Workplaces.places(kind: "shop", squareMetres: 500))
        let used = e.workplaces(companyID: id)!.used
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var prem = s.companies[i].value("prem"); prem["kind"] = .string("office"); prem["m2"] = .number(Double(9 * (used + 1)))
            s.companies[i].set("prem", prem)
            s.companies[i].managerID = nil
        }
        var w = e.workplaces(companyID: id)!
        XCTAssertEqual(w.capacity, used + 1)
        XCTAssertEqual(w.free, 1)
        _ = try hireOne(&e, id, role: "recept")
        w = e.workplaces(companyID: id)!
        XCTAssertEqual(w.free, 0)
        let p = candidate(&e, id, role: "recept")
        let before = e.state.company(id)!.staff.count
        XCTAssertEqual(e.hire(personID: p.id, companyID: id, monthlyWage: p.askingMonthlyWage * 2), .refused)
        XCTAssertEqual(e.state.company(id)!.staff.count, before)
        XCTAssertNotNil(e.hireBlock(companyID: id))
        XCTAssertTrue(e.hireBlock(companyID: id)!.contains("No free desk"))
        XCTAssertTrue(e.hireBlock(companyID: id)!.contains("Move to bigger premises"))
        XCTAssertNil(e.hireBlock(companyID: id, role: "cleaner"))
        XCTAssertNil(e.hireBlock(companyID: id, role: "dev"))
        XCTAssertNotNil(e.hireBlock(companyID: id, role: "recept"))
        let desk = ManagerHiring.verdict(e.state, companyID: id, role: "recept", target: 9, data: e.data)
        if case .no(let why) = desk { XCTAssertFalse(why.isEmpty) }
        if case .no(let why) = ManagerHiring.verdict(e.state, companyID: id, role: "dev", target: 9, data: e.data) { XCTAssertFalse(why.contains("No free desk")) }
        let listing = CompanySetup.Listing(index: 0, name: "x", squareMetres: 45, rentFactor: 1, location: 1, landlord: "y")
        XCTAssertEqual(e.officeCapacity(forListing: listing, companyID: id), 5)
        let (shop, sid) = try company(2, trade: "cafe")
        XCTAssertNil(shop.workplaces(companyID: sid)!.capacity)
        XCTAssertNil(shop.workplaces(companyID: sid)!.free)
    }

    private func promiseSetup(manager: Bool) throws -> (GameEngine, Int, Int, Int) {
        var (e, id) = try company(3, trade: "cafe")
        let pid = try hireOne(&e, id, role: "barista")
        var promiseID = 0
        e.update { s, _, _ in
            StaffPromises.make(&s, companyID: id, personID: pid, draft: StaffPromises.Draft(.salaryReview, dueInWeeks: 1))
            promiseID = StaffPromises.promises(s, personID: pid).first?.id ?? 0
        }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        if manager {
            let m = candidate(&e, id, role: "manager")
            e.update { s, _, _ in
                s.people[m.id]?.employerID = id
                if let i = s.companyIndex(id) { s.companies[i].managerID = m.id }
            }
            e.setManagerBudget(companyID: id, budget: .normal)
        }
        return (e, id, pid, promiseID)
    }

    func testPromisesReadPerEmployeeWithPatience() throws {
        let (e, id, pid, prid) = try promiseSetup(manager: false)
        let list = e.promises(of: pid, companyID: id)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, prid)
        XCTAssertEqual(list[0].patienceLeft, PromiseReminders.maxWaits)
        XCTAssertEqual(list[0].status, "Pending")
        XCTAssertFalse(list[0].text.isEmpty)
        XCTAssertEqual(list[0].dueWeek, e.state.week + 1)
    }

    func testReminderGoesToOwnerWithoutManagerAndToManagerWithOne() throws {
        for withManager in [false, true] {
            var (e, id, pid, prid) = try promiseSetup(manager: withManager)
            let before = Set(e.state.inbox.map { $0.id })
            e.update { s, d, _ in PromiseReminders.weekly(&s, data: d) }
            let fresh = e.state.inbox.filter { !before.contains($0.id) && $0.actionID == PromiseReminders.action }
            XCTAssertEqual(fresh.count, 1, "one reminder")
            XCTAssertEqual(fresh.first?.status, "open")
            XCTAssertEqual(fresh.first?.value("data")["prid"].int, prid)
            XCTAssertEqual(fresh.first?.value("data")["pid"].int, pid)
            e.update { s, d, _ in PromiseReminders.weekly(&s, data: d) }
            XCTAssertEqual(e.state.inbox.filter { $0.actionID == PromiseReminders.action }.count, 1)
            let taken = e.routeFreshDecisions(fresh)
            if withManager {
                XCTAssertEqual(taken, 1)
                let m = e.state.inbox.first { $0.id == fresh[0].id }!
                XCTAssertEqual(m.status, "done")
                XCTAssertTrue(m.handledBy.contains("manager"), m.handledBy)
                XCTAssertEqual(e.promises(of: pid, companyID: id).first { $0.id == prid }?.status, "Fulfilled", "the manager keeps it")
            } else {
                XCTAssertEqual(taken, 0)
                XCTAssertEqual(e.state.inbox.first { $0.id == fresh[0].id }?.status, "open")
                XCTAssertEqual(e.state.inbox.first { $0.id == fresh[0].id }?.handledBy, "")
            }
        }
    }

    func testKeepItNowFulfilsAndAskToWaitMovesTheDateUntilPatienceRunsOut() throws {
        var (e, id, pid, prid) = try promiseSetup(manager: false)
        e.update { s, d, _ in PromiseReminders.weekly(&s, data: d) }
        let wageBefore = e.state.company(id)!.staff.first { $0.id == pid }!.monthlyWage
        var msg = e.state.inbox.first { $0.actionID == PromiseReminders.action }!
        XCTAssertEqual(msg.options.count, 2)
        XCTAssertTrue(e.answer(messageID: msg.id, option: 0))
        XCTAssertEqual(e.promises(of: pid, companyID: id).first { $0.id == prid }?.status, "Fulfilled")
        XCTAssertGreaterThan(e.state.company(id)!.staff.first { $0.id == pid }!.monthlyWage, wageBefore)

        (e, id, pid, prid) = try promiseSetup(manager: false)
        e.update { s, d, _ in PromiseReminders.weekly(&s, data: d) }
        msg = e.state.inbox.first { $0.actionID == PromiseReminders.action }!
        let due0 = e.promises(of: pid, companyID: id)[0].dueWeek
        XCTAssertTrue(e.answer(messageID: msg.id, option: 1))
        var p = e.promises(of: pid, companyID: id).first { $0.isOpen }!
        XCTAssertEqual(p.dueWeek, due0 + PromiseReminders.waitWeeks)
        XCTAssertEqual(p.patienceLeft, 1)
        XCTAssertEqual(p.status, "Pending")
        XCTAssertEqual(e.state.company(id)!.staff.first { $0.id == pid }!.int("denied"), 0)
        for _ in 0..<(7 * 3) { e.nextDay() }
        let again = e.state.inbox.filter { $0.actionID == PromiseReminders.action && $0.status == "open" }
        XCTAssertEqual(again.count, 1)
        XCTAssertTrue(e.answer(messageID: again[0].id, option: 1))
        p = e.promises(of: pid, companyID: id).first { $0.isOpen }!
        XCTAssertEqual(p.patienceLeft, 0)
        let m = e.state.company(id)?.staff.first { $0.id == pid }
        XCTAssertTrue(m == nil || m!.int("denied") > 0 || m!.noticeWeeks > 0)
        if m != nil {
            let r = e.askToWait(employeeID: pid, promiseID: p.id)
            XCTAssertEqual(r, .letSlide)
        }
    }

    func testJobAdCostsMoneyAndApplicantsComeOverTime() throws {
        var (e, id) = try company(4, trade: "cafe")
        let form = try XCTUnwrap(e.jobAdForm(companyID: id))
        XCTAssertFalse(form.companyName.isEmpty)
        XCTAssertTrue(form.orgNumber.hasPrefix("55"))
        XCTAssertEqual(form.orgNumber, e.jobAdForm(companyID: id)?.orgNumber)
        let roles = e.recommendedRoles(companyID: id)
        XCTAssertTrue(roles.contains { $0.isCore })
        XCTAssertTrue(roles.contains { !$0.isCore && !$0.effect.isEmpty })
        let fee = e.jobAdFee(companyID: id, role: "barista")
        XCTAssertGreaterThan(fee, 0)
        XCTAssertGreaterThan(e.jobAdFee(companyID: id, role: "lawyer"), fee, "a better-paid role costs more")
        let cash = e.state.company(id)!.cash
        let msgs = e.state.inbox.count
        guard case .posted(let paid, let expected) = e.postJobAd(companyID: id, role: "barista") else { return XCTFail("not posted") }
        XCTAssertEqual(paid, fee)
        XCTAssertEqual(cash - e.state.company(id)!.cash, fee, accuracy: 0.5)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertEqual(e.applicants(companyID: id).count, 0, "nobody at once")
        XCTAssertEqual(e.state.inbox.count, msgs)
        if case .posted = e.postJobAd(companyID: id, role: "barista") { XCTFail("double post") }
        var seenDay1 = 0
        for day in 1...(7 * 5) {
            e.nextDay()
            if day == 7 { seenDay1 = e.applicants(companyID: id).count }
        }
        let apps = e.applicants(companyID: id)
        XCTAssertEqual(apps.count, expected)
        XCTAssertLessThan(seenDay1, apps.count, "they keep arriving after the first week")
        let applied = e.state.inbox.filter { $0.title.hasSuffix("applied for Barista") || $0.title.contains(" applied for ") }
        XCTAssertEqual(applied.count, expected)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testJobAdNeedsNameAndRecord() throws {
        var (e, id) = try company(5, trade: "cafe")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].name = "" } }
        if case .missingRecord = e.postJobAd(companyID: id, role: "barista") {} else { XCTFail("must refuse without a name") }
    }

    func testSmallCompaniesGetFewerApplicantsThanBigOnes() throws {
        var small = 0, big = 0
        for seed in 10...14 {
            var (e, id) = try company(seed, trade: "cafe")
            let n0 = JobAds.expectedApplicants(e.state, e.state.company(id)!, data: e.data)
            small += n0
            e.update { s, d, _ in
                guard let i = s.companyIndex(id) else { return }
                for k in 0..<18 {
                    var p = Hiring.generateCandidate(role: "barista", company: s.companies[i], faces: false, state: &s, data: d)
                    p.employerID = id; s.people[p.id] = p
                    var m = StaffMember(raw: [:]); m.id = p.id; m.set("role", "barista"); m.monthlyWage = 1; m.hiredWeek = s.week - k
                    var st = s.companies[i].staff; st.append(m); s.companies[i].staff = st
                }
                s.companies[i].reputation = 80
            }
            big += JobAds.expectedApplicants(e.state, e.state.company(id)!, data: e.data)
            _ = e
        }
        XCTAssertGreaterThan(big, small * 2)
    }

    func testAgencyCostsMoreGivesSuggestionsNowAndTakesAShareOfPayForTwoYears() throws {
        var (e, id) = try company(6, trade: "cafe")
        let adFee = e.jobAdFee(companyID: id, role: "barista")
        let agencyFee = e.agencyFee(companyID: id, role: "barista")
        XCTAssertGreaterThanOrEqual(agencyFee, adFee * 7)
        XCTAssertEqual(e.hiringSearchOptions().map(\.mode), [.ads, .agency], "no network option for the player")
        let cash = e.state.company(id)!.cash
        guard case .engaged(let fee, let ids) = e.engageAgency(companyID: id, role: "barista") else { return XCTFail("not engaged") }
        XCTAssertEqual(fee, agencyFee)
        XCTAssertEqual(cash - e.state.company(id)!.cash, fee, accuracy: 0.5)
        XCTAssertEqual(ids.count, Agency.immediate)
        XCTAssertEqual(e.applicants(companyID: id).count, Agency.immediate)
        for _ in 0..<(7 * 4) { e.nextDay() }
        XCTAssertEqual(e.applicants(companyID: id).count, Agency.immediate + Agency.laterWeeks, "better fits keep coming")
        var hired = 0
        for a in e.applicants(companyID: id) where hired == 0 {
            if e.hire(personID: a.personID, companyID: id, monthlyWage: e.state.people[a.personID]!.askingMonthlyWage * 1.8) == .ok { hired = a.personID }
        }
        guard hired != 0 else { throw XCTSkip("no agency hire") }
        let m = e.state.company(id)!.staff.first { $0.id == hired }!
        XCTAssertEqual(m.num("agPct"), Agency.salaryShare)
        XCTAssertEqual(Agency.salaryShare, 0.08)
        XCTAssertEqual(Agency.months, 24)
        for _ in 0..<(7 * 9) { e.nextDay() }
        let fees = e.state.company(id)!.transactions.filter { $0["l"].string.hasPrefix("Agency fee") }
        XCTAssertGreaterThanOrEqual(fees.count, 1)
        let wage = e.state.company(id)!.staff.first { $0.id == hired }?.monthlyWage ?? m.monthlyWage
        XCTAssertEqual(abs(fees[0]["a"].double), wage * 0.08, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSecurityGuardLowersTheftLossesAndDutyIsSet() throws {
        let probe = try company(7, trade: "cafe").0
        guard let shrinkTrade = probe.data.catalog.all.first(where: { $0.trait("shrink") != nil && ["retail", "venue"].contains($0.family) && $0.premisesKind != "office" }) else { throw XCTSkip("no shrink trade") }
        var (e, id) = try company(7, trade: shrinkTrade.id)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        let pid = try hireOne(&e, id, role: shrinkTrade.standardStaff.first?.role ?? "cashier")
        XCTAssertEqual(RoleEffects.shrinkFactor(e.state.company(id)!), 1)
        XCTAssertFalse(e.setDuty(companyID: id, employeeID: pid, duty: "notARole"))
        XCTAssertTrue(e.setDuty(companyID: id, employeeID: pid, duty: "guard"))
        XCTAssertEqual(e.workerProfile(companyID: id, employeeID: pid)?.duty, "guard")
        XCTAssertEqual(RoleEffects.shrinkFactor(e.state.company(id)!), RoleEffects.guardLossFactor)
        XCTAssertEqual(RoleEffects.theftGrowthFactor(e.state.company(id)!), 0.5)
        XCTAssertTrue(e.recommendedRoles(companyID: id).first { $0.id == "guard" }?.filled ?? false)
        var without = e
        without.update { s, _, _ in if let i = s.companyIndex(id), let k = s.companies[i].staff.firstIndex(where: { $0.id == pid }) { var st = s.companies[i].staff; st[k].set("duty", .null); s.companies[i].staff = st } }
        var with = e
        for _ in 0..<(7 * 4) { with.nextDay(); without.nextDay() }
        let a = with.state.company(id)!.cash, b = without.state.company(id)!.cash
        print("ROLE guard cash with \(a) without \(b)")
        XCTAssertGreaterThan(a, b)
        XCTAssertTrue(e.setDuty(companyID: id, employeeID: pid, duty: nil))
        XCTAssertNil(e.workerProfile(companyID: id, employeeID: pid)?.duty)
    }

    func testOtherRoleEffects() throws {
        var (e, id) = try company(8, trade: "cafe")
        let pid = try hireOne(&e, id, role: "barista")
        let co0 = e.state.company(id)!
        XCTAssertEqual(RoleEffects.awarenessFactor(co0), 1)
        XCTAssertEqual(RoleEffects.inspectionRelief(co0), 0)
        XCTAssertTrue(e.setDuty(companyID: id, employeeID: pid, duty: "marketer"))
        var co = e.state.company(id)!
        XCTAssertEqual(RoleEffects.awarenessFactor(co), 1 + RoleEffects.marketingGain + (co.ownerHours < RoleEffects.ownerAwayHours ? RoleEffects.marketingGainOwnerAway - RoleEffects.marketingGain : 0))
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].ownerHours = 5 } }
        co = e.state.company(id)!
        XCTAssertEqual(RoleEffects.awarenessFactor(co), 1 + RoleEffects.marketingGainOwnerAway, "more while the owner works elsewhere")
        XCTAssertTrue(e.setDuty(companyID: id, employeeID: pid, duty: "cleaner"))
        XCTAssertEqual(RoleEffects.inspectionRelief(e.state.company(id)!), RoleEffects.cleanerInspection)
    }

    func testTermsSummaryGivesTheWholePage() throws {
        var (e, id) = try company(9, trade: "cafe")
        let p = candidate(&e, id, role: "barista")
        var terms = Hiring.Terms()
        terms.percent = 50
        terms.promises = [StaffPromises.Draft(.salaryReview, dueInWeeks: 26)]
        let t = try XCTUnwrap(e.termsSummary(companyID: id, candidateID: p.id, terms: terms))
        XCTAssertEqual(t.personID, p.id)
        XCTAssertGreaterThan(t.salaryAsk, 0)
        XCTAssertGreaterThan(t.marketPay, 0)
        XCTAssertEqual(t.contractType, "Part time")
        XCTAssertEqual(t.workingPercent, 50, accuracy: 0.5)
        XCTAssertEqual(t.promisesAsked.count, 1)
        XCTAssertEqual(t.startWeek, e.state.week)
        XCTAssertEqual(t.counterOptions.map(\.id), ["ask", "market", "middle"])
        XCTAssertTrue(t.counterOptions.allSatisfy { $0.annualEmployerCost > 0 })
        XCTAssertEqual(e.termsSummary(companyID: id, candidateID: p.id, terms: terms), t)
        XCTAssertNil(e.termsSummary(companyID: id, candidateID: -5))
    }

    func testWorkerProfileFields() throws {
        var (e, id) = try company(11, trade: "cafe")
        let pid = try hireOne(&e, id, role: "barista")
        e.update { s, _, _ in StaffPromises.make(&s, companyID: id, personID: pid, draft: StaffPromises.Draft(.training, dueInWeeks: 30)) }
        for _ in 0..<(7 * 3) { e.nextDay() }
        let w = try XCTUnwrap(e.workerProfile(companyID: id, employeeID: pid))
        XCTAssertEqual(w.employeeID, pid)
        XCTAssertGreaterThan(w.monthlyWage, 0)
        XCTAssertNotNil(w.contract)
        XCTAssertEqual(w.promises.count, 1)
        XCTAssertFalse(w.mood.isEmpty)
        XCTAssertGreaterThan(w.hoursPerWeek, 0)
        XCTAssertEqual(w.weeksEmployed, 3)
        XCTAssertEqual(w.hoursWorked, w.hoursPerWeek * 3, accuracy: 0.01)
        XCTAssertGreaterThan(w.performance, 0)
        XCTAssertGreaterThan(w.expectedPerformance, 0)
        XCTAssertEqual(w.meetsExpectation, w.performance >= w.expectedPerformance - 5)
        XCTAssertFalse(w.performanceNote.isEmpty)
        XCTAssertNil(e.workerProfile(companyID: id, employeeID: -1))
    }

    func testDeterministicAndSaveReloadSafe() throws {
        func play() throws -> GameEngine {
            var (e, id) = try company(12, trade: "cafe")
            _ = e.postJobAd(companyID: id, role: "barista")
            _ = e.engageAgency(companyID: id, role: "barista")
            let pid = try hireOne(&e, id, role: "barista")
            e.update { s, _, _ in StaffPromises.make(&s, companyID: id, personID: pid, draft: StaffPromises.Draft(.salaryReview, dueInWeeks: 2)) }
            for _ in 0..<(7 * 6) { e.nextDay() }
            return e
        }
        let a = try play(), b = try play()
        XCTAssertEqual(a.state, b.state, "same seed and actions give the same game")
        let data = try JSONEncoder().encode(a.state)
        let loaded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(loaded, a.state)
        var x = a, y = a
        y.update { s, _, _ in s = loaded }
        for _ in 0..<(7 * 4) { x.nextDay(); y.nextDay() }
        XCTAssertEqual(x.state, y.state)
        XCTAssertTrue(Ledger.gaps(x.state).isEmpty)
    }
}
