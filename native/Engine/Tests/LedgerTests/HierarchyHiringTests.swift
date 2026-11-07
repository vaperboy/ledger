import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// ChainHierarchy: the higher rank hires one level down (CEO -> chain manager -> regional manager -> store manager), within the authority and budget the
/// owner gave, and asks the owner when it has neither. The owner can always hire into the post themselves.
final class HierarchyHiringTests: XCTestCase {
    /// A chain of `count` open stores in the player's city, none with a manager, each with cash for a manager's pay.
    private func chain(_ count: Int) throws -> (e: GameEngine, chain: Int, stores: [Int]) {
        var e = try ChainsTests.engine("NO")
        let first = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, first)
        let id = try XCTUnwrap(e.makeChain(companyID: first, name: "Test Cafe"))
        var stores = [first]
        for _ in 1..<count { if case .success(let s) = e.openChainStore(chainID: id, cityID: e.state.player.cityID, size: 1) { stores.append(s) } }
        guard stores.count == count else { throw XCTSkip("chain stores could not be opened") }
        e.update { s, _, _ in
            for sid in stores {
                guard let i = s.companyIndex(sid) else { continue }
                s.companies[i].status = .open
                s.companies[i].ownerHours = 0
                s.companies[i].managerID = nil
                s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: 400_000, profit: 90_000, cash: 0) }
                Payments.injectCash(&s, companyID: sid, amount: 20_000_000)
            }
        }
        return (e, id, stores)
    }

    private func hireExec(_ e: inout GameEngine, _ level: ManagerModel.ExecLevel, chain: Int, city: String? = nil, authority: Int, buy: Double? = nil) throws -> Int {
        let cand = try XCTUnwrap(e.searchExecutive(level)?.first)
        XCTAssertEqual(e.hireExecutive(level, personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3, chainID: chain, city: city), .ok)
        let scope = "chain:\(chain)" + (city.map { ":\($0)" } ?? "")
        let rid = try XCTUnwrap(ManagerModel.regionals(e.state).first { $0["scope"].string == scope }?["id"].int)
        e.update { s, _, _ in ManagerModel.setExecutiveAuthority(&s, level: level, chainID: chain, regionalID: rid, authority: authority, buy: buy) }
        return cand.id
    }

    /// Run the weekly step a number of times, three weeks apart (a search that found nobody is retried after two).
    private func run(_ e: inout GameEngine, times: Int = 8) {
        for _ in 0..<times { e.update { s, d, _ in s.week += 3; HierarchyHiring.weekly(&s, data: d) } }
    }

    func testRegionalManagerHiresEachStoreManagerInASixStoreChain() throws {
        var (e, cid, stores) = try chain(6)
        XCTAssertNil(e.state.rest["hier"], "nothing is saved until a hire is tried")
        let city = e.state.player.cityID
        let regional = try hireExec(&e, .region, chain: cid, city: city, authority: 2)
        let boss = try XCTUnwrap(HierarchyHiring.appointer(e.state, post: .storeManager(companyID: stores[0]), data: e.data))
        XCTAssertEqual(boss.kind, "region"); XCTAssertEqual(boss.personID, regional)
        // the vacancy names who hires it
        let v = try XCTUnwrap(e.teamOverview().vacancies.first { $0.id == "mgr-\(stores[0])" })
        XCTAssertEqual(v.post, "mgr"); XCTAssertEqual(v.hirerName, boss.name); XCTAssertEqual(v.hirerAuthority, 2)
        run(&e)
        for sid in stores {
            let co = try XCTUnwrap(e.state.company(sid))
            let mid = try XCTUnwrap(co.managerID, "store \(sid) still has no manager")
            XCTAssertEqual(e.state.people[mid]?.employerID, sid)
            XCTAssertNotEqual(mid, regional)
        }
        // the owner is told by the regional manager who did it
        XCTAssertTrue(e.state.inbox.contains { $0.kind == "info" && $0.from == boss.name && $0.title.contains("appointed as") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testChainManagerWithoutRegionalLayerHiresStoreManagersDirectly() throws {
        var (e, cid, stores) = try chain(3)
        let cm = try hireExec(&e, .chainmgr, chain: cid, authority: 2)
        let boss = try XCTUnwrap(HierarchyHiring.appointer(e.state, post: .storeManager(companyID: stores[1]), data: e.data))
        XCTAssertEqual(boss.kind, "chainmgr"); XCTAssertEqual(boss.personID, cm)
        run(&e)
        for sid in stores { XCTAssertNotNil(e.state.company(sid)?.managerID, "store \(sid) still has no manager") }
        XCTAssertEqual(ManagerModel.regionals(e.state).count, 1, "three stores in a city do not call for a regional manager")
    }

    func testWithoutAuthorityTheBossAsksTheOwnerAndTheOwnerDecides() throws {
        var (e, cid, stores) = try chain(2)
        _ = try hireExec(&e, .chainmgr, chain: cid, authority: 0)
        run(&e, times: 4)
        XCTAssertTrue(stores.allSatisfy { e.state.company($0)?.managerID == nil }, "asking first means nobody is hired yet")
        let ask = try XCTUnwrap(e.openDecisions.first { $0.actionID == HierarchyHiring.action }, "the owner is asked")
        XCTAssertEqual(ask.options.count, 2)
        let target = ask.companyID
        XCTAssertTrue(e.answer(messageID: ask.id, option: 0))
        XCTAssertNotNil(e.state.company(target)?.managerID, "the owner approved the person named")
        // a second request is declined: that store is left alone for a while
        let other = try XCTUnwrap(e.openDecisions.first { $0.actionID == HierarchyHiring.action })
        let otherStore = other.companyID
        XCTAssertTrue(e.answer(messageID: other.id, option: 1))
        run(&e, times: 1)
        XCTAssertNil(e.state.company(otherStore)?.managerID)
        XCTAssertFalse(e.openDecisions.contains { $0.actionID == HierarchyHiring.action && $0.companyID == otherStore }, "declined: not asked again within eight weeks")
    }

    func testAboveTheLimitTheBossAsksEvenWithAuthorityOne() throws {
        var (e, cid, stores) = try chain(2)
        _ = try hireExec(&e, .chainmgr, chain: cid, authority: 1, buy: 1)
        run(&e, times: 4)
        XCTAssertTrue(stores.allSatisfy { e.state.company($0)?.managerID == nil })
        XCTAssertNotNil(e.openDecisions.first { $0.actionID == HierarchyHiring.action })
    }

    func testNobodyAboveMeansTheVacancyStaysWithTheOwner() throws {
        var (e, _, stores) = try chain(2)
        run(&e, times: 4)
        XCTAssertTrue(stores.allSatisfy { e.state.company($0)?.managerID == nil })
        XCTAssertTrue(e.openDecisions.filter { $0.actionID == HierarchyHiring.action }.isEmpty, "no boss, no request")
        let v = try XCTUnwrap(e.teamOverview().vacancies.first { $0.id == "mgr-\(stores[0])" })
        XCTAssertNil(v.hirerName)
        XCTAssertEqual(e.vacancyHirerLine(v), "")
        // the owner can search and hire into it
        let route = try XCTUnwrap(e.vacancyRoute(v))
        XCTAssertEqual(route.post, .manager); XCTAssertEqual(route.companyID, stores[0])
        let list = try XCTUnwrap(e.searchVacancy(v))
        XCTAssertFalse(list.isEmpty)
    }

    func testChainManagerAppointsARegionalManagerForABigCity() throws {
        var (e, cid, _) = try chain(4)
        _ = try hireExec(&e, .chainmgr, chain: cid, authority: 2)
        let city = e.state.player.cityID
        let v = try XCTUnwrap(e.teamOverview().vacancies.first { $0.id == "region-\(cid)-\(city)" })
        XCTAssertEqual(v.post, "region"); XCTAssertEqual(v.hirerAuthority, 2)
        run(&e)
        XCTAssertTrue(ManagerModel.regionals(e.state).contains { $0["scope"].string == "chain:\(cid):\(city)" }, "the chain manager appointed the regional manager")
        XCTAssertNil(e.teamOverview().vacancies.first { $0.id == "region-\(cid)-\(city)" })
    }

    func testTheBossAboveAlsoHiresOrdinaryStaffWhileTheStoreHasNoManager() throws {
        var (e, cid, stores) = try chain(2)
        let sid = stores[1]
        let role = try XCTUnwrap(e.state.company(sid)?.staff.first?.role)
        let target = (e.state.company(sid)?.staff.count ?? 0) + 1
        var before = ManagerHiring.verdict(e.state, companyID: sid, role: role, target: target, data: e.data)
        if case .no(let why) = before { XCTAssertTrue(why.contains("Without a manager"), why) }
        _ = try hireExec(&e, .chainmgr, chain: cid, authority: 1)
        before = ManagerHiring.verdict(e.state, companyID: sid, role: role, target: target, data: e.data)
        if case .no(let why) = before { XCTAssertFalse(why.contains("Without a manager"), "the chain manager has the authority: \(why)") }
    }
}
