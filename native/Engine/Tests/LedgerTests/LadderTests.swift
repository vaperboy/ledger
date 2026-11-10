import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class LadderTests: XCTestCase {
    func testTenGoalsInOrderWithExactTitlesAndPastTense() throws {
        let e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 1)
        let g = try XCTUnwrap(PlayerGoals.ladder(e.state))
        XCTAssertEqual(g.map { $0.id }, (1...10).map { "M\($0)" })
        XCTAssertEqual(g.map { $0.title }, ["Get through your first week", "Set your prices", "Hire your first worker", "Answer a decision", "Word gets around",
                                            "Pay yourself", "Make a profit in a month", "Hire a manager", "Trade for a quarter", "Survive a bad week"])
        XCTAssertEqual(g.map { $0.pastTense }, ["You got through your first week.", "You set your prices.", "You hired your first worker.", "You answered your first decision.",
                                                "Your first campaign ran.", "You paid yourself.", "Your first profitable month.", "You hired a manager.",
                                                "You traded for a quarter.", "You survived a bad week."])
        XCTAssertEqual(PlayerGoals.currentLadderGoal(e.state)?.id, "M1")
        XCTAssertEqual(g.first { $0.id == "M2" }?.link, "sales")
    }

    func testOnlyTheOpenGoalCanFinishAndTheStoryNamesIt() throws {
        var e = try ChainsTests.engine(ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
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

    func playCafe(country: String, seed: Int = 7, price: Double = 0) throws -> (reachedM7Week: Int?, done: Int) {
        var e = try ChainsTests.engine(country, seed: seed, ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        let channels = ["google", "meta", "seo"].filter { e.marketing.channels[$0] != nil }
        _ = e.setPriceLevel(companyID: id, level: price)
        for k in channels { if let ch = e.marketing.channels[k], ch.budgetOptions.count > 1 { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[1]) } }
        e.payYourself(companyID: id, monthly: cur.scaledPrice(2000))
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

    func testRentWeighsOnTheStartingCityAboutTheSameEverywhere() throws {
        var heavy: [String] = []
        for c in try CountryBook.bundled().countries {
            guard let city = c.cities.first else { continue }
            let burden = city.rent / (city.demand * city.price)
            if burden > 1.7 { heavy.append("\(c.code) \(String(format: "%.2f", burden))") }
        }
        XCTAssertTrue(heavy.isEmpty, "rent against what a city's customers spend: " + heavy.joined(separator: ", "))
    }

    func testRewardsAreRealConsequencesNeverCash() throws {
        var e = try ChainsTests.engine(ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        for g in PlayerGoals.ladder(e.state) ?? [] { XCTAssertFalse(g.reward.lowercased().contains("grant") || g.reward.lowercased().contains("refund") || g.reward.lowercased().contains("free"), g.id) }
        let cash = e.state.cash
        let repBefore = e.state.company(id)?.reputation ?? 0
        let credit = e.state.credit
        e.update { s, _, _ in
            for k in ["M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9", "M10"] { _ = PlayerGoals.ladderReward(&s, k, cur) }
        }
        XCTAssertEqual(e.state.cash, cash, accuracy: 0.001, "no ladder reward pays money")
        XCTAssertGreaterThan(e.state.credit, credit)
        XCTAssertGreaterThanOrEqual(e.state.company(id)?.reputation ?? 0, repBefore)
        XCTAssertTrue(PlayerGoals.ladderFlag(e.state, "classic"))
        XCTAssertTrue(PlayerGoals.ladderFlag(e.state, "rank"))
        XCTAssertTrue(PlayerGoals.ladderFlag(e.state, "amb"))
        e.update { s, _, _ in
            XCTAssertEqual(PlayerGoals.ladderReward(&s, "M5", cur), "", "a campaign is its own reward")
            XCTAssertEqual(PlayerGoals.ladderReward(&s, "M6", cur), "")
        }
    }

    func testBadWeekGoalFinishesOnItsOwnAfterQuietWeeksAndNeverShowsACard() throws {
        var e = try ChainsTests.engine(ladder: true)
        _ = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        e.update { s, _, _ in
            s.rest["ldr"] = .object(["done": .object(Dictionary(uniqueKeysWithValues: (1...9).map { ("M\($0)", JSONValue.object(["w": .number(Double(s.week))])) }))])
        }
        XCTAssertNil(PlayerGoals.currentLadderGoal(e.state), "M10 asks nothing of the player")
        e.update { s, _, _ in XCTAssertEqual(PlayerGoals.ladderSweep(&s, currency: cur), []) }
        e.update { s, _, _ in s.week += PlayerGoals.quietWeeksForM10 }
        e.update { s, _, _ in XCTAssertEqual(PlayerGoals.ladderSweep(&s, currency: cur), ["M10"]) }
        XCTAssertTrue(Gates.goalDone(e.state, 10))
    }
}
