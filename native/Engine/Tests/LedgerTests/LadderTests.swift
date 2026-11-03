import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Brief Part 5: the ladder M1 to M10, its past-tense lines and rewards, and a scripted game that reaches M7 within 20 weeks on every country.
final class LadderTests: XCTestCase {
    func testTenGoalsInOrderWithExactTitlesAndPastTense() throws {
        let e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 1)
        let g = try XCTUnwrap(PlayerGoals.ladder(e.state))
        XCTAssertEqual(g.map { $0.id }, (1...10).map { "M\($0)" })
        XCTAssertEqual(g.map { $0.title }, ["Get through your first week", "Choose how you sell", "Hire your first worker", "Answer a decision", "Word gets around",
                                            "Pay yourself", "Make a profit in a month", "Hire a manager", "Open a second company", "Survive a bad week"])
        XCTAssertEqual(g.map { $0.pastTense }, ["You got through your first week.", "You chose how you sell.", "You hired your first worker.", "You answered your first decision.",
                                                "Your first campaign ran.", "You paid yourself.", "Your first profitable month.", "You hired a manager.",
                                                "You opened a second company.", "You survived a bad week."])
        XCTAssertEqual(PlayerGoals.currentLadderGoal(e.state)?.id, "M1")
        XCTAssertEqual(g.first { $0.id == "M2" }?.link, "sales")
    }

    func testOnlyTheOpenGoalCanFinishAndTheStoryNamesIt() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        // Work done out of order does not skip ahead: M3 (staff) and M5 are met, M1 is not.
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("mkt", .object(["x": .object(["b": .number(1)])]))
            XCTAssertEqual(PlayerGoals.ladderSweep(&s, currency: cur), [])
        }
        XCTAssertEqual(PlayerGoals.currentLadderGoal(e.state)?.id, "M1")
        ChainsTests.play(&e, days: 7)
        let done = Gates.goalsDone(e.state)
        XCTAssertGreaterThanOrEqual(done, 1)
        let report = try XCTUnwrap(e.latestReport(.week))
        let input = e.weekStoryInput(for: report)
        XCTAssertEqual(input.completedGoalPastTense, "You got through your first week.")
    }

    /// Plays a cafe from day one, doing what each goal asks as soon as it is open (the engine does not enforce gates, the app hides them).
    /// Once a goal is met its cost goes again: campaigns stop, the owner stops taking pay, and the owner works the counter alone.
    func playCafe(country: String, seed: Int = 7, price: Double = 0) throws -> (reachedM7Week: Int?, done: Int) {
        var e = try ChainsTests.engine(country, seed: seed)
        let id = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        let channels = ["google", "meta", "seo"].filter { e.marketing.channels[$0] != nil }
        _ = e.setPriceLevel(companyID: id, level: price)                                       // M2: a price set
        for k in channels { if let ch = e.marketing.channels[k], ch.budgetOptions.count > 1 { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[1]) } }   // M5
        _ = e.setOwnerSalary(companyID: id, monthly: cur.scaledPrice(2000))                // M6
        var answered = false
        var stoppedAds = false, stoppedPay = false, alone = false
        for day in 0..<(20 * 7) {
            if !answered && day == 8 {
                e.update { s, _, _ in
                    s.addMessage(kind: "ask", from: "Test", title: "A decision", body: "Pick one.", companyID: id, status: "open",
                                 options: [.option("Fine", "")], action: FirstYear.frozenAction)
                }
                if let m = e.openDecisions.first(where: { $0.actionID == FirstYear.frozenAction }) { answered = e.answer(messageID: m.id, option: 0) }
            }
            ChainsTests.play(&e, days: 1)
            if !stoppedAds, Gates.goalDone(e.state, 5) { stoppedAds = true; for k in channels { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: 0) } }
            if !stoppedPay, Gates.goalDone(e.state, 6) { stoppedPay = true; _ = e.setOwnerSalary(companyID: id, monthly: 0) }
            if !alone, Gates.goalDone(e.state, 3), let st = e.state.company(id)?.staff.first { alone = true; e.dismissStaff(companyID: id, staffID: st.id) }
            if Gates.goalDone(e.state, 7) { return (e.state.week, Gates.goalsDone(e.state)) }
        }
        return (nil, Gates.goalsDone(e.state))
    }

    func testScriptedGameReachesM7WithinTwentyWeeksOnEveryCountry() throws {
        let codes = try CountryBook.bundled().countries.map { $0.code }
        XCTAssertGreaterThan(codes.count, 10)
        var failures: [String] = []
        for code in codes {
            // A player who sees no profit tries another price: the going price first, then cheaper, then dearer.
            var best: (reachedM7Week: Int?, done: Int) = (nil, 0)
            for price in [0.0, -1.0, 1.0] {
                best = try playCafe(country: code, price: price)
                if let w = best.reachedM7Week, w <= 20 { break }
            }
            if let w = best.reachedM7Week { if w > 20 { failures.append("\(code): M7 in week \(w)") } }
            else { failures.append("\(code): stopped at \(best.done) goals") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
    }

    func testRewardsAreOneOffAndMatchTheOldChecklistValues() throws {
        var e = try ChainsTests.engine()
        _ = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        let before = e.state.cash
        e.update { s, _, _ in
            let line = PlayerGoals.ladderReward(&s, "M3", cur)
            XCTAssertTrue(line.hasPrefix("The job centre pays a month of payroll tax"))
        }
        XCTAssertEqual(e.state.cash - before, cur.scaledPrice(6000), accuracy: 1)
        e.update { s, _, _ in _ = PlayerGoals.ladderReward(&s, "M8", cur); _ = PlayerGoals.ladderReward(&s, "M9", cur) }
        XCTAssertTrue(PlayerGoals.ladderFlag(e.state, "classic"))
        XCTAssertTrue(PlayerGoals.ladderFlag(e.state, "rank"))
    }
}
