import XCTest
import GameCore
import Simulation

/// The play streak and the three reminders.
final class PlayStreakTests: XCTestCase {
    private func fresh() throws -> GameEngine { try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 1) }

    func testStreakCountsConsecutiveCalendarDaysAndIgnoresSecondPlayOnTheSameDay() throws {
        var s = try fresh().state
        XCTAssertEqual(PlayStreak.current(s, today: 100), 0)
        PlayStreak.record(&s, today: 100)
        PlayStreak.record(&s, today: 100)
        XCTAssertEqual(PlayStreak.current(s, today: 100), 1)
        PlayStreak.record(&s, today: 101)
        PlayStreak.record(&s, today: 102)
        XCTAssertEqual(PlayStreak.current(s, today: 102), 3)
        XCTAssertEqual(PlayStreak.current(s, today: 103), 3, "yesterday still counts until today is played")
    }

    func testAMissedDayEndsTheRunAndTheNextPlayStartsAtOne() throws {
        var s = try fresh().state
        for d in 10...13 { PlayStreak.record(&s, today: d) }
        XCTAssertEqual(PlayStreak.current(s, today: 13), 4)
        XCTAssertEqual(PlayStreak.current(s, today: 15), 0)
        PlayStreak.record(&s, today: 15)
        XCTAssertEqual(PlayStreak.current(s, today: 15), 1)
    }

    func testAnEmptyStreakIsStillStartedByDayZero() throws {
        var s = try fresh().state
        PlayStreak.record(&s, today: 0)
        PlayStreak.record(&s, today: 1)
        XCTAssertEqual(PlayStreak.current(s, today: 1), 2)
    }

    func testStreakSurvivesTheSaveFormat() throws {
        var e = try fresh()
        e.update { s, _, _ in PlayStreak.record(&s, today: 7); PlayStreak.record(&s, today: 8) }
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(PlayStreak.current(back, today: 8), 2)
    }

    func testNewGameHasTheLadderGoalReminderAtFortyEightHoursOnly() throws {
        let e = try fresh()
        let r = SessionHooks.reminders(e.state)
        XCTAssertEqual(r.map { $0.id }, ["ledger.goal"])
        XCTAssertEqual(r.first?.after, 48 * 3600)
        XCTAssertEqual(r.first?.title, "Get through your first week")
    }

    func testAnOpenDecisionWithAnExpiryGetsTheTwentyHourReminder() throws {
        var e = try fresh()
        e.update { s, _, _ in
            s.addMessage(kind: "ask", from: "Staff", title: "Pay rise request", body: "b", companyID: s.companies.first?.id ?? 0, status: "open", expiresWeek: s.week + 3)
        }
        let r = SessionHooks.reminders(e.state)
        XCTAssertEqual(r.map { $0.id }, ["ledger.expiry", "ledger.goal"])
        XCTAssertEqual(r.first?.after, 20 * 3600)
        XCTAssertTrue(r.first?.body.hasSuffix(": Pay rise request. 3 weeks left.") ?? false)
        XCTAssertFalse(SessionHooks.cliffhanger(e.state), "three weeks out is not a cliffhanger")
        e.update { s, _, _ in s.week += 1 }
        XCTAssertTrue(SessionHooks.cliffhanger(e.state))
    }

    func testOffersToBuyAreNeverRemindedAndIdleGameGetsTheSevenDayNote() throws {
        var e = try ChainsTests.engine()
        _ = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            s.rest["ldr"] = nil
            s.addMessage(kind: "ask", from: "Buyer", title: "An offer to buy your company", body: "b", status: "open", expiresWeek: s.week + 2)
        }
        let r = SessionHooks.reminders(e.state)
        XCTAssertEqual(r.map { $0.id }, ["ledger.idle"])
        XCTAssertEqual(r.first?.after, 7 * 86400)
        XCTAssertTrue(r.first?.body.hasSuffix(" is waiting for its next day.") ?? false)
    }
}
