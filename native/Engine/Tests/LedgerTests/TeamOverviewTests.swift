import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The Team tab's read model: who runs each company and what needs the owner, in the scenarios the screen must handle.
final class TeamOverviewTests: XCTestCase {
    private func open(_ e: inout GameEngine, _ id: Int, ownerHours: Double = 0) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].ownerHours = ownerHours
        }
    }

    private func hireManager(_ e: inout GameEngine, _ id: Int) throws {
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
    }

    func testOneStoreRunByTheOwner() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        open(&e, id, ownerHours: 40)
        let o = e.teamOverview()
        let line = try XCTUnwrap(o.companies.first { $0.id == id })
        XCTAssertEqual(line.managedBy, TeamOverview.you)
        XCTAssertFalse(line.delegated)
        XCTAssertEqual(line.authority, -1)
        XCTAssertFalse(o.issues.contains { $0.kind == .vacancy && $0.companyID == id }, "the owner works there")
    }

    func testStoreNobodyRunsIsAVacancyAndAManagerFillsIt() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        open(&e, id, ownerHours: 0)
        XCTAssertTrue(e.teamOverview().issues.contains { $0.kind == .vacancy && $0.companyID == id && $0.needsOwner })
        try hireManager(&e, id)
        let o = e.teamOverview()
        let line = try XCTUnwrap(o.companies.first { $0.id == id })
        XCTAssertTrue(line.delegated)
        XCTAssertNotEqual(line.managedBy, TeamOverview.you)
        XCTAssertGreaterThanOrEqual(line.authority, 0)
        XCTAssertFalse(o.issues.contains { $0.kind == .vacancy && $0.companyID == id })
    }

    func testStaffTroubleIsTheManagersJobInADelegatedStoreAndYoursOtherwise() throws {
        var e = try ChainsTests.engine("UK")
        let mine = ChainsTests.start(&e, "cafe"), theirs = ChainsTests.start(&e, "cafe")
        open(&e, mine, ownerHours: 40); open(&e, theirs)
        try hireManager(&e, theirs)
        e.update { s, _, _ in
            for id in [mine, theirs] {
                let i = s.companyIndex(id)!
                guard !s.companies[i].staff.isEmpty else { continue }
                s.companies[i].staff[0].sickUntilWeek = s.week + 2
            }
        }
        let o = e.teamOverview()
        let a = o.issues.first { $0.kind == .staffSick && $0.companyID == mine }
        let b = o.issues.first { $0.kind == .staffSick && $0.companyID == theirs }
        if let a { XCTAssertTrue(a.needsOwner) }
        if let b { XCTAssertFalse(b.needsOwner, "the store manager handles sickness in a store they run") }
        XCTAssertTrue(a != nil || b != nil, "at least one store has staff")
    }

    func testTenStoresEachHaveALineAndLateWagesAlwaysReachTheOwner() throws {
        var e = try ChainsTests.engine("UK")
        let ids = (0..<10).map { _ in ChainsTests.start(&e, "cafe") }
        for id in ids { open(&e, id, ownerHours: 0) }
        try hireManager(&e, ids[0])
        e.update { s, _, _ in s.companies[s.companyIndex(ids[0])!].set("pr29", .object(["late": .object(["d0": 1, "why": "cash", "mi": 0, "owe": 1000, "n": 3])])) }
        let o = e.teamOverview()
        XCTAssertEqual(Set(o.companies.map { $0.id }).intersection(ids).count, 10)
        let late = try XCTUnwrap(o.issues.first { $0.kind == .payroll && $0.companyID == ids[0] })
        XCTAssertTrue(late.needsOwner, "wages are the owner's problem even where a manager runs the store")
        XCTAssertEqual(o.issues.first?.severity, 3, "the most urgent owner issue comes first")
    }

    func testChainWithRegionalManagerAndChainVacancy() throws {
        var e = try ChainsTests.engine("NO")
        let first = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, first)
        let chain = try XCTUnwrap(e.makeChain(companyID: first, name: "Test Cafe"))
        var stores = [first]
        for _ in 0..<4 { if case .success(let id) = e.openChainStore(chainID: chain, cityID: e.state.player.cityID, size: 1) { stores.append(id) } }
        for id in stores { open(&e, id) }
        if stores.count >= 5 { XCTAssertTrue(e.teamOverview().issues.contains { $0.kind == .chainVacancy && $0.chainID == chain }) }
        let cand = try XCTUnwrap(e.searchExecutive(.region)?.first)
        XCTAssertEqual(e.hireExecutive(.region, personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3, chainID: chain, city: e.state.player.cityID), .ok)
        let o = e.teamOverview()
        let line = try XCTUnwrap(o.companies.first { $0.id == first })
        XCTAssertEqual(line.chainID, chain)
        XCTAssertEqual(line.managerTitle, "Regional manager", "with no store manager the regional manager runs the store")
        XCTAssertEqual(line.managedBy, e.state.people[cand.id]?.name)
    }

    func testHoldingManagingDirectorRunsTheCompaniesUnderIt() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe"), other = ChainsTests.start(&e, "cafe")
        open(&e, id); open(&e, other)
        // The engine offers a holding a managing director once two companies sit under it.
        guard case .success(let hid) = e.createHolding(name: "H", companies: [id, other]) else { throw XCTSkip("holding could not be created") }
        let slot = try XCTUnwrap(e.teamSlots(companyID: hid).first { $0.key == "ceo" })
        let cand = try XCTUnwrap(e.searchTeam(companyID: hid, key: slot.key)?.first)
        XCTAssertEqual(e.hireTeam(companyID: hid, key: slot.key, personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3), .ok)
        let line = try XCTUnwrap(e.teamOverview().companies.first { $0.id == id })
        XCTAssertEqual(line.holdingID, hid)
        XCTAssertEqual(line.managerTitle, "Managing director")
        XCTAssertTrue(line.delegated)
    }

    func testOpenDecisionIsListedOnceForItsCompany() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        open(&e, id)
        e.update { s, _, _ in s.addMessage(kind: "ask", from: "Test", title: "Decide", body: "", companyID: id, tone: "n", status: "open", options: [.option("OK")], action: "test") }
        let d = e.teamOverview().issues.filter { $0.kind == .decision && $0.title == "Decide" }
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.companyID, id)
        XCTAssertNotNil(d.first?.messageID)
        XCTAssertEqual(d.first?.beyondAuthority, false, "an ordinary decision is not an escalation")
    }

    func testManagersRequestAboveTheirAuthorityIsMarked() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        open(&e, id)
        try hireManager(&e, id)
        let name = try XCTUnwrap(e.state.company(id)?.managerID.flatMap { e.state.people[$0]?.name })
        e.update { s, _, _ in s.addMessage(kind: "ask", from: name, title: "Buy an oven", body: "", companyID: id, tone: "n", status: "open", options: [.option("Approve"), .option("Decline")], action: "prop") }
        let d = try XCTUnwrap(e.teamOverview().issues.first { $0.kind == .decision && $0.title == "Buy an oven" })
        XCTAssertTrue(d.beyondAuthority)
        XCTAssertTrue(d.needsOwner)
        XCTAssertTrue(d.detail.hasPrefix(name), "says who asked")
    }

    func testVacanciesListStoreChainAndGroupPosts() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe"), b = ChainsTests.start(&e, "cafe")
        open(&e, a, ownerHours: 0); open(&e, b, ownerHours: 40)
        let o = e.teamOverview()
        let store = o.vacancies.first { $0.id == "mgr-\(a)" }
        if e.state.company(a)?.staff.isEmpty == false {
            XCTAssertEqual(store?.scope, "store")
            XCTAssertEqual(store?.needed, true, "no one runs it")
            XCTAssertEqual(o.vacancies.first?.needed, true, "needed posts come first")
        }
        XCTAssertNil(o.vacancies.first { $0.id == "mgr-\(b)" }, "the owner runs it")
        XCTAssertEqual(o.vacancies.first { $0.id == "md" }?.scope, "group", "two companies make room for a group managing director")
        XCTAssertEqual(o.vacancies.first { $0.id == "md" }?.needed, false)
        try hireManager(&e, a)
        XCTAssertNil(e.teamOverview().vacancies.first { $0.id == "mgr-\(a)" })
    }

    func testChainPostsAreVacanciesUntilFilled() throws {
        var e = try ChainsTests.engine("NO")
        let first = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, first)
        let chain = try XCTUnwrap(e.makeChain(companyID: first, name: "Test Cafe"))
        open(&e, first)
        let o = e.teamOverview()
        XCTAssertEqual(o.vacancies.first { $0.id == "chainmgr-\(chain)" }?.scope, "chain")
        XCTAssertNotNil(o.vacancies.first { $0.id == "ceo56-\(chain)" })
        XCTAssertEqual(o.companies.first { $0.id == first }?.chainName, "Test Cafe")
    }

    func testScorecardsAndProfitShareAndDuties() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        open(&e, id)
        XCTAssertNil(e.managerProfitBonusPreview(companyID: id, share: 0.1), "no manager, no profit share")
        XCTAssertTrue(e.managerDuties(companyID: id).isEmpty)
        try hireManager(&e, id)
        let o = e.teamOverview()
        let line = try XCTUnwrap(o.companies.first { $0.id == id })
        XCTAssertNotNil(line.score)
        XCTAssertNotNil(line.managerQuality)
        XCTAssertEqual(o.scorecards.map { $0.id }, [id])
        XCTAssertEqual(o.scorecards.first?.score, e.managerScorecard(companyID: id)?.score)

        let p0 = try XCTUnwrap(e.managerProfitBonusPreview(companyID: id, share: 0.1))
        XCTAssertGreaterThanOrEqual(p0.monthlyCost, 0)
        e.setManagerProfitBonus(companyID: id, share: 0.5)
        XCTAssertEqual(e.managerProfitBonusPreview(companyID: id, share: 0)?.current, 0.3, "the engine caps the share at 30%")

        XCTAssertEqual(e.managerDuties(companyID: id).first?.manager, true, "the manager looks after it by default")
        e.setManagerDuty(companyID: id, duty: "prem", manager: false)
        XCTAssertEqual(e.managerDuties(companyID: id).first?.manager, false)
    }

    func testFiftyCompaniesStayCheap() throws {
        var e = try ChainsTests.engine("UK")
        let ids = (0..<50).map { _ in ChainsTests.start(&e, "cafe") }
        for id in ids { open(&e, id, ownerHours: 0) }
        let o = e.teamOverview()
        XCTAssertEqual(Set(o.companies.map { $0.id }).intersection(ids).count, 50)
        XCTAssertEqual(Set(o.vacancies.map { $0.id }).count, o.vacancies.count, "vacancy ids are unique")
    }
}
