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

    func testVoteChanceFollowsOpinionStakeAndSatisfaction() {
        XCTAssertGreaterThan(ManagerModel.voteChance(opinion: true, percent: 10, satisfaction: 0.5), ManagerModel.voteChance(opinion: false, percent: 10, satisfaction: 0.5))
        XCTAssertGreaterThan(ManagerModel.voteChance(opinion: false, percent: 10, satisfaction: 0.9), ManagerModel.voteChance(opinion: false, percent: 10, satisfaction: 0.1))
        XCTAssertGreaterThan(ManagerModel.voteChance(opinion: true, percent: 30, satisfaction: 0.5), ManagerModel.voteChance(opinion: true, percent: 2, satisfaction: 0.5))
        for sat in [0.0, 0.5, 1.0] { for op in [true, false] {
            let p = ManagerModel.voteChance(opinion: op, percent: 100, satisfaction: sat)
            XCTAssertGreaterThanOrEqual(p, 0.03); XCTAssertLessThanOrEqual(p, 0.97)
        } }
    }

    func testCastVotesAreSeededAndYourVoteIsYourOwn() {
        let people = [you(30)] + (0..<10).map { who("h\($0)", 7, yes: $0 % 2 == 0, activity: 0.5) }
        let a = ManagerModel.castVotes(people, seed: "s1", youYes: false)
        XCTAssertEqual(a, ManagerModel.castVotes(people, seed: "s1", youYes: false))
        XCTAssertFalse(a[0].yes)
        XCTAssertTrue(ManagerModel.castVotes(people, seed: "s1", youYes: true)[0].yes)
        XCTAssertNotEqual(a.map { $0.yes }, ManagerModel.castVotes(people, seed: "s2", youYes: false).map { $0.yes })
    }

    func testHappyHoldersBackYouMoreOftenThanUnhappyOnes() {
        var happy = 0, unhappy = 0
        for n in 0..<400 {
            let a = ManagerModel.castVotes([who("a", 10, yes: false, activity: 1), who("b", 10, yes: false, activity: 0)], seed: "r\(n)", youYes: true)
            if a[0].yes { happy += 1 }
            if a[1].yes { unhappy += 1 }
        }
        XCTAssertGreaterThan(happy, unhappy)
    }

    func testAloneTheAgendaIsDecidedByYourVoteAndExecutesAtOnce() throws {
        var (e, id, key) = try table(seed: 61, ownership: 100, holders: [])
        let point = "close:\(id)"
        XCTAssertTrue(e.boardMeetingAgenda(keys: [key]).contains { $0.id == point })
        XCTAssertTrue(e.boardMeetingGuests(e.boardMeetingAgenda(keys: [key])).isEmpty)
        let r = try XCTUnwrap(e.voteOnBoardPoint(key: key, id: point, yes: true))
        XCTAssertEqual(r.kind, .carried)
        XCTAssertTrue(r.line.contains("approved by you"), r.line)
        XCTAssertFalse(try XCTUnwrap(e.state.company(id)).status.isLive)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertNil(e.voteOnBoardPoint(key: key, id: point, yes: true), "an executed point is gone")
    }

    func testAloneVotingNoLeavesTheCompanyAndTakesThePointOffTheTable() throws {
        var (e, id, key) = try table(seed: 67, ownership: 100, holders: [])
        let point = "close:\(id)"
        let r = try XCTUnwrap(e.voteOnBoardPoint(key: key, id: point, yes: false))
        XCTAssertEqual(r.kind, .votedDown)
        XCTAssertTrue(r.line.contains("you voted no"), r.line)
        XCTAssertTrue(try XCTUnwrap(e.state.company(id)).status.isLive)
        XCTAssertFalse(e.boardMeetingAgenda(keys: [key]).contains { $0.id == point })
    }

    func testNothingToSellMeansNoSaleOnTheAgenda() throws {
        let (e, id, key) = try table(seed: 66, ownership: 100, holders: [])
        XCTAssertFalse(e.boardMeetingAgenda(keys: [key]).contains { $0.id == "sell:\(id)" })
    }

    func testAgendaIsCappedAtFourPoints() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 68)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        var keys: [String] = []
        for _ in 0..<3 {
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("could not start a company") }
            e.update { s, _, _ in
                if let i = s.companyIndex(id) {
                    s.companies[i].status = .open
                    s.companies[i].ownership = 40
                    s.companies[i].set("holders", .array([ann(60)]))
                    s.companies[i].monthlyHistory = (0..<3).map { MonthRecord(monthIndex: $0, revenue: 40_000, profit: 9_000, cash: 10_000) }
                }
            }
            keys.append(try XCTUnwrap(e.boardKey(companyID: id)))
        }
        XCTAssertEqual(e.boardMeetingAgenda(keys: keys).count, ManagerModel.agendaLimit)
        XCTAssertEqual(Set(e.boardMeetingAgenda(keys: keys).map { $0.id }).count, ManagerModel.agendaLimit)
    }

    func testTheSameMeetingGivesTheSameRuling() throws {
        let run = { () throws -> ManagerModel.MeetingRuling in
            var (e, id, key) = try self.table(seed: 62, ownership: 40, holders: [self.ann(60)])
            e.beginBoardMeeting(keys: [key])
            return try XCTUnwrap(e.voteOnBoardPoint(key: key, id: "dividend:\(id)", yes: true))
        }
        XCTAssertEqual(try run(), try run())
    }

    func testEveryRulingExecutesOrLeavesThingsAsItsLineSays() throws {
        var (base, id, key) = try table(seed: 63, ownership: 40, holders: [ann(60)])
        let point = "dividend:\(id)"
        var seen = Set<String>()
        for n in 0..<200 {
            setMeetingCount(&base, id: id, key: key, n)
            var e = base
            let guests = e.boardMeetingGuests(e.boardMeetingAgenda(keys: [key]))
            let r = try XCTUnwrap(e.voteOnBoardPoint(key: key, id: point, yes: true))
            XCTAssertEqual(r.attendees.map { $0.present }, ManagerModel.meetingAttendees(base.state, key: key, try XCTUnwrap(ManagerModel.meetingDecisions(base.state, key: key, data: base.data).first { $0.id == point })).map { $0.present })
            XCTAssertEqual(guests.map { $0.present }, r.attendees.filter { !$0.isYou }.map { $0.present })
            switch r.kind {
            case .carried:
                XCTAssertEqual(e.dividendPolicy(companyID: id), "low")
                XCTAssertTrue(r.line.contains("approved"), r.line)
                XCTAssertTrue(r.line.contains("%"), r.line)
            case .votedDown:
                XCTAssertEqual(e.dividendPolicy(companyID: id), "none")
                XCTAssertFalse(e.boardMeetingAgenda(keys: [key]).contains { $0.id == point })
                XCTAssertTrue(r.line.contains("rejected"), r.line)
            case .blocked:
                XCTAssertEqual(e.dividendPolicy(companyID: id), "none")
                XCTAssertTrue(e.boardMeetingAgenda(keys: [key]).contains { $0.id == point }, "a held-up point stays on the table")
                XCTAssertTrue(r.line.contains("Ann Partner"), r.line)
            case .refused:
                XCTFail(r.line)
            }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
            seen.insert("\(r.kind)")
        }
        XCTAssertTrue(seen.contains("carried") || seen.contains("votedDown") || seen.contains("blocked"))
        XCTAssertGreaterThanOrEqual(seen.count, 2, "different meetings give different results: \(seen)")
    }

    func testBeginningAMeetingMovesTheRollOnlyOnce() throws {
        var (e, _, key) = try table(seed: 65, ownership: 40, holders: [ann(60)])
        let n0 = ManagerModel.board(e.state, key: key)["mc"].int
        e.beginBoardMeeting(keys: [key])
        XCTAssertEqual(ManagerModel.board(e.state, key: key)["mc"].int, n0 + 1)
    }

    func testEveryMeetingUsesANewRoll() throws {
        var (e, id, key) = try table(seed: 69, ownership: 40, holders: [ann(60)])
        var seen = Set<Bool>()
        for n in 0..<60 {
            setMeetingCount(&e, id: id, key: key, n)
            if let a = e.boardMeetingGuests(e.boardMeetingAgenda(keys: [key])).first(where: { $0.name == "Ann Partner" }) { seen.insert(a.present) }
        }
        XCTAssertEqual(seen, [true, false])
    }
}
