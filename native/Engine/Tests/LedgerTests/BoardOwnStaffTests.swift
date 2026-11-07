import XCTest
import GameCore
import Finance
import Businesses
@testable import SaveSystem
@testable import Simulation

final class BoardOwnStaffTests: XCTestCase {
    /// A game with two cafes, both staffed; returns the engine, the first company and one of its employees (made skilled).
    private func setup(seed: Int = 21) throws -> (GameEngine, Int, Int, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        var ids: [Int] = []
        for _ in 0..<2 {
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 6_000_000) else { XCTFail("start"); return (e, 0, 0, 0) }
            e.update { s, d, _ in _ = CompanySetup.quickSetup(&s, companyID: id, data: d) }
            ids.append(id)
        }
        var who = 0
        e.update { s, _, _ in
            if let m = s.company(ids[0])?.staff.first { who = m.id; var p = s.people[m.id]!; p.skill = 80; s.people[m.id] = p }
        }
        XCTAssertNotEqual(who, 0, "staff exists")
        return (e, ids[0], ids[1], who)
    }

    func testOwnStaffListedAppointedWithHalfFee() throws {
        var (e, a, b, who) = try setup()
        let list = e.boardCandidates(companyID: a, seat: "director")
        let own = try XCTUnwrap(list.first { $0.personID == who })
        XCTAssertTrue(own.isOwnStaff)
        XCTAssertFalse(own.qualification.isEmpty)
        XCTAssertEqual(e.appointOwnToBoard(companyID: a, seat: "director", personID: who), .applied)
        let key = try XCTUnwrap(e.boardKey(companyID: a))
        let seat = try XCTUnwrap(e.boardSeats(key: key).first { $0.id == who })
        XCTAssertEqual(seat.role, "director")
        // half fee on the own company's board; full fee on a sister company's board
        XCTAssertEqual(seat.monthlyFee * 12, own.feePerYear, accuracy: 0.01)
        let other = try XCTUnwrap(e.boardCandidates(companyID: b, seat: "director").first { $0.personID == who })
        XCTAssertGreaterThan(other.feePerYear, own.feePerYear * 1.5)
        // keeps the job
        XCTAssertEqual(e.state.people[who]?.employerID, a)
        XCTAssertTrue(e.state.company(a)!.staff.contains { $0.id == who })
        // no longer listed, cannot be seated twice
        XCTAssertFalse(e.boardCandidates(companyID: a, seat: "director").contains { $0.personID == who })
        XCTAssertTrue(e.appointOwnToBoard(companyID: a, seat: "director", personID: who).isRefused)
        XCTAssertTrue(e.appointOwnToBoard(companyID: a, seat: "sec", personID: who).isRefused)
        XCTAssertEqual(e.boardSeats(key: key).filter { $0.id == who }.count, 1)
        // removal through the existing call keeps the job
        e.removeFromBoard(key: key, personID: who)
        XCTAssertNil(e.boardSeats(key: key).first { $0.id == who })
        XCTAssertEqual(e.state.people[who]?.employerID, a)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSearchedCandidatesListedAndOutsidersRefused() throws {
        var (e, a, _, who) = try setup(seed: 22)
        let key = try XCTUnwrap(e.boardKey(companyID: a))
        let found = try XCTUnwrap(e.searchForSeat(key: key, role: "director"))
        let list = e.boardCandidates(companyID: a, seat: "director")
        XCTAssertEqual(list.filter { !$0.isOwnStaff }.map { $0.personID }, found.map { $0.id })
        XCTAssertTrue(list.contains { $0.isOwnStaff && $0.personID == who })
        // a searched stranger is not "own staff"
        XCTAssertTrue(e.appointOwnToBoard(companyID: a, seat: "director", personID: found[0].id).isRefused)
        // an unskilled employee does not qualify
        e.update { s, _, _ in var p = s.people[who]!; p.skill = 20; s.people[who] = p }
        XCTAssertFalse(e.boardCandidates(companyID: a, seat: "director").contains { $0.personID == who })
        XCTAssertTrue(e.appointOwnToBoard(companyID: a, seat: "director", personID: who).isRefused)
    }

    func testSingleSeatFullAndMonthlyFeeBooksBalance() throws {
        var (e, a, _, who) = try setup(seed: 23)
        XCTAssertEqual(e.appointOwnToBoard(companyID: a, seat: "chair", personID: who), .applied)
        e.update { s, _, _ in
            if let m = s.company(a)?.staff.dropFirst().first { var p = s.people[m.id]!; p.skill = 85; s.people[m.id] = p }
        }
        if let second = e.state.company(a)?.staff.dropFirst().first {
            XCTAssertTrue(e.appointOwnToBoard(companyID: a, seat: "chair", personID: second.id).isRefused, "one chair only")
        }
        for _ in 0..<70 { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSaveReloadAndDeterminism() throws {
        func run() throws -> (GameEngine, Int) {
            var (e, a, _, who) = try setup(seed: 24)
            XCTAssertEqual(e.appointOwnToBoard(companyID: a, seat: "director", personID: who), .applied)
            for _ in 0..<40 { e.nextDay() }
            return (e, a)
        }
        let (e1, a) = try run()
        let (e2, _) = try run()
        let k = try XCTUnwrap(e1.boardKey(companyID: a))
        XCTAssertEqual(e1.boardSeats(key: k), e2.boardSeats(key: k))
        XCTAssertEqual(e1.boardCandidates(companyID: a, seat: "director"), e2.boardCandidates(companyID: a, seat: "director"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-board-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(e1.state, summary: store.summary(of: e1.state, trades: e1.data.catalog))
        let (data, events, marketing) = try GameEngine.loadResources()
        let e3 = GameEngine(state: try store.load(), data: data, events: events, marketing: marketing)
        XCTAssertEqual(e3.boardSeats(key: k), e1.boardSeats(key: k))
        XCTAssertEqual(e3.boardCandidates(companyID: a, seat: "director"), e1.boardCandidates(companyID: a, seat: "director"))
    }
}
