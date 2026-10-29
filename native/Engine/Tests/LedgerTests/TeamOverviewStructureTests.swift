import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Who employs whom, by structure (owner's table): stand-alone companies, a chain, a holding, several separate companies under one owner.
/// The group office is something the owner sets up; before that Team lists only each company's own posts.
final class TeamOverviewStructureTests: XCTestCase {
    private func open(_ e: inout GameEngine, _ id: Int, ownerHours: Double = 0) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].ownerHours = ownerHours
        }
    }

    /// Give a company a headcount by repeating its first staff member (ids are irrelevant to the headcount rules).
    private func scale(_ e: inout GameEngine, _ id: Int, to n: Int) throws {
        var done = false
        e.update { s, _, _ in
            guard let i = s.companyIndex(id), let first = s.companies[i].staff.first else { return }
            s.companies[i].staff = Array(repeating: first, count: n); done = true
        }
        if !done { throw XCTSkip("trade starts with no staff") }
    }

    private func groupScoped(_ o: TeamOverview) -> (members: [TeamOverview.Member], vacancies: [TeamOverview.Vacancy]) {
        (o.members.filter { $0.scope == "group" }, o.vacancies.filter { $0.scope == "group" })
    }

    func testSeparateCompaniesShowNoGroupPostsUntilTheOwnerSetsUpAnOffice() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe"), b = ChainsTests.start(&e, "cafe")
        open(&e, a); open(&e, b)
        var o = e.teamOverview()
        XCTAssertFalse(o.groupOffice.established)
        let g = groupScoped(o)
        XCTAssertTrue(g.members.isEmpty && g.vacancies.isEmpty, "two stand-alone companies: only each company's own posts")
        XCTAssertFalse(e.groupOfficeEstablished)
        // The engine refuses a group managing director before the office exists.
        let cand = try XCTUnwrap(e.searchExecutive(.md)?.first)
        XCTAssertEqual(e.hireExecutive(.md, personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3), .refused)
        XCTAssertTrue(e.groupManagingDirector.isNull)
        // The owner establishes the office (the free home office): the group posts now exist, each employed by the group office.
        XCTAssertEqual(e.rentOffice(tier: "home"), .ok)
        o = e.teamOverview()
        XCTAssertTrue(o.groupOffice.established)
        XCTAssertEqual(o.groupOffice.employer, "Your group office")
        let md = try XCTUnwrap(o.vacancies.first { $0.id == "md" })
        XCTAssertEqual(md.scope, "group"); XCTAssertEqual(md.employer, "Your group office"); XCTAssertFalse(md.needed)
        XCTAssertNotNil(o.vacancies.first { $0.id == "hq-pa" }, "the personal assistant is the one role a home office has a desk for")
        XCTAssertNil(o.vacancies.first { $0.id == "hq-law" }, "the in-house lawyer still opens with 3 companies (Headquarters.unlocked)")
        XCTAssertTrue(o.vacancies.filter { $0.scope == "group" }.allSatisfy { $0.employer == "Your group office" })
        // Hired, the person is listed with the group scope and the group office as employer.
        XCTAssertEqual(e.hireExecutive(.md, personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3), .ok)
        o = e.teamOverview()
        let m = try XCTUnwrap(o.members.first { $0.id == "md" })
        XCTAssertEqual(m.role, "Group managing director"); XCTAssertEqual(m.scope, "group"); XCTAssertEqual(m.employer, "Your group office")
        XCTAssertNil(o.vacancies.first { $0.id == "md" })
    }

    func testGroupOfficeIsCarriedByAHoldingWithSpareCashElseByTheOwner() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe"), b = ChainsTests.start(&e, "cafe")
        open(&e, a); open(&e, b)
        XCTAssertEqual(e.rentOffice(tier: "cow"), .ok)
        guard case .success(let hid) = e.createHolding(name: "Alpha Holding", companies: [a, b]) else { throw XCTSkip("holding could not be created") }
        e.update { s, _, _ in if let i = s.companyIndex(hid) { s.companies[i].cash = 0 } }
        XCTAssertEqual(e.teamOverview().groupOffice.employer, "Your group office", "a holding without spare cash does not carry the office")
        e.update { s, _, _ in if let i = s.companyIndex(hid) { s.companies[i].cash = 1_000_000_000_000 } }
        XCTAssertEqual(e.teamOverview().groupOffice.employer, "Alpha Holding")
        XCTAssertTrue(e.teamOverview().vacancies.filter { $0.id.hasPrefix("hq-") }.allSatisfy { $0.employer == "Alpha Holding" })
    }

    func testStandAloneCompanyGetsDepartmentHeadsByHeadcountEmployedByItself() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        open(&e, id, ownerHours: 40)
        XCTAssertTrue(e.teamOverview().vacancies.filter { $0.companyID == id && $0.id.hasPrefix("slot-") }.isEmpty, "a small company has no department heads")
        try scale(&e, id, to: 30)
        let o = e.teamOverview()
        let name = try XCTUnwrap(e.state.company(id)?.name)
        let heads = o.vacancies.filter { $0.companyID == id && $0.id.hasPrefix("slot-") }
        XCTAssertTrue(heads.contains { $0.title == "HR manager" }, "HR opens at the existing ManagerModel.teamRoles threshold (25 people)")
        XCTAssertTrue(heads.contains { $0.title == "Finance manager" })
        XCTAssertTrue(heads.contains { $0.title == "Operations manager" })
        XCTAssertTrue(heads.allSatisfy { $0.employer == name && $0.scope != "group" && $0.scope != "chain" })
        XCTAssertTrue(groupScoped(o).vacancies.isEmpty && groupScoped(o).members.isEmpty, "one company, no group posts")
        // Fill the HR post: the person is the company's employee.
        let cand = try XCTUnwrap(e.searchTeam(companyID: id, key: "hr")?.first)
        XCTAssertEqual(e.hireTeam(companyID: id, key: "hr", personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3), .ok)
        let hr = try XCTUnwrap(e.teamOverview().members.first { $0.role == "HR manager" })
        XCTAssertEqual(hr.employer, name); XCTAssertEqual(hr.scope, "company"); XCTAssertEqual(hr.companyID, id)
    }

    func testChainLeadershipBelongsToTheChain() throws {
        var e = try ChainsTests.engine("NO")
        let first = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, first)
        let chain = try XCTUnwrap(e.makeChain(companyID: first, name: "Test Cafe"))
        var stores = [first]
        for _ in 0..<2 { if case .success(let id) = e.openChainStore(chainID: chain, cityID: e.state.player.cityID, size: 1) { stores.append(id) } }
        for id in stores { open(&e, id) }
        guard stores.count >= 2 else { throw XCTSkip("chain stores could not be opened") }
        var o = e.teamOverview()
        let v = try XCTUnwrap(o.vacancies.first { $0.id == "chainmgr-\(chain)" })
        XCTAssertEqual(v.employer, "Test Cafe"); XCTAssertEqual(v.scope, "chain")
        XCTAssertTrue(groupScoped(o).vacancies.isEmpty, "a chain does not create group posts")
        let cand = try XCTUnwrap(e.searchExecutive(.chainmgr)?.first)
        XCTAssertEqual(e.hireExecutive(.chainmgr, personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3, chainID: chain, city: nil), .ok)
        o = e.teamOverview()
        let m = try XCTUnwrap(o.members.first { $0.role == "Chain manager" })
        XCTAssertEqual(m.employer, "Test Cafe"); XCTAssertEqual(m.scope, "chain"); XCTAssertEqual(m.chainID, chain)
        XCTAssertTrue(groupScoped(o).members.isEmpty)
    }

    func testHoldingLeadershipBelongsToTheHolding() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe"), b = ChainsTests.start(&e, "cafe")
        open(&e, a); open(&e, b)
        guard case .success(let hid) = e.createHolding(name: "Alpha Holding", companies: [a, b]) else { throw XCTSkip("holding could not be created") }
        var o = e.teamOverview()
        let v = try XCTUnwrap(o.vacancies.first { $0.companyID == hid && $0.id.hasSuffix("ceo") })
        XCTAssertEqual(v.scope, "group"); XCTAssertEqual(v.employer, "Alpha Holding")
        XCTAssertNil(o.vacancies.first { $0.id == "md" }, "the holding's own leadership is not a group office post")
        let cand = try XCTUnwrap(e.searchTeam(companyID: hid, key: "ceo")?.first)
        XCTAssertEqual(e.hireTeam(companyID: hid, key: "ceo", personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3), .ok)
        o = e.teamOverview()
        let m = try XCTUnwrap(o.members.first { $0.companyID == hid })
        XCTAssertEqual(m.employer, "Alpha Holding"); XCTAssertEqual(m.scope, "group")
        XCTAssertFalse(o.groupOffice.established, "a holding is not a group office")
    }

    func testGroupOfficeAndItsPeopleSurviveASaveRoundTrip() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe"), b = ChainsTests.start(&e, "cafe")
        open(&e, a); open(&e, b)
        XCTAssertFalse(e.teamOverview().groupOffice.established)
        XCTAssertTrue(e.state.rest["office"]?["set"].isNull ?? true, "the free home-office record every new game starts with is not a group office")
        XCTAssertEqual(e.rentOffice(tier: "home"), .ok)
        let cand = try XCTUnwrap(e.searchExecutive(.md)?.first)
        XCTAssertEqual(e.hireExecutive(.md, personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3), .ok)
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertEqual(back, e.state)
        let was = e.teamOverview()
        e.update { s, _, _ in s = back }
        let now = e.teamOverview()
        XCTAssertEqual(now.members.map { $0.id }, was.members.map { $0.id })
        XCTAssertEqual(now.vacancies.map { $0.id }, was.vacancies.map { $0.id })
        XCTAssertEqual(now.members.first { $0.id == "md" }?.employer, "Your group office")
        XCTAssertTrue(now.groupOffice.established)
    }
}
