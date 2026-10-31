import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// Stage 6: board meetings have real agendas, close, record minutes and outcomes, and their decisions change the game.
final class BoardAgendaTests: XCTestCase {
    /// `count` limited cafes, each with a co-owner (so a board exists), the board set to meet regularly and a CFO at the table.
    private func makeBoards(seed: Int, count: Int) throws -> (engine: GameEngine, ids: [Int], keys: [String]) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        var ids: [Int] = [], keys: [String] = []
        for _ in 0..<count {
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 8_000_000) else { throw XCTSkip("could not start a company") }
            ids.append(id)
            e.update { s, _, _ in
                if let i = s.companyIndex(id) { s.companies[i].set("holders", .array([.object(["name": "Ann Partner", "pct": 15, "in": 0, "k27": "quiet", "sat": 60, "w0": 0])])) }
            }
            let key = try XCTUnwrap(e.boardKey(companyID: id))
            keys.append(key)
            e.setBoardMode(key: key, regular: true)
            let cands = try XCTUnwrap(e.searchForSeat(key: key, role: "cfo"))
            let c = try XCTUnwrap(cands.first)
            XCTAssertEqual(e.fillSeat(key: key, personID: c.id, monthlyFee: c.num("fee13") * 1.3), .ok)
        }
        return (e, ids, keys)
    }

    private func loseMoney(_ e: inout GameEngine, _ id: Int) {
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].monthlyHistory = (0..<3).map { MonthRecord(monthIndex: $0, revenue: 40_000, profit: -6_000, cash: 10_000) } }
        }
    }
    private func makeProfit(_ e: inout GameEngine, _ id: Int) {
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].monthlyHistory = (0..<3).map { MonthRecord(monthIndex: $0, revenue: 40_000, profit: 9_000, cash: 10_000) } }
        }
    }

    func testNoPointsMeansNoMeetingAndNoMessage() throws {
        var (e, _, keys) = try makeBoards(seed: 31, count: 1)
        let inbox0 = e.state.inbox.count
        XCTAssertTrue(e.boardAgendaPreview(key: keys[0]).isEmpty)
        XCTAssertNil(e.holdBoardMeeting(key: keys[0]))
        XCTAssertTrue(e.boardMeetings(key: keys[0]).isEmpty)
        XCTAssertEqual(e.state.inbox.count, inbox0)
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 0)
    }

    func testAgendaComesFromRealLossesAndApprovalPutsTheCompanyUpForSale() throws {
        var (e, ids, keys) = try makeBoards(seed: 32, count: 1)
        loseMoney(&e, ids[0])
        XCTAssertEqual(e.boardAgendaPreview(key: keys[0]).map { $0.action }, ["sale"])
        let mid = try XCTUnwrap(e.holdBoardMeeting(key: keys[0]))
        let m = try XCTUnwrap(e.boardMeetings(key: keys[0]).first)
        XCTAssertEqual(m.id, mid)
        XCTAssertEqual(m.title, "Meeting you called")
        XCTAssertTrue(m.isOpen)
        XCTAssertEqual(m.items.count, 1)
        XCTAssertFalse(m.items[0].effect.isEmpty)
        XCTAssertFalse(m.items[0].risk.isEmpty)
        XCTAssertFalse(m.attendees.isEmpty)
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 1)
        // The same point is not raised twice while it is open.
        XCTAssertNil(e.holdBoardMeeting(key: keys[0]))
        XCTAssertTrue(e.state.inbox.last?.body.contains("0 points") != true)

    }

    func testApprovedSaleClosesTheMeetingAndIsRemembered() throws {
        var (e, ids, keys) = try makeBoards(seed: 33, count: 1)
        loseMoney(&e, ids[0])
        let mid = try XCTUnwrap(e.holdBoardMeeting(key: keys[0]))
        let r = e.decideMeetingItem(key: keys[0], meetingID: mid, item: 0, approve: true)
        guard case .done(let out) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(out.contains("listed"))
        XCTAssertTrue((e.state.rest["sales"]?.array ?? []).contains { $0["co"].int == ids[0] }, "the company is really on the broker's list")
        let m = try XCTUnwrap(e.boardMeetings(key: keys[0]).first)
        XCTAssertEqual(m.status, "closed")
        XCTAssertEqual(m.items[0].status, "yes")
        XCTAssertEqual(m.items[0].outcome, out)
        XCTAssertTrue(m.minutes.contains { $0.hasPrefix("Approved:") })
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 0)
        // Answered points are not raised again at once, even when a meeting is called on purpose.
        var again: Int? = 0
        e.update { s, d, _ in again = ManagerModel.holdBoardMeeting(&s, key: keys[0], data: d, why: "Again") }
        XCTAssertNil(again)
        // A point already answered cannot be answered twice.
        XCTAssertEqual(e.decideMeetingItem(key: keys[0], meetingID: mid, item: 0, approve: true), .gone)
    }

    func testDeclinedPointIsKeptAsMinutesAndNotRaisedAgain() throws {
        var (e, ids, keys) = try makeBoards(seed: 34, count: 1)
        loseMoney(&e, ids[0])
        let mid = try XCTUnwrap(e.holdBoardMeeting(key: keys[0]))
        XCTAssertEqual(e.decideMeetingItem(key: keys[0], meetingID: mid, item: 0, approve: false), .declined)
        let m = try XCTUnwrap(e.boardMeetings(key: keys[0]).first)
        XCTAssertEqual(m.status, "closed")
        XCTAssertTrue(m.minutes.contains { $0.hasPrefix("Declined:") })
        XCTAssertFalse((e.state.rest["sales"]?.array ?? []).contains { $0["co"].int == ids[0] })
        XCTAssertTrue(e.boardAgendaPreview(key: keys[0]).isEmpty)
    }

    func testDividendDecisionChangesThePolicyAndARefusalKeepsThePointOpen() throws {
        var (e, ids, keys) = try makeBoards(seed: 35, count: 1)
        makeProfit(&e, ids[0])
        XCTAssertEqual(e.boardAgendaPreview(key: keys[0]).map { $0.action }, ["dividend"])
        let mid = try XCTUnwrap(e.holdBoardMeeting(key: keys[0]))
        // Something changed before the vote: the policy is set already, so the board cannot carry the point out.
        e.update { s, _, _ in if let i = s.companyIndex(ids[0]) { s.companies[i].set("dp27", "mid") } }
        let refused = e.decideMeetingItem(key: keys[0], meetingID: mid, item: 0, approve: true)
        guard case .refused(let why) = refused else { return XCTFail("\(refused)") }
        XCTAssertFalse(why.isEmpty)
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 1, "a refused point stays on the agenda")
        e.update { s, _, _ in if let i = s.companyIndex(ids[0]) { s.companies[i].set("dp27", "none") } }
        guard case .done = e.decideMeetingItem(key: keys[0], meetingID: mid, item: 0, approve: true) else { return XCTFail("approve") }
        XCTAssertEqual(e.dividendPolicy(companyID: ids[0]), "low")
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 0)
    }

    func testUndecidedMeetingLapsesAndStopsCounting() throws {
        var (e, ids, keys) = try makeBoards(seed: 36, count: 1)
        loseMoney(&e, ids[0])
        let mid = try XCTUnwrap(e.holdBoardMeeting(key: keys[0]))
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 1)
        for _ in 0..<(7 * (ManagerModel.lapseWeeks + 1)) { _ = e.nextDay() }
        let m = try XCTUnwrap(e.boardMeetings(key: keys[0]).first { $0.id == mid })
        XCTAssertEqual(m.status, "lapsed")
        XCTAssertEqual(m.items[0].status, "late")
        XCTAssertTrue(m.minutes.contains { $0.hasPrefix("No decision:") })
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 0)
        XCTAssertEqual(e.decideMeetingItem(key: keys[0], meetingID: mid, item: 0, approve: true), .gone)
    }

    func testMeetingsAndOutcomesSurviveASave() throws {
        var (e, ids, keys) = try makeBoards(seed: 37, count: 1)
        loseMoney(&e, ids[0])
        let mid = try XCTUnwrap(e.holdBoardMeeting(key: keys[0]))
        _ = e.decideMeetingItem(key: keys[0], meetingID: mid, item: 0, approve: false)
        let bytes = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: bytes)
        XCTAssertEqual(ManagerModel.meetings(back, key: keys[0]), e.boardMeetings(key: keys[0]))
        XCTAssertEqual(ManagerModel.board(back, key: keys[0]), ManagerModel.board(e.state, key: keys[0]))
    }

    func testOldMeetingsWithoutStatusDoNotCount() throws {
        var (e, ids, keys) = try makeBoards(seed: 38, count: 1)
        // A regular meeting as the old game saved it: no title, no status, no points.
        e.update { s, _, _ in
            guard let i = s.companyIndex(ids[0]) else { return }
            var b = s.companies[i].value("brd")
            b["mts"] = .array([.object(["id": 9001, "w": .number(Double(s.week)), "rows": .array([]), "items": .array([]), "ex": .array([]), "why": "Regular meeting"])])
            s.companies[i].set("brd", b)
        }
        let m = try XCTUnwrap(e.boardMeetings(key: keys[0]).first)
        XCTAssertEqual(m.status, "closed")
        XCTAssertEqual(m.title, "Regular board meeting")
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 0)
        XCTAssertEqual(e.boardDecisionsWaiting, 0)
    }

    /// Same seed, same boards.
    func testBoardsAreDeterministic() throws {
        func run() throws -> String {
            var (e, ids, keys) = try makeBoards(seed: 41, count: 2)
            for id in ids { loseMoney(&e, id) }
            for _ in 0..<(7 * 30) { _ = e.nextDay() }
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            return try keys.map { String(decoding: try enc.encode(ManagerModel.board(e.state, key: $0)), as: UTF8.self) }.joined(separator: "|")
        }
        XCTAssertEqual(try run(), try run())
    }

    /// Three boards over two years, several seeds: no empty meetings, no empty messages, the count of open points stays small and does not grow.
    func testTwoYearsOfThreeBoardsNeverGrowTheBadges() throws {
        for seed in [51, 52, 53] {
            var (e, ids, keys) = try makeBoards(seed: seed, count: 3)
            for id in ids { loseMoney(&e, id) }
            var peak = 0, peakYearOne = 0, peakYearTwo = 0
            var meetingsHeld = 0
            for week in 1...104 {
                for _ in 0..<7 { _ = e.nextDay() }
                let waiting = e.boardDecisionsWaiting
                peak = max(peak, waiting)
                if week > 52 { peakYearTwo = max(peakYearTwo, waiting) } else { peakYearOne = max(peakYearOne, waiting) }
                for k in keys {
                    XCTAssertLessThanOrEqual(e.boardOpenDecisions(key: k), 2 * 5 + 2, "seed \(seed) week \(week)")
                    XCTAssertLessThanOrEqual(ManagerModel.board(e.state, key: k)["mts"].array.count, 24)
                }
            }
            for k in keys {
                for m in e.boardMeetings(key: k) where !m.isEmergency {
                    meetingsHeld += 1
                    XCTAssertFalse(m.items.filter { !$0.action.isEmpty }.isEmpty, "seed \(seed): a regular meeting with nothing on the agenda")
                    XCTAssertFalse(m.title.isEmpty)
                }
            }
            XCTAssertFalse(e.state.inbox.contains { $0.body.contains(" 0 points") || $0.body.contains("0 points for you") }, "seed \(seed)")
            XCTAssertLessThanOrEqual(peakYearTwo, peakYearOne + 3, "seed \(seed): the count grew in the second year")
            XCTAssertLessThanOrEqual(e.boardDecisionsWaiting, 3 * 12, "seed \(seed)")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "seed \(seed): the books still balance")
            print("board probe seed \(seed): peak open \(peak), year two peak \(peakYearTwo), regular meetings kept \(meetingsHeld), waiting now \(e.boardDecisionsWaiting)")
        }
    }
}
