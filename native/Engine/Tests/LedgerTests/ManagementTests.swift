import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Managers, assistant managers, promotions: they run, the owner steps back, and the books still balance.
final class ManagementTests: XCTestCase {
    private func gameWithCafe(seed: Int = 5) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        return (e, id)
    }

    func testHireManagerRunsCompanyAndOwnerSteps_Back() throws {
        var (e, id) = try gameWithCafe()
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(cands.count, 4)
        XCTAssertNotNil(e.interviewManager(personID: cands[0].id, skill: "ops"))
        let pick = cands[0]
        var r = e.hireManager(personID: pick.id, companyID: id, monthlyWage: pick.askingMonthlyWage * 1.2)
        XCTAssertEqual(r, .ok)
        XCTAssertEqual(e.state.company(id)?.managerID, pick.id)
        XCTAssertEqual(e.state.company(id)?.ownerHours, 0)
        XCTAssertEqual(e.hireManager(personID: pick.id, companyID: id, monthlyWage: 1), .taken)
        e.setManagerAuthority(companyID: id, level: 2)
        XCTAssertEqual(e.state.company(id)?.value("auth")["lvl"].int, 2)
        XCTAssertNotNil(e.askManager(companyID: id, key: "price_up"))
        for _ in 0..<(30 * 7) {
            e.nextDay()
            for m in e.openDecisions where ["prop", "mgrraise", "mgrpoach", "staffx"].contains(m.actionID) { e.answer(messageID: m.id, option: 0) }
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        let sev = e.dismissManager(companyID: id)
        XCTAssertGreaterThan(sev, 0)
        XCTAssertNil(e.state.company(id)?.managerID)
        r = e.hireManager(personID: cands[1].id, companyID: id, monthlyWage: cands[1].askingMonthlyWage * 1.2)
        XCTAssertEqual(r, .ok)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testResignationRunsItsNotice() throws {
        var (e, id) = try gameWithCafe(seed: 9)
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        _ = e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.2)
        e.update { s, _, _ in ManagerModel.resign(&s, companyIndex: s.companyIndex(id)!, why: "test") }
        XCTAssertFalse(e.state.company(id)!.value("mgrNotice").isNull)
        for _ in 0..<(32 * 7) { e.nextDay() }
        XCTAssertNil(e.state.company(id)?.managerID, "the manager leaves after the notice")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAssistantAndPromotion() throws {
        var (e, id) = try gameWithCafe(seed: 3)
        let a = try XCTUnwrap(e.searchAssistants(companyID: id))
        XCTAssertEqual(e.hireAssistant(personID: a[0].id, companyID: id, monthlyWage: a[0].askingMonthlyWage * 1.2), .ok)
        XCTAssertTrue(e.toggleAssistantDuty(companyID: id, duty: "comp"))
        XCTAssertTrue(e.toggleAssistantDuty(companyID: id, duty: "paper"))
        XCTAssertFalse(e.toggleAssistantDuty(companyID: id, duty: "equip"), "two jobs at most")
        for _ in 0..<(8 * 7) { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // promote a worker to run the company
        let roles = e.hireableRoles(companyID: id)
        let c = e.searchWorkers(companyID: id, role: roles[0], mode: .agency)
        let w = c[0]
        XCTAssertEqual(e.hire(personID: w.id, companyID: id, monthlyWage: w.askingMonthlyWage * 1.3), .ok)
        let posts = ManagerModel.promotionPosts(e.state, companyID: id, personID: w.id, data: e.data)
        guard let post = posts.first(where: { $0.kind == "mgr" && $0.companyID == id }) else { return XCTFail("no manager post") }
        // a low offer is answered with a counter (they ask for more), never with a refusal
        guard case .counter(let ask, _, _) = e.contractPropose(companyID: id, personID: w.id, proposal: .init(.promotion, amount: post.ask * 0.5, choice: post.id)) else { return XCTFail("a low offer gets a counter") }
        XCTAssertGreaterThanOrEqual(ask, post.ask * 0.5)
        guard case .agreed = e.contractPropose(companyID: id, personID: w.id, proposal: .init(.promotion, amount: max(ask, post.ask), choice: post.id)) else { return XCTFail("fair offer should be accepted") }
        XCTAssertEqual(e.state.company(id)?.managerID, w.id)
        XCTAssertFalse(e.state.company(id)!.staff.contains { $0.id == w.id })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
