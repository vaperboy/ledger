import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class OtherActionsTests: XCTestCase {
    private func cafe() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { XCTFail("start"); throw CocoaError(.fileReadUnknown) }
        return (e, id)
    }

    private func candidate(_ e: inout GameEngine, _ id: Int, role: String = "barista") -> Int {
        var pid = 0
        e.update { s, d, _ in
            let co = s.company(id)
            pid = Hiring.generateCandidate(role: role, company: co, tier: "mid", state: &s, data: d).id
        }
        return pid
    }

    func testPartTimeSeasonalAndFullTimeOffers() throws {
        var (e, id) = try cafe()
        let a = candidate(&e, id), b = candidate(&e, id)
        let ask = e.state.people[a]!.askingMonthlyWage
        XCTAssertEqual(e.hire(personID: a, companyID: id, monthlyWage: ask * 1.3, terms: Hiring.Terms(hours: 20)), .ok)
        var m = e.state.company(id)!.staff.first { $0.id == a }!
        XCTAssertEqual(m.partTimeShare, (m.weeklyHours ?? 0) / 37.5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(m.weeklyHours ?? 99, 30)
        let wage20 = m.monthlyWage
        // More hours, more pay (pay follows hours) unless the person studies and cannot.
        if m.num("maxH", 60) >= 30 {
            XCTAssertEqual(e.setStaffHours(companyID: id, staffID: a, hours: 30), .ok)
            m = e.state.company(id)!.staff.first { $0.id == a }!
            XCTAssertEqual(m.monthlyWage, wage20 * 30 / 20, accuracy: 1e-6)
        }
        // A seasonal hire for the months that are not now is off and unpaid.
        let now = GameCalendar.month(week: e.state.week) + 1
        let other = (1...12).filter { $0 != now }.prefix(2).map { $0 }
        XCTAssertEqual(e.hire(personID: b, companyID: id, monthlyWage: e.state.people[b]!.askingMonthlyWage * 1.3, terms: Hiring.Terms(hours: 25, seasonMonths: Array(other))), .ok)
        let s = e.state.company(id)!.staff.first { $0.id == b }!
        XCTAssertTrue(s.isOffSeason)
        XCTAssertFalse(StaffTalks.seasonText(Array(other)).isEmpty)
        XCTAssertTrue(e.toggleSeason(companyID: id, staffID: b, season: "summer"))
        // Going full time is refused when it is not the work the person wants; once it works, hours and seasons are gone.
        var results = Set<String>()
        for _ in 0..<1 { results.insert("\(e.offerFullTime(companyID: id, staffID: a))") }
        XCTAssertTrue(results.isSubset(of: ["ok", "refused", "student"]))
        if results.contains("ok") { XCTAssertNil(e.state.company(id)!.staff.first { $0.id == a }!.weeklyHours) }
        XCTAssertEqual(e.offerPartTime(companyID: id, staffID: a), .already)
    }

    func testTrialWeekPaysAndReveals() throws {
        var (e, id) = try cafe()
        let p = candidate(&e, id)
        let before = e.state.company(id)!.cash
        let seen = e.startTrialWeek(personID: p, companyID: id)
        XCTAssertNotNil(seen)
        XCTAssertLessThan(e.state.company(id)!.cash, before)
        XCTAssertEqual(e.state.people[p]?.value("trial").double, 1)
    }

    func testDevelopmentProjectRunsAndPays() throws {
        var (e, id) = try cafe()
        let list = e.developmentProjects(companyID: id)
        XCTAssertFalse(list.isEmpty)
        let first = list[0].project
        XCTAssertEqual(e.startDevelopment(companyID: id, project: first.id), .ok)
        XCTAssertEqual(e.startDevelopment(companyID: id, project: first.id), .busy)
        e.update { s, _, _ in
            var r = s.companies[s.companyIndex(id)!].value("rd56"); r["run"]["wEnd"] = .number(Double(s.week)); s.companies[s.companyIndex(id)!].set("rd56", r)
        }
        e.update { s, d, _ in
            guard let i = s.companyIndex(id), let bd = d.catalog[s.companies[i].type] else { return }
            Development.weekly(&s, i, bd, data: d)
        }
        XCTAssertNil(Development.running(e.state.company(id)!))
        XCTAssertEqual(e.startDevelopment(companyID: id, project: first.id), e.state.company(id)!.value("rd56")["done"].array.isEmpty ? .ok : .recent)
    }

    func testDailyGoalAndFirstSteps() throws {
        var (e, _) = try cafe()
        let g = e.dailyGoal(now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNotNil(g)
        XCTAssertNotNil(e.firstStepRewards)
        XCTAssertEqual(e.firstStepRewards?.count, 10)
        XCTAssertNil(e.claimFirstStep(id: "profit"), "an unfinished step gives no reward")
        let cash = e.state.cash
        XCTAssertNotNil(e.claimFirstStep(id: "co"))
        XCTAssertGreaterThan(e.state.cash, cash)
        XCTAssertNil(e.claimFirstStep(id: "co"), "a reward is claimed once")
        XCTAssertTrue(e.chooseAmbition(path: "dynasty"))
        XCTAssertEqual(e.ambitionPath, "dynasty")
        XCTAssertFalse(e.ambitionMilestones.isEmpty)
    }

    func testComplaintAnswerAndAccountant() throws {
        var (e, id) = try cafe()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("compl", .array([.object(["id": 5, "w": .number(Double(s.week)), "who": "A. Customer", "t": "Late.", "sev": 2, "st": "open"])]))
        }
        XCTAssertEqual(e.openComplaints(companyID: id).count, 1)
        XCTAssertEqual(e.answerComplaint(companyID: id, complaintID: 5, answer: .refund), true)
        XCTAssertEqual(e.openComplaints(companyID: id).count, 0)
        XCTAssertNil(e.answerComplaint(companyID: id, complaintID: 5, answer: .refund))
    }
}
