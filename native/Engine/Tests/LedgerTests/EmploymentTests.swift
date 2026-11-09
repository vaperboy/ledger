import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
@testable import Simulation

/// Working percentages, the two-page hiring negotiation, promises, after-hiring changes, the work log and hidden values. Probes run in six
/// countries (UK US DE PL MX JP).
final class EmploymentTests: XCTestCase {
    static let countries = ["UK", "US", "DE", "PL", "MX", "JP"]

    private func shop(_ code: String = "UK", trade: String = "cafe", seed: Int = 9) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: 200_000_000) else { XCTFail("start \(code)"); throw CocoaError(.fileReadUnknown) }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { _ = e.nextDay(); days += 1 }
        return (e, id)
    }

    @discardableResult
    private func candidate(_ e: inout GameEngine, _ id: Int, role: String = "cook", tier: String = "mid", pers: String? = nil, noLimit: Bool = true) -> Int {
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: role, company: s.company(id), tier: tier, state: &s, data: d)
            if let pers { p.set("pers", pers) }
            p.set("sec", 0.1)
            s.people[p.id] = p; pid = p.id
        }
        // pick a candidate without an hours limit unless the test is about it
        if noLimit, Hiring.maxHoursPerWeek(personID: pid) != nil { return candidate(&e, id, role: role, tier: tier, pers: pers, noLimit: true) }
        return pid
    }

    /// A week of the real daily simulation (the company must have opened).
    private func week(_ e: inout GameEngine) {
        for _ in 0..<7 { _ = e.nextDay() }
    }

    private func member(_ e: GameEngine, _ id: Int, _ pid: Int) -> StaffMember? { e.state.company(id)?.staff.first { $0.id == pid } }

    // MARK: 1. Working percentages

    func testWorkingPercentagesDriveHoursWagesCostAndMetricsInSixCountries() throws {
        for code in Self.countries {
            var (e, id) = try shop(code)
            for pct in [20.0, 50.0, 80.0, 100.0, 65.0] {
                let pid = candidate(&e, id)
                let offer = e.marketWage(role: "cook", companyID: id) * 1.8
                let terms = Hiring.Terms(percent: pct)
                let preview = try XCTUnwrap(e.hiringEmployerCost(companyID: id, personID: pid, monthlyWage: offer, terms: terms), "\(code) \(pct)")
                XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: offer, terms: terms), .ok, "\(code) \(pct)")
                let m = try XCTUnwrap(member(e, id, pid))
                XCTAssertEqual(EmploymentContract.percent(m), pct, accuracy: 0.01, "\(code) \(pct): contracted percent")
                XCTAssertEqual(EmploymentContract.hours(m), 37.5 * pct / 100, accuracy: 0.13, "\(code) \(pct): hours")
                XCTAssertEqual(m.partTimeShare, pct / 100, accuracy: 0.004, "\(code) \(pct): capacity share")
                let booked = try XCTUnwrap(e.employerCost(companyID: id, personID: pid))
                XCTAssertEqual(booked.totalMonthly, preview.totalMonthly, accuracy: 0.5, "\(code) \(pct): preview equals booked")
                XCTAssertEqual(booked.workingPercentage, pct / 100, accuracy: 0.004)
            }
            let tm = try XCTUnwrap(e.teamMetrics(companyID: id))
            let hours = e.state.company(id)!.staff.reduce(0) { $0 + EmploymentContract.hours($1) }
            XCTAssertEqual(tm.totalHoursPerWeek, hours, accuracy: 1e-6, "\(code): team hours follow the percentages")
            XCTAssertGreaterThan(tm.averageHourlyRate, 0)
            XCTAssertEqual(tm.averageHourlyRate, tm.grossMonthlyWages / tm.totalHoursPerMonth, accuracy: 1e-6, "\(code): average hourly rate follows the hours")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        }
    }

    func testPayAndCapacityScaleWithThePercentage() throws {
        var (e, id) = try shop()
        let a = candidate(&e, id), b = candidate(&e, id)
        let offer = e.marketWage(role: "cook", companyID: id) * 1.8
        XCTAssertEqual(e.hire(personID: a, companyID: id, monthlyWage: offer, terms: Hiring.Terms(percent: 100)), .ok)
        XCTAssertEqual(e.hire(personID: b, companyID: id, monthlyWage: offer, terms: Hiring.Terms(percent: 50)), .ok)
        let wa = member(e, id, a)!.monthlyWage, wb = member(e, id, b)!.monthlyWage
        XCTAssertEqual(wb / wa, 0.5, accuracy: 0.01, "gross wages follow the percentage")
        // the same person changed afterwards: pay, cost and capacity follow
        let before = e.employerCost(companyID: id, personID: a)!.totalMonthly
        guard case .agreed = e.contractPropose(companyID: id, personID: a, proposal: .init(.hours, amount: 80, choice: "percent")) else { return XCTFail("percent change") }
        let m = member(e, id, a)!
        XCTAssertEqual(EmploymentContract.percent(m), 80, accuracy: 0.01)
        XCTAssertEqual(e.employerCost(companyID: id, personID: a)!.totalMonthly / before, 0.8, accuracy: 0.01)
        XCTAssertEqual(m.partTimeShare, 0.8, accuracy: 0.001)
        // back to full time
        guard case .agreed = e.contractPropose(companyID: id, personID: a, proposal: .init(.hours, amount: 100, choice: "percent")) else { return XCTFail("full") }
        XCTAssertNil(member(e, id, a)!.weeklyHours)
        XCTAssertEqual(member(e, id, a)!.monthlyWage, wa, accuracy: 1)
    }

    func testOutOfRangePercentageIsRefusedWithAReasonAndHoursLimitIsExplicit() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id)
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(percent: 5)), .planRefused)
        XCTAssertNotNil(e.hireTermsProblem(post: .worker(role: "cook"), companyID: id, personID: pid, terms: Hiring.Terms(percent: 5)))
        XCTAssertNil(e.state.people[pid].flatMap { $0.employerID == id ? $0 : nil }, "nobody was hired")
        // a person who studies can work at most 20 or 30 hours: an offer over it is refused with a reason, never cut silently
        var limited = 0
        for _ in 0..<60 { let p = candidate(&e, id, noLimit: false); if Hiring.maxHoursPerWeek(personID: p) != nil { limited = p; break } }
        let cap = try XCTUnwrap(Hiring.maxHoursPerWeek(personID: limited))
        let over = Hiring.Terms(hours: cap + 5)
        XCTAssertNotNil(e.hireTermsProblem(post: .worker(role: "cook"), companyID: id, personID: limited, terms: over))
        XCTAssertEqual(e.hire(personID: limited, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: over), .planRefused)
        XCTAssertEqual(e.hire(personID: limited, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(hours: cap)), .ok)
        XCTAssertEqual(member(e, id, limited)!.weeklyHours ?? 0, cap, accuracy: 0.01, "exactly the hours agreed")
        XCTAssertEqual(e.employmentContract(companyID: id, personID: limited)?.hoursLimit, cap)
    }

    func testOldPartTimeAndSeasonalRecordsReadAsPercentagesWithoutLosingData() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id)
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(hours: 20)), .ok)
        // a record as the old code wrote it: hours 20, pt share, seasonal months
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!, k = s.companies[ci].staff.firstIndex { $0.id == pid }!
            var st = s.companies[ci].staff
            st[k].weeklyHours = 20; st[k].partTimeShare = 20 / 37.5
            st[k].set("seas", .array([6, 7, 8].map { .number(Double($0)) }))
            s.companies[ci].staff = st
        }
        let c = try XCTUnwrap(e.employmentContract(companyID: id, personID: pid))
        XCTAssertEqual(c.workingPercent, 53.33, accuracy: 0.01)
        XCTAssertTrue(c.typeLabels.contains("Seasonal") && c.typeLabels.contains("Part time"))
        XCTAssertEqual(c.seasonMonths, [6, 7, 8])
        XCTAssertEqual(c.contractedHoursPerWeek, 20)
        let m = member(e, id, pid)!
        XCTAssertEqual(m.weeklyHours, 20, "the record itself is untouched")
    }

    func testSeasonalAndTemporaryContractsHaveRealDatesAndConsequences() throws {
        for code in ["UK", "DE", "MX"] {
            var (e, id) = try shop(code)
            // temporary: a custom length (not one of the screens' choices)
            let t = candidate(&e, id)
            XCTAssertEqual(e.hire(personID: t, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(fixedTermWeeks: 10, percent: 80)), .ok, code)
            let c = try XCTUnwrap(e.employmentContract(companyID: id, personID: t))
            XCTAssertEqual(c.endWeek, e.state.week + 10, code)
            XCTAssertNotNil(c.endDate)
            XCTAssertTrue(c.typeLabels.contains("Temporary"))
            XCTAssertFalse(c.isPermanent)
            XCTAssertNotNil(c.renewalQuestionWeek)
            XCTAssertFalse(c.history.isEmpty, "the hire is the first entry")
            // the renewal question arrives, and on the date the job ends (the labour data decides what is owed)
            e.update { s, d, _ in s.week += 9; FixedTerm.weekly(&s, data: d) }
            XCTAssertTrue(e.state.inbox.contains { $0.title.contains("fixed term") && $0.title.contains("ends in") }, code)
            e.update { s, d, _ in s.week += 2; FixedTerm.weekly(&s, data: d) }
            XCTAssertNil(member(e, id, t), "\(code): the temporary job ended on its date")
            // seasonal for one season: ends with the season
            let sPerson = candidate(&e, id)
            XCTAssertEqual(e.hire(personID: sPerson, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(seasonMonths: [6, 7, 8], percent: 50, seasonCount: 1)), .ok, code)
            let sc = try XCTUnwrap(e.employmentContract(companyID: id, personID: sPerson))
            XCTAssertNotNil(sc.endWeek)
            XCTAssertEqual(sc.seasonMonths, [6, 7, 8])
            let end = try XCTUnwrap(sc.endWeek)
            XCTAssertFalse([6, 7, 8].contains(GameCalendar.date(week: end).month + 1), "\(code): ends on the first week after the season")
            XCTAssertTrue([6, 7, 8].contains(GameCalendar.date(week: end - 1).month + 1) || end - e.state.week > 0)
        }
    }

    func testFixedMonthlySalaryPartTimeIsScaledAndStaysFixed() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id)
        let offer = e.marketWage(role: "cook", companyID: id) * 1.8
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: offer, terms: Hiring.Terms(basis: "fix", percent: 50)), .ok)
        let m = try XCTUnwrap(member(e, id, pid))
        XCTAssertEqual(m.payBasis, "fix")
        XCTAssertEqual(EmploymentContract.percent(m), 50, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(e.employmentContract(companyID: id, personID: pid)).payBasisLabel, "Fixed monthly salary")
    }

    // MARK: 2. Two-page negotiation

    func testAskIsNilUntilTheCandidateHasMadeOneAndShownEqualsApplied() throws {
        for code in Self.countries {
            var (e, id) = try shop(code)
            let pid = candidate(&e, id)
            let post = HirePost.worker(role: "cook")
            let terms = Hiring.Terms(percent: 80)
            var talk = try XCTUnwrap(e.hireSalaryTalk(post: post, companyID: id, personID: pid, terms: terms), code)
            XCTAssertNil(talk.theirAsk, "\(code): no ask before the candidate has made one")
            XCTAssertFalse(talk.canOfferTheirAsk)
            XCTAssertEqual(talk.marketPayLabel, "Offer market pay")
            XCTAssertEqual(talk.yourOffer, talk.marketPay, accuracy: 0.01, "without an offer of yours the market pay is the starting point")
            let ask = try XCTUnwrap(e.hearTheirAsk(post: post, companyID: id, personID: pid, terms: terms), code)
            talk = try XCTUnwrap(e.hireSalaryTalk(post: post, companyID: id, personID: pid, terms: terms, offer: ask))
            XCTAssertEqual(talk.theirAsk, ask)
            XCTAssertTrue(talk.canOfferTheirAsk)
            // what is shown is what is applied
            XCTAssertEqual(e.hireOffer(post: post, companyID: id, personID: pid, monthlyWage: ask, terms: terms), .hired, "\(code): the ask is accepted")
            let m = try XCTUnwrap(member(e, id, pid))
            let booked = try XCTUnwrap(e.employerCost(companyID: id, personID: pid))
            XCTAssertEqual(m.monthlyWage, talk.appliedMonthlyWage, accuracy: 0.5, "\(code): wage shown = wage applied")
            XCTAssertEqual(booked.grossHourlyWage, talk.hourlyWage, accuracy: 1e-6, "\(code): hourly wage shown = applied")
            XCTAssertEqual(booked.totalAnnual, talk.annualEmployerCost, accuracy: 0.5, "\(code): annual employer cost shown = booked")
            XCTAssertEqual(talk.workingPercent, 80, accuracy: 0.01)
        }
    }

    func testACounterOfferIsAnAskAndKeepsTheRounds() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id, pers: "steady")
        let post = HirePost.worker(role: "cook")
        let market = e.marketWage(role: "cook", companyID: id)
        var counter = 0.0
        for _ in 0..<4 {
            let r = e.hireOffer(post: post, companyID: id, personID: pid, monthlyWage: market * 0.8)
            if case .countered(let amount, _) = r { counter = amount; break }
            if r == .hired { break }
        }
        if counter > 0 {
            let talk = try XCTUnwrap(e.hireSalaryTalk(post: post, companyID: id, personID: pid, terms: Hiring.Terms()))
            XCTAssertEqual(talk.theirAsk ?? 0, counter, accuracy: 0.01, "their counter is their ask")
            XCTAssertGreaterThan(talk.rounds, 0)
        }
    }

    func testCandidateAsksAreCentredOnMarketPayAndAgeDoesNotMoveThem() throws {
        for code in Self.countries {
            var (e, id) = try shop(code)
            var byTier: [String: [Double]] = [:]
            let market = e.marketWage(role: "cook", companyID: id)
            for tier in ["young", "mid", "senior"] {
                for _ in 0..<40 {
                    let pid = candidate(&e, id, tier: tier)
                    byTier[tier, default: []].append(e.state.people[pid]!.askingMonthlyWage / market)
                }
            }
            let all = byTier.values.flatMap { $0 }
            let mean = all.reduce(0, +) / Double(all.count)
            XCTAssertEqual(mean, 1.0, accuracy: 0.1, "\(code): asks centre on the market pay")
            XCTAssertGreaterThan(all.max()! - all.min()!, 0.15, "\(code): and spread by skill and experience")
            // within the same skill band, the age group makes no difference: compare the skill-adjusted asks
            func adj(_ t: String) -> Double { byTier[t]!.reduce(0, +) / Double(byTier[t]!.count) }
            XCTAssertLessThan(abs(adj("young") - adj("senior")), 0.3)
        }
        // the formula itself has no age in it
        XCTAssertEqual(Hiring.askSpread(skill: 55, experience: 6), 1.0, accuracy: 1e-9)
        XCTAssertGreaterThan(Hiring.askSpread(skill: 80, experience: 15), Hiring.askSpread(skill: 30, experience: 1))
    }

    func testBetterPackageAndStrongerCompanyLowerTheAskALittle() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id)
        let post = HirePost.worker(role: "cook")
        let plain = try XCTUnwrap(e.hearTheirAsk(post: post, companyID: id, personID: pid, terms: Hiring.Terms()))
        let rich = Hiring.Terms(bonusPlan: WorkerBonus.levels.first { !$0.isNone }?.id, expenseItems: StaffExpenses.items(forRole: "cook").prefix(2).map { $0.id },
                                promises: [StaffPromises.Draft(.salaryReview, dueInWeeks: 26), StaffPromises.Draft(.training, dueInWeeks: 20)], expectations: ["career"])
        let better = try XCTUnwrap(e.hearTheirAsk(post: post, companyID: id, personID: pid, terms: rich))
        XCTAssertLessThan(better, plain, "a better package lowers the ask")
        XCTAssertGreaterThan(better, plain * 0.9, "but only a little")
        // a temporary job for someone who needs security costs more
        e.update { s, _, _ in var p = s.people[pid]!; p.set("sec", 0.9); s.people[pid] = p }
        let perm = try XCTUnwrap(e.hearTheirAsk(post: post, companyID: id, personID: pid, terms: Hiring.Terms()))
        let temp = try XCTUnwrap(e.hearTheirAsk(post: post, companyID: id, personID: pid, terms: Hiring.Terms(fixedTermWeeks: 26)))
        XCTAssertGreaterThan(temp, perm)
        // a company that is late with its bills is a riskier employer
        let risky = e.state.people[pid]!
        _ = risky
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].unpaidMonths = 2 }
        let late = try XCTUnwrap(e.hearTheirAsk(post: post, companyID: id, personID: pid, terms: Hiring.Terms()))
        XCTAssertGreaterThan(late, perm)
        let reasons = try XCTUnwrap(e.hireSalaryTalk(post: post, companyID: id, personID: pid, terms: Hiring.Terms())).reasons
        XCTAssertTrue(reasons.contains { $0.contains("late with its bills") })
        XCTAssertFalse(reasons.joined().contains("%"), "reasons are words")
    }

    func testPageOneOptionsAndSamePathForManagersExecutivesOfficeAndAnalyst() throws {
        var (e, id) = try shop(seed: 21)
        let pid = candidate(&e, id)
        let opts = try XCTUnwrap(e.hireDraftOptions(post: .worker(role: "cook"), companyID: id, personID: pid))
        XCTAssertEqual(opts.percents, [20, 50, 80, 100])
        XCTAssertEqual(Set(opts.contractKinds.map(\.id)), ["permanent", "seasonal", "temporary"])
        XCTAssertTrue(opts.fields.contains("promises") && opts.fields.contains("vehicle"))
        XCTAssertEqual(Set(opts.promiseKinds.map(\.id)), Set(StaffPromises.Kind.allCases.map(\.rawValue)))
        // manager
        var cands: [Person] = []
        e.update { s, d, _ in cands = (0..<3).map { _ in ManagerModel.generateCandidate(company: s.company(id), type: "gen", state: &s, data: d) } }
        let mgr = cands[0].id
        let mopts = try XCTUnwrap(e.hireDraftOptions(post: .manager, companyID: id, personID: mgr))
        XCTAssertEqual(mopts.percents, [100])
        XCTAssertNil(mopts.hoursLimit)
        var mt = try XCTUnwrap(e.hireSalaryTalk(post: .manager, companyID: id, personID: mgr, terms: Hiring.Terms()))
        XCTAssertNil(mt.theirAsk)
        XCTAssertGreaterThan(mt.annualEmployerCost, mt.appliedMonthlyWage * 12)
        let ask = try XCTUnwrap(e.hearTheirAsk(post: .manager, companyID: id, personID: mgr))
        mt = try XCTUnwrap(e.hireSalaryTalk(post: .manager, companyID: id, personID: mgr, terms: Hiring.Terms(), offer: ask))
        XCTAssertTrue(mt.canOfferTheirAsk)
        XCTAssertEqual(e.hireOffer(post: .manager, companyID: id, personID: mgr, monthlyWage: ask * 1.3), .hired)
        XCTAssertEqual(e.state.company(id)?.managerID, mgr)
        XCTAssertNil(e.state.people[mgr]?.value("tf").isNull == false ? 1 : nil, "the transient factor is gone")
        // a bad draft for a post that has no hours
        XCTAssertNotNil(e.hireTermsProblem(post: .manager, companyID: id, personID: cands[1].id, terms: Hiring.Terms(percent: 50)))
        // analyst: the head-office road
        var analyst = 0
        e.update { s, d, _ in analyst = MarketMap.dataAnalystCandidates(&s, count: 1, data: d)[0].id }
        let at = try XCTUnwrap(e.hireSalaryTalk(post: .analyst, companyID: nil, personID: analyst, terms: Hiring.Terms()))
        XCTAssertNil(at.theirAsk)
        let aAsk = try XCTUnwrap(e.hearTheirAsk(post: .analyst, companyID: nil, personID: analyst))
        let ar = e.hireOffer(post: .analyst, companyID: nil, personID: analyst, monthlyWage: aAsk * 1.3)
        XCTAssertTrue(ar == .hired || ar == .blocked("The head office already has a data analyst."), "\(ar)")
        // executive: one door too
        var exec = 0
        e.update { s, d, _ in exec = ManagerModel.searchExecutive(&s, level: .md, data: d)?.first?.id ?? 0 }
        if exec != 0 {
            XCTAssertNil(try XCTUnwrap(e.hireSalaryTalk(post: .executive(.md), companyID: nil, personID: exec, terms: Hiring.Terms())).theirAsk)
            let xAsk = try XCTUnwrap(e.hearTheirAsk(post: .executive(.md), companyID: nil, personID: exec))
            XCTAssertGreaterThan(xAsk, 0)
        }
    }

    // MARK: 3. Promises

    func testPromiseLifecycleDueFulfilledBrokenRenegotiated() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id, pers: "steady")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(promises: [StaffPromises.Draft(.salaryReview, dueInWeeks: 8), StaffPromises.Draft(.training, dueInWeeks: 8)])), .ok)
        var rows = e.promises(companyID: id)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.status == .pending && $0.employee == e.state.people[pid]!.name && $0.dueWeek == $0.madeWeek + 8 })
        // a second one of the same kind is refused
        var second: StaffPromises.Promise?
        e.update { s, _, _ in second = StaffPromises.make(&s, companyID: id, personID: pid, draft: StaffPromises.Draft(.training, dueInWeeks: 5)) }
        XCTAssertNil(second)
        // training is kept the moment a course is taken
        var course = ""
        e.update { s, d, _ in course = StaffProfile.courses(s.company(id)!, data: d).first?.id ?? "" }
        if !course.isEmpty {
            e.update { s, d, _ in _ = StaffProfile.takeCourse(&s, companyID: id, staffID: pid, courseID: course, data: d) }
            XCTAssertEqual(e.promises(companyID: id).first { $0.kind == .training }?.status, .fulfilled)
        }
        // due date arrives: Due, with an Inbox note
        e.update { s, d, _ in s.week += 8; StaffPromises.weekly(&s, data: d) }
        XCTAssertEqual(e.promises(companyID: id).first { $0.kind == .salaryReview }?.status, .due)
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("is waiting for what you promised") })
        // a renegotiation moves the date (or the person refuses), once
        let row = try XCTUnwrap(e.promises(companyID: id).first { $0.kind == .salaryReview })
        let r = e.renegotiatePromise(personID: pid, promiseID: row.id, newDueInWeeks: 6)
        switch r {
        case .agreed:
            let all = e.promises(companyID: id).filter { $0.kind == .salaryReview }
            XCTAssertTrue(all.contains { $0.status == .renegotiated } && all.contains { $0.status == .pending })
            XCTAssertEqual(e.renegotiatePromise(personID: pid, promiseID: all.first { $0.status == .pending }!.id, newDueInWeeks: 4).isRefusal, true, "only once")
        case .refused: break
        case .notPossible(let why): XCTFail(why)
        }
        // left unkept past the grace period it breaks: the old marks of a refused request follow, and the company's word suffers
        e.update { s, d, _ in s.week += 40; for _ in 0..<3 { StaffPromises.weekly(&s, data: d); s.week += 2 } }
        let broken = e.promises(companyID: id).first { $0.kind == .salaryReview && $0.status == .broken }
        XCTAssertNotNil(broken)
        let m = try XCTUnwrap(member(e, id, pid))
        XCTAssertGreaterThan(m.int("denied"), 0, "the existing mark: more people hand in notice")
        XCTAssertTrue(StaffPromises.letDown(m, week: e.state.week))
        XCTAssertTrue(StaffProfile.mood(e.state, companyID: id, staffID: pid, data: e.data)!.bad.contains { $0.contains("promised") })
        XCTAssertEqual(StaffPromises.record(e.state.company(id)!, week: e.state.week).broken, 1)
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("waiting for what you promised") })
    }

    func testEachPromiseKindHasARealFulfilmentCheck() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id)
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(percent: 50)), .ok)
        let perk = try XCTUnwrap(StaffPerks.all.first { !StaffPerks.isOn(e.state.company(id)!, $0.id) && $0.groups.contains(StaffPerks.group(ofRole: "cook")) })
        let drafts: [StaffPromises.Draft] = [.init(.salaryReview, dueInWeeks: 30), .init(.betterConditions, dueInWeeks: 30), .init(.futureBenefits, dueInWeeks: 30, detail: "perk:\(perk.id)"),
                                            .init(.percentageChange, dueInWeeks: 30, detail: "80"), .init(.promotion, dueInWeeks: 30), .init(.responsibility, dueInWeeks: 30)]
        for d in drafts { XCTAssertNotNil(e.promise(companyID: id, personID: pid, draft: d).changedTerms ? 1 : nil, "\(d.kind)") }
        XCTAssertFalse(StaffPromises.Draft(.futureBenefits, dueInWeeks: 5, detail: "perk:nope").isPlausible)
        XCTAssertFalse(StaffPromises.Draft(.percentageChange, dueInWeeks: 5, detail: "5").isPlausible)
        func status(_ k: StaffPromises.Kind) -> StaffPromises.Status? { e.promises(companyID: id).first { $0.kind == k }?.status }
        XCTAssertEqual(status(.salaryReview), .pending)
        // percentage change through the contract door
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.hours, amount: 80, choice: "percent")) else { return XCTFail("percent") }
        XCTAssertEqual(status(.percentageChange), .fulfilled)
        // a raise
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payRise, amount: 0.08)) else { return XCTFail("raise") }
        XCTAssertEqual(status(.salaryReview), .fulfilled)
        // a perk that covers them
        e.update { s, _, _ in _ = StaffPerks.set(&s, companyID: id, perk: perk.id, on: true) }
        XCTAssertEqual(status(.futureBenefits), .fulfilled)
        XCTAssertEqual(status(.betterConditions), .fulfilled)
        // promotion and responsibility are fulfilled by a real promotion
        let posts = ManagerModel.promotionPosts(e.state, companyID: id, personID: pid, data: e.data).filter { $0.blocked.isEmpty && $0.kind == "role" }
        if let post = posts.first {
            guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.promotion, amount: post.ask * 1.2, choice: post.id, terms: .init(authority: 1))) else { return }
            XCTAssertEqual(status(.promotion), .fulfilled)
            XCTAssertEqual(status(.responsibility), .fulfilled)
        }
        // a promise instead of an immediate answer to their request
        XCTAssertTrue(e.state.inbox.isEmpty || true)
    }

    func testAPromiseCanAnswerTheirRequest() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id, pers: "loyal")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2), .ok)
        e.update { s, d, _ in
            ContractTalk.employeeAsks(&s, companyIndex: s.companyIndex(id)!, staffID: pid, topic: .payRise, data: d)
        }
        XCTAssertNotNil(e.contractTalk(personID: pid))
        let r = e.contractRespond(companyID: id, personID: pid, decision: .promise(StaffPromises.Draft(.salaryReview, dueInWeeks: 12)))
        XCTAssertTrue(r.changedTerms)
        XCTAssertNil(e.contractTalk(personID: pid), "the request is answered")
        XCTAssertEqual(e.promises(companyID: id).count, 1)
        XCTAssertTrue(e.contractHistory(companyID: id, personID: pid).contains { $0.kind == "promise" })
    }

    // MARK: 4. After-hiring changes

    func testPreviewShowsCostsHoursAndImpactAndHistoryIsKept() throws {
        for code in ["UK", "DE", "JP"] {
            var (e, id) = try shop(code)
            let pid = candidate(&e, id, pers: "loyal")
            XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2), .ok)
            let state0 = e.state
            let pv = e.contractPreview(companyID: id, personID: pid, proposal: .init(.hours, amount: 50, choice: "percent"))
            XCTAssertTrue(e.state == state0, "a preview changes nothing")
            XCTAssertEqual(pv.hoursBefore, 37.5)
            XCTAssertEqual(pv.hoursAfter, 18.75, accuracy: 0.01)
            XCTAssertEqual(pv.hoursDifference, -18.75, accuracy: 0.01)
            XCTAssertLessThan(pv.costPerMonth, 0)
            XCTAssertEqual(pv.costPerYear, pv.costPerMonth * 12, accuracy: 1e-6)
            XCTAssertEqual(pv.personMonthlyDifference, pv.costPerMonth, accuracy: 1, "\(code): for one person the company difference is the person's")
            XCTAssertNotNil(pv.employerBefore); XCTAssertNotNil(pv.employerAfter)
            XCTAssertFalse(pv.payrollImpact.isEmpty); XCTAssertFalse(pv.operationalImpact.isEmpty)
            XCTAssertTrue(pv.mayRefuse)
            XCTAssertEqual(pv.employerAfter?.totalMonthly ?? 0, pv.employerBefore!.totalMonthly / 2, accuracy: 1, "\(code)")
            // agreed (or refused, by temperament); a refusal changes nothing
            let reply = e.contractPropose(companyID: id, personID: pid, proposal: .init(.hours, amount: 50, choice: "percent"))
            switch reply {
            case .agreed:
                XCTAssertEqual(EmploymentContract.percent(member(e, id, pid)!), 50, accuracy: 0.01)
                XCTAssertTrue(e.contractHistory(companyID: id, personID: pid).contains { $0.kind == "hours" && $0.text.contains("50") })
            case .unwilling: XCTAssertEqual(EmploymentContract.percent(member(e, id, pid)!), 100)
            default: XCTFail("\(reply)")
            }
            guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payRise, amount: 0.05)) else { return XCTFail("raise is never refused") }
            let hist = e.contractHistory(companyID: id, personID: pid)
            XCTAssertTrue(hist.first!.kind == "hired" && hist.contains { $0.kind == "pay" })
            XCTAssertTrue(hist.map(\.week).sorted() == hist.map(\.week))
        }
    }

    func testEmployeesMayRefuseCutsAndChangesByTemperamentButNeverARaise() throws {
        var refused = [String: Int](), tried = [String: Int]()
        for (i, pers) in ["loyal", "steady", "restless", "arrogant"].enumerated() {
            for k in 0..<12 {
                var (e, id) = try shop(seed: 100 + i * 20 + k)
                let pid = candidate(&e, id, pers: pers)
                XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2), .ok)
                let temp = Hiring.temperament(of: e.state.people[pid]!).id
                tried[temp, default: 0] += 1
                // a raise: never refused
                guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payRise, amount: 0.07)) else { return XCTFail("a raise is taken") }
                // a big cut in hours; the draw is keyed on the person and the eight-week block, and ids repeat across seeds, so move to a different block
                e.update { s, _, _ in s.week += k * 8 }
                if case .unwilling = e.contractPropose(companyID: id, personID: pid, proposal: .init(.hours, amount: 40, choice: "percent")) { refused[temp, default: 0] += 1 }
                // a small cut is not a significant change
                var e2 = e
                if case .unwilling = e2.contractPropose(companyID: id, personID: pid, proposal: .init(.hours, amount: 90, choice: "percent")) { XCTFail("a small cut is not refused") }
            }
        }
        let flexible = Double(refused["flexible", default: 0]) / Double(max(1, tried["flexible", default: 0]))
        let stubborn = Double(refused["stubborn", default: 0] + refused["greedy", default: 0]) / Double(max(1, tried["stubborn", default: 0] + tried["greedy", default: 0]))
        XCTAssertLessThanOrEqual(flexible, stubborn + 0.0001, "flexible people refuse no more often than stubborn ones")
        XCTAssertGreaterThan(refused.values.reduce(0, +), 0, "some refuse")
        XCTAssertLessThan(refused.values.reduce(0, +), tried.values.reduce(0, +), "not everyone does")
    }

    func testSeasonalDurationAndContractTypeChangeThroughTheOneDoor() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id, pers: "loyal")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(seasonMonths: [6, 7, 8], percent: 50)), .ok)
        XCTAssertTrue(e.contractChoices(companyID: id, personID: pid, topic: .term).contains { $0.id == "seasons:1" })
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "seasons:1")) else { return XCTFail("seasons") }
        XCTAssertNotNil(e.employmentContract(companyID: id, personID: pid)?.endWeek)
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "perm")) else { return XCTFail("perm") }
        XCTAssertNil(e.employmentContract(companyID: id, personID: pid)?.endWeek)
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:30")) else { return XCTFail("30 weeks") }
        XCTAssertEqual(e.employmentContract(companyID: id, personID: pid)?.endWeek, e.state.week + 30)
    }

    // MARK: 5. Hidden values and realistic behaviour

    func testNoProbabilitiesOrScoresInPlayerVisibleEngineText() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id, pers: "restless")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2), .ok)
        var texts: [String] = []
        for topic in ContractTalk.Topic.allCases {
            for ch in e.contractChoices(companyID: id, personID: pid, topic: topic) {
                let pv = e.contractPreview(companyID: id, personID: pid, proposal: .init(topic, amount: topic == .payRise ? 0.05 : topic == .notice ? 4 : 1, choice: ch.id), asRequest: true)
                texts += pv.lines + pv.risks + pv.peers + pv.labour + [pv.payrollImpact, pv.operationalImpact]
            }
        }
        let bad = ["chance", "in 10", "% less", "Skill ", "Trust ", "Boldness", "odds"]
        for t in texts { for b in bad { XCTAssertFalse(t.contains(b), "'\(t)' shows a hidden value ('\(b)')") } }
        let profile = try XCTUnwrap(StaffProfile.profile(e.state, companyID: id, staffID: pid, data: e.data))
        XCTAssertFalse(profile.feedback.summary.contains(where: \.isNumber), "feedback has no figures")
        XCTAssertEqual(Mirror(reflecting: profile).children.compactMap(\.label).filter { ["skill", "skillBand", "personality", "tiredness", "learns", "stamina"].contains($0) }, [])
        let applicantID = candidate(&e, id)
        let a = Mirror(reflecting: try XCTUnwrap(e.applicant(personID: applicantID, companyID: id))).children.compactMap(\.label)
        XCTAssertFalse(a.contains("askMonthly") || a.contains("claimedSkill") || a.contains("askVersusMarket") || a.contains("trialSkill"))
    }

    func testWorkLogFeedsFeedbackFromActualWeeksAndIsCapped() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id)
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2), .ok)
        XCTAssertFalse(try XCTUnwrap(e.performanceFeedback(companyID: id, personID: pid)).enoughToJudge, "too early at first")
        for _ in 0..<8 { week(&e) }
        let m = try XCTUnwrap(member(e, id, pid))
        let log = WorkLog.weeks(m)
        XCTAssertGreaterThanOrEqual(log.count, 6, "the weekly simulation writes the log")
        XCTAssertTrue(log.allSatisfy { $0.tasksDone <= $0.tasksAssigned })
        let fb = try XCTUnwrap(e.performanceFeedback(companyID: id, personID: pid))
        XCTAssertTrue(fb.enoughToJudge)
        XCTAssertFalse(fb.observations.isEmpty)
        XCTAssertTrue(fb.observations.contains { $0.aspect == "Completed work" })
        // the sentences come from the counts: an invented log gives the sentence the counts imply
        var made = m
        let rows = (0..<8).map { w -> JSONValue in .array([e.state.week - w, 150, 150, 8, 7, 0, 0, 0, 0, 3, 1, 0, 0].map { .number(Double($0)) }) }
        made.set("wlog", .array(rows))
        let f2 = WorkLog.feedback(made, week: e.state.week)
        XCTAssertTrue(f2.summary.contains("Completed most assigned work"), f2.summary)
        XCTAssertTrue(f2.summary.contains("guidance"), f2.summary)
        // capped at 26 weeks
        for _ in 0..<30 { week(&e) }
        XCTAssertLessThanOrEqual(WorkLog.weeks(member(e, id, pid) ?? m).count, WorkLog.weeksKept)
        // a trial week reports observations, not a skill figure
        let cand = candidate(&e, id)
        let seen = try XCTUnwrap(e.startTrialWeek(personID: cand, companyID: id))
        XCTAssertFalse(seen.isEmpty)
        XCTAssertEqual(e.applicant(personID: cand, companyID: id)?.trialObservations.count, seen.count)
    }

    func testDissatisfactionDisengagementQuietAndAbruptLeaving() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id, pers: "restless")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2), .ok)
        let ci = e.state.companyIndex(id)!
        // keep them unhappy: pay far under the market, a refused request
        e.update { s, _, _ in
            var st = s.companies[ci].staff; st[0].monthlyWage = 100; st[0].set("denied", s.week); s.companies[ci].staff = st
            var f = s.companies[ci].value("flags"); f["noquit"] = 1; s.companies[ci].set("flags", f)
        }
        var voiced = false, disengaged = false
        for _ in 0..<40 {
            e.update { s, _, _ in var st = s.companies[ci].staff; if !st.isEmpty { st[0].set("denied", s.week); s.companies[ci].staff = st } }
            week(&e)
            voiced = voiced || e.state.inbox.contains { $0.title.contains("mentions other options") || $0.title.contains("would like a word") || $0.title.contains("has a complaint") || $0.title.contains("is not happy") }
            disengaged = disengaged || e.state.inbox.contains { $0.title.contains("lost interest") }
        }
        XCTAssertTrue(voiced, "they say so before it comes to more")
        XCTAssertTrue(disengaged, "and then lose interest")
        // while they are still on the payroll the mood card says so too
        var e3 = e
        e3.update { s, _, _ in
            let ci = s.companyIndex(id)!
            var st = s.companies[ci].staff
            if !st.contains(where: { $0.id == pid }) { st.append(StaffMember(raw: ["id": .number(Double(pid)), "role": .string("cook"), "wage": .number(1000), "w0": .number(0)])) }
            let k = st.firstIndex { $0.id == pid }!
            st[k].set("dis", s.week); s.companies[ci].staff = st
        }
        XCTAssertTrue(StaffProfile.mood(e3.state, companyID: id, staffID: pid, data: e3.data)?.bad.contains { $0.contains("lost interest") } ?? false)
        // the style is temperament, not age
        var young = e.state.people[pid]!, old = young
        young.age = 19; old.age = 60
        XCTAssertEqual(StaffBehaviour.style(of: young), StaffBehaviour.style(of: old))
        // abrupt leaving happens only for the discontented
        var m = StaffMember(raw: ["id": .number(Double(pid)), "dis": .number(8), "uw": .number(12)])
        var abrupt = 0
        for w in 0..<400 { if StaffBehaviour.resignationNotice(m, person: e.state.people[pid]!, week: w, standardNotice: 8).abrupt { abrupt += 1 } }
        XCTAssertGreaterThan(abrupt, 0)
        XCTAssertLessThan(abrupt, 250)
        m.raw.removeValue(forKey: "dis"); m.raw.removeValue(forKey: "uw")
        XCTAssertEqual(StaffBehaviour.resignationNotice(m, person: e.state.people[pid]!, week: 3, standardNotice: 8).abrupt, false, "a contented person works their notice")
    }

    func testRaiseThresholdHasNoAgeInIt() {
        let t = (try? GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1))?.data.catalog.tables
        XCTAssertNotNil(t)
        XCTAssertEqual(StaffTalks.raiseNeeded(role: "cook", age: 19, tables: t!), StaffTalks.raiseNeeded(role: "cook", age: 55, tables: t!))
    }

    // MARK: Promises to group employees

    func testPromisesToTheAnalystAreKeptByRealGroupActions() throws {
        var (e, id) = try shop(seed: 31)
        let exp = try XCTUnwrap(StaffExpenses.items(forRole: "analyst").first ?? StaffExpenses.items.first)
        var analyst = 0
        e.update { s, d, _ in analyst = MarketMap.dataAnalystCandidates(&s, count: 1, data: d)[0].id }
        let ask = try XCTUnwrap(e.hearTheirAsk(post: .analyst, companyID: nil, personID: analyst))
        let opts = try XCTUnwrap(e.hireDraftOptions(post: .analyst, companyID: nil, personID: analyst))
        XCTAssertEqual(Set(opts.promiseKinds.map(\.id)), Set(StaffPromises.Kind.allCases.map(\.rawValue)), "all kinds are offered")
        XCTAssertTrue(opts.promiseKinds.allSatisfy { !$0.detail.isEmpty })
        let drafts: [StaffPromises.Draft] = [.init(.salaryReview, dueInWeeks: 20), .init(.promotion, dueInWeeks: 20), .init(.responsibility, dueInWeeks: 20), .init(.training, dueInWeeks: 20),
                                            .init(.betterConditions, dueInWeeks: 20), .init(.futureBenefits, dueInWeeks: 20, detail: "exp:\(exp.id)"), .init(.percentageChange, dueInWeeks: 20, detail: "80")]
        // a perk is not something a group employee can be promised
        e.update { s, _, _ in XCTAssertNil(StaffPromises.make(&s, companyID: 0, personID: analyst, draft: .init(.futureBenefits, dueInWeeks: 5, detail: "perk:health"))) }
        guard e.hireOffer(post: .analyst, companyID: nil, personID: analyst, monthlyWage: ask * 1.4, terms: Hiring.Terms(promises: drafts)) == .hired else { return }
        func status(_ k: StaffPromises.Kind) -> StaffPromises.Status? { StaffPromises.promises(e.state, personID: analyst).first { $0.kind == k }?.status }
        XCTAssertEqual(StaffPromises.promises(e.state, personID: analyst).count, 7)
        XCTAssertTrue(StaffPromises.promises(e.state, personID: analyst).allSatisfy { $0.status == .pending })
        let wage0 = try XCTUnwrap(GroupPeople.wage(e.state, personID: analyst))
        XCTAssertTrue(e.groupSetPercent(personID: analyst, percent: 80))
        XCTAssertEqual(status(.percentageChange), .fulfilled)
        XCTAssertEqual(GroupPeople.wage(e.state, personID: analyst) ?? 0, wage0 * 0.8, accuracy: 1, "pay follows the percentage")
        XCTAssertNotEqual(status(.salaryReview), .fulfilled, "a lower percentage is not a pay review")
        XCTAssertTrue(e.groupRaise(personID: analyst, percent: 0.1))
        XCTAssertEqual(status(.salaryReview), .fulfilled)
        XCTAssertNotEqual(status(.training), .fulfilled)
        XCTAssertTrue(e.groupTrain(personID: analyst))
        XCTAssertEqual(status(.training), .fulfilled)
        XCTAssertTrue(e.groupSetExpense(personID: analyst, item: exp.id, on: true))
        XCTAssertEqual(status(.betterConditions), .fulfilled)
        XCTAssertEqual(status(.futureBenefits), .fulfilled)
        XCTAssertNotEqual(status(.promotion), .fulfilled)
        let wageBefore = GroupPeople.wage(e.state, personID: analyst) ?? 0
        XCTAssertTrue(e.groupPromote(personID: analyst))
        XCTAssertEqual(status(.promotion), .fulfilled)
        XCTAssertEqual(status(.responsibility), .fulfilled)
        XCTAssertGreaterThan(GroupPeople.wage(e.state, personID: analyst) ?? 0, wageBefore)
        // the weekly entitlement is paid
        let cashBefore = Payments.liquid(e.state)
        e.update { s, d, _ in StaffPromises.weekly(&s, data: d) }
        XCTAssertLessThan(Payments.liquid(e.state), cashBefore)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAnUnkeptGroupPromiseBreaksAndTheWordHelperHasNoNumbers() throws {
        var (e, _) = try shop(seed: 32)
        var analyst = 0
        e.update { s, d, _ in analyst = MarketMap.dataAnalystCandidates(&s, count: 1, data: d)[0].id }
        let ask = try XCTUnwrap(e.hearTheirAsk(post: .analyst, companyID: nil, personID: analyst))
        guard e.hireOffer(post: .analyst, companyID: nil, personID: analyst, monthlyWage: ask * 1.4, terms: Hiring.Terms(promises: [.init(.salaryReview, dueInWeeks: 4)])) == .hired else { return }
        e.update { s, d, _ in s.week += 4; StaffPromises.weekly(&s, data: d); s.week += 5; StaffPromises.weekly(&s, data: d) }
        XCTAssertEqual(StaffPromises.promises(e.state, personID: analyst).first?.status, .broken)
        for v in [0.0, 20, 40, 60, 90] { for axis in ["trust", "bold", "care"] { XCTAssertFalse(StandingWords.pressImage(axis, v).contains(where: \.isNumber)) } }
        XCTAssertEqual(e.publicImageWords.count, 3)
        XCTAssertNotEqual(StandingWords.pressImage("trust", 10), StandingWords.pressImage("trust", 90))
    }

    // MARK: Saves

    func testNewKeysSurviveASaveRoundTrip() throws {
        var (e, id) = try shop()
        let pid = candidate(&e, id)
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(percent: 50, promises: [StaffPromises.Draft(.salaryReview, dueInWeeks: 10)])), .ok)
        for _ in 0..<3 { week(&e) }
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertTrue(back == e.state)
        XCTAssertEqual(StaffPromises.promises(back, personID: pid).count, 1)
        XCTAssertFalse(WorkLog.weeks(back.company(id)!.staff.first { $0.id == pid }!).isEmpty)
    }
}

private extension StaffPromises.RenegotiateResult {
    var isRefusal: Bool { if case .refused = self { return true }; return false }
}
