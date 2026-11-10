import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class BoardMeetingTests: XCTestCase {
    private typealias Who = ManagerModel.Attendee

    private func who(_ id: String, _ pct: Double, yes: Bool, present: Bool = true, activity: Double = 0.6) -> Who {
        Who(id: id, name: id, percent: pct, yes: yes, isYou: false, activity: activity, present: present)
    }

    private func you(_ pct: Double) -> Who { Who(id: "you", name: "You", percent: pct, yes: true, isYou: true) }

    func testJoinChanceRisesWithStakeAndActivity() {
        let small = ManagerModel.joinChance(percent: 3, activity: 0.5)
        let big = ManagerModel.joinChance(percent: 30, activity: 0.5)
        XCTAssertGreaterThan(big, small)
        XCTAssertGreaterThan(ManagerModel.joinChance(percent: 10, activity: 0.9), ManagerModel.joinChance(percent: 10, activity: 0.1))
        XCTAssertLessThanOrEqual(ManagerModel.joinChance(percent: 100, activity: 1), 0.97)
        XCTAssertGreaterThan(ManagerModel.joinChance(percent: 0, activity: 0), 0)
    }

    func testAttendanceIsSeededAndYouAlwaysSit() {
        let stakes = [you(30)] + (0..<12).map { who("h\($0)", 5, yes: true) }
        let a = ManagerModel.gather(stakes, seed: "alpha")
        XCTAssertEqual(a, ManagerModel.gather(stakes, seed: "alpha"))
        XCTAssertTrue(a[0].present)
        XCTAssertNotEqual(a.map { $0.present }, ManagerModel.gather(stakes, seed: "beta").map { $0.present })
        for x in a { XCTAssertGreaterThanOrEqual(x.arrives, 0); XCTAssertLessThanOrEqual(x.arrives, 1) }
    }

    func testBigHoldersTurnUpMoreOftenThanSmallOnes() {
        var big = 0, small = 0
        for n in 0..<400 {
            let a = ManagerModel.gather([who("b", 30, yes: true), who("s", 2, yes: true)], seed: "run\(n)")
            if a[0].present { big += 1 }
            if a[1].present { small += 1 }
        }
        XCTAssertGreaterThan(big, small)
    }

    func testAMajorityOfThePresentSharesCarries() {
        let v = ManagerModel.meetingVerdict([you(60), who("Ann", 40, yes: false)])
        XCTAssertTrue(v.passes)
        XCTAssertFalse(v.blockedByAbsent)
        XCTAssertEqual(v.yesPercent, 60)
    }

    func testAbsentHolderLargerThanTheMarginBlocks() {
        let v = ManagerModel.meetingVerdict([you(40), who("Bob", 35, yes: false), who("Ann", 25, yes: false, present: false)])
        XCTAssertFalse(v.passes)
        XCTAssertTrue(v.blockedByAbsent)
        XCTAssertEqual(v.blockers.map { $0.name }, ["Ann"])
    }

    func testAbsentHolderAtFivePercentDoesNotMatter() {
        let v = ManagerModel.meetingVerdict([you(48), who("Bob", 47, yes: false), who("Cy", 5, yes: false, present: false)])
        XCTAssertTrue(v.passes)
        XCTAssertTrue(v.blockers.isEmpty)
        XCTAssertEqual(v.absentPercent, 5)
    }

    func testAbsentHolderAboveFivePercentMattersWhenTheMarginIsThin() {
        let v = ManagerModel.meetingVerdict([you(48), who("Bob", 45, yes: false), who("Cy", 7, yes: false, present: false)])
        XCTAssertFalse(v.passes)
        XCTAssertEqual(v.blockers.map { $0.name }, ["Cy"])
    }

    func testALeadBiggerThanTheAbsentSharesStands() {
        let v = ManagerModel.meetingVerdict([you(60), who("Ann", 40, yes: false, present: false)])
        XCTAssertTrue(v.passes)
    }

    func testPresentSharesAgainstVoteItDownWithoutBlamingTheAbsent() {
        let v = ManagerModel.meetingVerdict([you(30), who("Ann", 70, yes: false)])
        XCTAssertFalse(v.passes)
        XCTAssertFalse(v.blockedByAbsent)
        XCTAssertEqual(v.noPercent, 70)
    }

    private func table(seed: Int, ownership: Double, holders: [JSONValue]) throws -> (engine: GameEngine, id: Int, key: String) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("could not start a company") }
        e.update { s, _, _ in
            if let i = s.companyIndex(id) {
                s.companies[i].status = .open
                s.companies[i].ownership = ownership
                s.companies[i].set("holders", .array(holders))
            }
        }
        return (e, id, try XCTUnwrap(e.boardKey(companyID: id)))
    }

    private func ann(_ pct: Double) -> JSONValue { .object(["name": "Ann Partner", "pct": .number(pct), "in": 0, "k27": "quiet", "sat": 60, "w0": 0]) }

    private func setMeetingCount(_ e: inout GameEngine, id: Int, key: String, _ n: Int) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var b = ManagerModel.board(s, key: key)
            b["mc"] = .number(Double(n))
            s.companies[i].set("brd", b)
        }
    }

    func testAlonePuttingAPointForwardDecidesAtOnce() throws {
        var (e, id, key) = try table(seed: 61, ownership: 100, holders: [])
        let point = "close:\(id)"
        XCTAssertTrue(e.boardPutForward(key: key).contains { $0.id == point })
        XCTAssertTrue(e.boardMeetingAttendees(key: key, id: point).isEmpty)
        let r = try XCTUnwrap(e.holdBoardMeeting(key: key, id: point))
        guard case .carriedOut(let said) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertTrue(said.contains("wound up"))
        XCTAssertFalse(try XCTUnwrap(e.state.company(id)).status.isLive)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSellingIsNotAMeetingPoint() throws {
        let (e, id, key) = try table(seed: 66, ownership: 100, holders: [])
        XCTAssertFalse(e.boardPutForward(key: key).contains { $0.id == "sell:\(id)" })
    }

    func testPreviewAndMeetingSeeTheSameAttendance() throws {
        var (e, id, key) = try table(seed: 62, ownership: 40, holders: [ann(60)])
        let point = "dividend:\(id)"
        let preview = e.boardMeetingAttendees(key: key, id: point)
        XCTAssertEqual(preview.count, 2)
        XCTAssertEqual(preview, e.boardMeetingAttendees(key: key, id: point))
        let r = try XCTUnwrap(e.holdBoardMeeting(key: key, id: point))
        XCTAssertEqual(r.attendees, preview)
    }

    func testAnAbsentMajorityHolderBlocksAndNothingIsSettled() throws {
        var (e, id, key) = try table(seed: 63, ownership: 40, holders: [ann(60)])
        let point = "dividend:\(id)"
        var found = false
        for n in 0..<400 {
            setMeetingCount(&e, id: id, key: key, n)
            if let a = e.boardMeetingAttendees(key: key, id: point).first(where: { $0.name == "Ann Partner" }), !a.present { found = true; break }
        }
        guard found else { throw XCTSkip("the co-owner always turns up in these meetings") }
        let r = try XCTUnwrap(e.holdBoardMeeting(key: key, id: point))
        XCTAssertEqual(r.outcome, .blocked(["Ann Partner"]))
        XCTAssertEqual(e.dividendPolicy(companyID: id), "none")
        XCTAssertTrue(e.boardPutForward(key: key).contains { $0.id == point }, "the point stays on the table")
    }

    func testWhenTheCoOwnerSitsTheMeetingIsNeverBlockedByThem() throws {
        var (e, id, key) = try table(seed: 64, ownership: 40, holders: [ann(60)])
        let point = "dividend:\(id)"
        var found = false
        for n in 0..<400 {
            setMeetingCount(&e, id: id, key: key, n)
            if let a = e.boardMeetingAttendees(key: key, id: point).first(where: { $0.name == "Ann Partner" }), a.present { found = true; break }
        }
        guard found else { throw XCTSkip("the co-owner never turns up") }
        let r = try XCTUnwrap(e.holdBoardMeeting(key: key, id: point))
        if case .blocked = r.outcome { XCTFail("a present holder cannot block") }
        XCTAssertFalse(r.verdict.blockedByAbsent)
    }

    func testEveryMeetingUsesANewRoll() throws {
        var (e, id, key) = try table(seed: 65, ownership: 40, holders: [ann(60)])
        let point = "dividend:\(id)"
        var seen = Set<Bool>()
        for n in 0..<60 {
            setMeetingCount(&e, id: id, key: key, n)
            if let a = e.boardMeetingAttendees(key: key, id: point).first(where: { $0.name == "Ann Partner" }) { seen.insert(a.present) }
        }
        XCTAssertEqual(seen, [true, false])
    }
}
