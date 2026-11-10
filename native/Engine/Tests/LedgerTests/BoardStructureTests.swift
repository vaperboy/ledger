import XCTest
import GameCore
import Finance
import Businesses
import Employees
@testable import SaveSystem
@testable import Simulation

final class BoardStructureTests: XCTestCase {
    private func startCafe(_ e: inout GameEngine) throws -> Int {
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("start") }
        e.update { s, d, _ in
            _ = CompanySetup.quickSetup(&s, companyID: id, data: d)
            if let i = s.companyIndex(id) { s.companies[i].status = .open }
        }
        return id
    }
    private func twoCafes(seed: Int) throws -> (GameEngine, Int, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        let a = try startCafe(&e), b = try startCafe(&e)
        return (e, a, b)
    }
    private func makeBranch(_ e: inout GameEngine, branch b: Int, of a: Int) {
        e.update { s, _, _ in if let i = s.companyIndex(b) { s.companies[i].set("branch", .object(["of": .number(Double(a))])) } }
    }

    func testBranchSharesTheParentBoard() throws {
        var (e, a, b) = try twoCafes(seed: 61)
        XCTAssertNotEqual(e.boardKey(companyID: a), e.boardKey(companyID: b), "separate companies have separate boards")
        makeBranch(&e, branch: b, of: a)
        let key = try XCTUnwrap(e.boardKey(companyID: a))
        XCTAssertEqual(e.boardKey(companyID: b), key)
        XCTAssertFalse(e.boardKeys.contains("co:\(b)"), "the branch has no board of its own")
        XCTAssertEqual(Set(ManagerModel.boardCompanies(e.state, key: key).map { $0.id }), [a, b])
    }

    func testManagerIsNotADirector() throws {
        var (e, a, _) = try twoCafes(seed: 63)
        let cands = try XCTUnwrap(e.searchManagers(companyID: a))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: a, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        let key = try XCTUnwrap(e.boardKey(companyID: a))
        XCTAssertTrue(e.boardSeats(key: key).isEmpty, "nobody sits unless appointed")
        XCTAssertFalse(e.boardVoters(key: key).contains { $0.type == "ceo" && $0.votes }, "the manager attends but does not vote")
    }

    func testDirectorsDecideTheCEOWhenAnOutsideOwnerHasASeat() throws {
        var (e, a, b) = try twoCafes(seed: 64)
        let cands = try XCTUnwrap(e.searchManagers(companyID: a))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: a, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        let pick = try XCTUnwrap(e.searchManagers(companyID: b)?.first)
        e.update { s, _, _ in
            guard let i = s.companyIndex(a), var p = s.people[pick.id] else { return }
            p.employerID = -4; s.people[pick.id] = p
            s.companies[i].ownership = 70
            s.companies[i].set("holders", .array([.object(["name": .string(p.name), "pct": 30, "in": 0, "k27": "div", "sat": 60, "w0": 0, "npc": .number(Double(pick.id))])]))
            s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0, revenue: 50_000, profit: 9_000, cash: 10_000) }
            s.companies[i].set("brd", .object(["seats": .array([.object(["id": .number(Double(pick.id)), "kind": "adv", "r": "director", "t": "Director", "owner": true,
                                                                         "w0": 0])]),
                                               "last": -99, "mts": .array([])]))
        }
        var v = e.ceoVote(companyID: a)
        for w in 20..<60 { e.update { s, _, _ in s.week = w }; v = e.ceoVote(companyID: a); if !v.passes { break } }
        XCTAssertTrue(v.directorsDecide)
        XCTAssertEqual(v.directorsTotal, 2)
        XCTAssertFalse(v.passes)
        guard case .voteFailed = e.proposeCEOChange(companyID: a) else { return XCTFail("the board should block it") }
        XCTAssertNotNil(e.state.company(a)?.managerID)
        e.update { s, _, _ in
            guard let i = s.companyIndex(a) else { return }
            s.companies[i].set("ceoBlk", .null)
            s.companies[i].set("brd", .null)
        }
        XCTAssertFalse(e.ceoVote(companyID: a).directorsDecide)
    }
}
