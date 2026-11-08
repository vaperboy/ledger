import XCTest
import GameCore
import Finance
import Businesses
import Employees
@testable import SaveSystem
@testable import Simulation

/// Which board a company sits on (branches share the parent's), who is seated (never a manager by default) and who decides on the CEO.
final class BoardStructureTests: XCTestCase {
    private func startCafe(_ e: inout GameEngine) throws -> Int {
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 6_000_000) else { throw XCTSkip("start") }
        e.update { s, d, _ in _ = CompanySetup.quickSetup(&s, companyID: id, data: d) }
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

    func testBranchUnderAnotherHoldingKeepsItsOwnBoard() throws {
        var (e, a, b) = try twoCafes(seed: 62)
        makeBranch(&e, branch: b, of: a)
        e.update { s, _, _ in if let i = s.companyIndex(b) { s.companies[i].holdingID = 99 } }
        XCTAssertEqual(e.boardKey(companyID: b), "co:\(b)", "a different legal owner is a separate board")
        XCTAssertTrue(e.boardKeys.contains("co:\(b)"))
    }

    func testManagerIsNotADirector() throws {
        var (e, a, _) = try twoCafes(seed: 63)
        let cands = try XCTUnwrap(e.searchManagers(companyID: a))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: a, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        let key = try XCTUnwrap(e.boardKey(companyID: a))
        XCTAssertTrue(e.boardSeats(key: key).isEmpty, "nobody sits unless appointed")
        XCTAssertFalse(e.boardVoters(key: key).contains { $0.type == "ceo" && $0.votes }, "the manager attends but does not vote")
    }

    /// You hold 70% and an outside owner sits as director: you and that director are two votes, so you cannot dismiss the CEO alone.
    func testDirectorsDecideTheCEOWhenAnOutsideOwnerHasASeat() throws {
        var (e, a, _) = try twoCafes(seed: 64)
        let cands = try XCTUnwrap(e.searchManagers(companyID: a))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: a, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        let key = try XCTUnwrap(e.boardKey(companyID: a))
        let pick = try XCTUnwrap(e.searchForSeat(key: key, role: "director")?.first)
        e.update { s, _, _ in
            guard let i = s.companyIndex(a), var p = s.people[pick.id] else { return }
            p.employerID = -4; s.people[pick.id] = p
            s.companies[i].ownership = 70
            s.companies[i].set("holders", .array([.object(["name": .string(p.name), "pct": 30, "in": 0, "k27": "div", "sat": 60, "w0": 0, "npc": .number(Double(pick.id))])]))
            s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0, revenue: 50_000, profit: 9_000, cash: 10_000) }
            s.companies[i].set("brd", .object(["seats": .array([.object(["id": .number(Double(pick.id)), "kind": "adv", "r": "director", "t": "Director", "owner": true,
                                                                         "w0": 0, "fee": 0, "ok": 0, "no": 0, "mood": 60])]),
                                               "mode": "needed", "freq": 4, "last": -99, "mts": .array([]), "cands": .array([])]))
        }
        // the outside owner likes the profits and backs the CEO; a rare change of heart is hashed by name and week, so look for an ordinary week
        var v = e.ceoVote(companyID: a)
        for w in 20..<60 { e.update { s, _, _ in s.week = w }; v = e.ceoVote(companyID: a); if !v.passes { break } }
        XCTAssertTrue(v.directorsDecide)
        XCTAssertEqual(v.directorsTotal, 2)
        XCTAssertFalse(v.passes)
        guard case .voteFailed = e.proposeCEOChange(companyID: a) else { return XCTFail("the board should block it") }
        XCTAssertNotNil(e.state.company(a)?.managerID)
        // without the outside director the owner with 70% decides alone again
        e.update { s, _, _ in
            guard let i = s.companyIndex(a) else { return }
            s.companies[i].set("ceoBlk", .null)
            s.companies[i].set("brd", .null)
        }
        XCTAssertFalse(e.ceoVote(companyID: a).directorsDecide)
    }
}
