import XCTest
import GameCore
import Finance
import Businesses
import Employees
@testable import SaveSystem
@testable import Simulation

final class BoardRemovalTests: XCTestCase {
    private func setup(seed: Int) throws -> (GameEngine, Int, String, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 6_000_000) else { XCTFail("start"); return (e, 0, "", 0) }
        e.update { s, d, _ in _ = CompanySetup.quickSetup(&s, companyID: id, data: d) }
        var who = 0
        e.update { s, _, _ in
            if let m = s.company(id)?.staff.first { who = m.id; var p = s.people[m.id]!; p.skill = 80; s.people[m.id] = p }
        }
        let key = try XCTUnwrap(e.boardKey(companyID: id))
        return (e, id, key, who)
    }

    func testOwnStaffRemovedKeepsJobAndNoPay() throws {
        var (e, a, key, who) = try setup(seed: 31)
        XCTAssertEqual(e.appointOwnToBoard(companyID: a, seat: "director", personID: who), .applied)
        let terms = e.seatRemovalTerms(key: key, personID: who)
        XCTAssertTrue(terms.allowed)
        XCTAssertTrue(terms.keepsJob)
        XCTAssertEqual(terms.cost, 0)
        let cash = e.state.company(a)!.cash
        XCTAssertEqual(e.removeSeatHolder(key: key, personID: who), .applied)
        XCTAssertNil(e.boardSeats(key: key).first { $0.id == who })
        XCTAssertEqual(e.state.people[who]?.employerID, a)
        XCTAssertEqual(e.state.company(a)!.cash, cash)
        XCTAssertTrue(e.removeSeatHolder(key: key, personID: who).isRefused, "no longer seated")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testOutsideDirectorPaidNoticeWhenOwnerControls() throws {
        var (e, a, key, _) = try setup(seed: 32)
        let found = try XCTUnwrap(e.searchForSeat(key: key, role: "director"))
        let pick = found[0]
        XCTAssertEqual(e.fillSeat(key: key, personID: pick.id, monthlyFee: pick.num("fee13") * 1.1), .ok)
        let seat = try XCTUnwrap(e.boardSeats(key: key).first { $0.id == pick.id })
        XCTAssertEqual(seat.kind, "adv")
        let terms = e.seatRemovalTerms(key: key, personID: pick.id)
        XCTAssertTrue(terms.allowed)
        XCTAssertFalse(terms.keepsJob)
        XCTAssertEqual(terms.noticeMonths, 3)
        XCTAssertEqual(terms.cost, seat.monthlyFee * 3, accuracy: 0.01)
        let cash = e.state.company(a)!.cash
        XCTAssertEqual(e.removeSeatHolder(key: key, personID: pick.id), .applied)
        XCTAssertNil(e.boardSeats(key: key).first { $0.id == pick.id })
        XCTAssertEqual(e.state.people[pick.id]?.employerID, 0)
        XCTAssertLessThan(e.state.company(a)!.cash, cash)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testMinorityOwnerVoteFailsWithoutOtherShareholders() throws {
        var (e, a, key, _) = try setup(seed: 33)
        let found = try XCTUnwrap(e.searchForSeat(key: key, role: "cfo"))
        XCTAssertEqual(e.fillSeat(key: key, personID: found[0].id, monthlyFee: found[0].num("fee13") * 1.1), .ok)
        e.update { s, _, _ in if let i = s.companyIndex(a) { s.companies[i].ownership = 40; s.companies[i].set("holders", .array([])) } }
        let terms = e.seatRemovalTerms(key: key, personID: found[0].id)
        XCTAssertTrue(terms.allowed)
        XCTAssertTrue(terms.needsVote)
        let cash = e.state.company(a)!.cash
        XCTAssertTrue(e.removeSeatHolder(key: key, personID: found[0].id).isRefused)
        XCTAssertNotNil(e.boardSeats(key: key).first { $0.id == found[0].id })
        XCTAssertEqual(e.state.company(a)!.cash, cash, "no notice when the vote fails")
    }

    func testMinorityOwnerVotePassesWithSupportAndPaysNotice() throws {
        var passed = false
        for n in 0..<20 where !passed {
            var (e, a, key, _) = try setup(seed: 34)
            let found = try XCTUnwrap(e.searchForSeat(key: key, role: "cfo"))
            XCTAssertEqual(e.fillSeat(key: key, personID: found[0].id, monthlyFee: found[0].num("fee13") * 1.1), .ok)
            e.update { s, _, _ in
                if let i = s.companyIndex(a) { s.companies[i].ownership = 40; s.companies[i].set("holders", .array([.object(["name": .string("Investor \(n)"), "pct": 60])])) }
            }
            let cash = e.state.company(a)!.cash
            if e.removeSeatHolder(key: key, personID: found[0].id) == .applied {
                passed = true
                XCTAssertNil(e.boardSeats(key: key).first { $0.id == found[0].id })
                XCTAssertLessThan(e.state.company(a)!.cash, cash)
            } else {
                XCTAssertNotNil(e.boardSeats(key: key).first { $0.id == found[0].id })
                XCTAssertEqual(e.state.company(a)!.cash, cash)
            }
        }
        XCTAssertTrue(passed, "a supporting co-owner can carry the vote")
    }

    /// Managers, executives and board advisers who have no portrait (an old save) get one from the sweep, the same one every time.
    func testPeopleWithoutAFaceGetOneDeterministically() throws {
        func run() throws -> [String?] {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 41)
            e.update { s, d, _ in
                for (i, employer) in [-1, -2, -3, -4].enumerated() {
                    var p = Person(raw: ["id": .number(Double(9000 + i)), "name": .string("Test Person \(i)"), "age": .number(40), "role": .string("manager")])
                    p.employerID = employer
                    s.people[p.id] = p
                }
                FaceBook.sweep(&s, data: d)
            }
            return (0..<4).map { e.state.people[9000 + $0]?.faceKey }
        }
        let a = try run()
        XCTAssertFalse(a.contains { $0 == nil }, "everyone employed has a portrait")
        XCTAssertEqual(Set(a.compactMap { $0 }).count, 4, "all different")
        XCTAssertEqual(a, try run(), "deterministic")
    }
}
