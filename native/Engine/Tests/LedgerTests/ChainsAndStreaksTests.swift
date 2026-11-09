import XCTest
@testable import Events
@testable import Businesses
@testable import Simulation
import GameCore
import Countries
import Finance

/// Longer event chains, the late-game fourth answer, the trade packs, streak perks and protection, the return recap and the mastery reads.
final class ChainsAndStreaksTests: XCTestCase {
    static let chainKinds = ["breachclaim", "breachpress", "suppnotice", "suppcash", "suppstop", "licwarn", "licreview", "pwreply", "pwlong", "pwtruce"]
    static let packTrades = ["cons", "tutor", "carclean", "photo", "handy", "cleaning", "webdev", "mktg", "law", "acctfirm", "staffing", "barber"]

    func engineWithCompany(trades: [String] = ["cafe"], weeks: Int = 3) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var first = 0
        var ids: [Int] = []
        for (n, trade) in trades.enumerated() {
            e.update { s, data, ctx in
                Ledger.move(&s, .me, 50_000_000, why: "Test funds")
                var id = 0
                if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) { id = i }
                let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, size: 1, state: s, data: data)
                Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
                _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
                if n == 0 { first = id }
                ids.append(id)
            }
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        // Each company's own weekday decides when its paperwork clears and it opens: play on until all have.
        var extra = 0
        while ids.contains(where: { e.state.company($0)?.status != .open }) && extra < 28 { e.nextDay(); extra += 1 }
        return (e, first)
    }

    func kinds(_ s: GameState, _ id: Int) -> Set<String> { Set(AftermathQueue.pending(s, companyID: id).map { $0.kind }) }

    func fire(_ e: GameEvent, _ s: inout GameState, _ id: Int, data: GameData, ctx: FinanceContext) {
        let i = s.companyIndex(id)!
        let c = EventEngine.context(for: s.companies[i], data: data, country: World(state: s, data: data).country(s.companies[i]))
        EventEngine.fire(&s, companyIndex: i, e, ctx: c, data: data, context: ctx)
    }

    // MARK: Chains

    func testEveryChainStepHasThreeCostedOptionsAndKeepsTheBooksBalanced() throws {
        let (base, id) = try engineWithCompany()
        for kind in Self.chainKinds {
            let step = try XCTUnwrap(Aftermath.event(kind), kind)
            XCTAssertEqual(step.id, "aft_" + kind)
            XCTAssertEqual(step.options.count, 3, kind)
            XCTAssertTrue(step.options.allSatisfy { !$0.detail.isEmpty }, kind)
            XCTAssertGreaterThanOrEqual(step.expiresAfterWeeks, 2, "\(kind): never a blocking decision")
            for n in 0..<step.options.count {
                var e = base
                var asked: Message? = nil
                e.update { s, data, ctx in
                    fire(step, &s, id, data: data, ctx: ctx)
                    asked = s.inbox.first { $0.status == "open" && $0.str("ev") == "aft_" + kind }
                }
                let m = try XCTUnwrap(asked, kind)
                XCTAssertTrue(e.answer(messageID: m.id, option: n), "\(kind) option \(n)")
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(kind) option \(n): \(Ledger.gaps(e.state))")
            }
        }
    }

    func testEveryNextStepNamedByAnAnswerExists() throws {
        func nexts(_ fx: JSONValue) -> [String] {
            var out: [String] = fx["next"].isNull ? [] : [fx["next"]["k"].string]
            if !fx["gamble"].isNull { out += nexts(fx["gamble"]["ok"]) + nexts(fx["gamble"]["bad"]) }
            return out
        }
        let lib = try EventLibrary.bundled()
        for kind in Self.chainKinds + Array(Aftermath.templates.keys) {
            let step = try XCTUnwrap(Aftermath.event(kind), kind)
            for o in step.options { for k in nexts(o.effects) { XCTAssertNotNil(Aftermath.event(k), "\(kind) -> \(k)") } }
        }
        for e in lib.events.values { for o in e.options { for k in nexts(o.effects) { XCTAssertNotNil(Aftermath.event(k), "\(e.id) -> \(k)") } } }
    }

    func testAnUnresolvedBreachEscalatesToAClaimThenAPressStory() throws {
        var (e, id) = try engineWithCompany()
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            let c = EventEngine.context(for: s.companies[i], data: data, country: World(state: s, data: data).country(s.companies[i]))
            // The answer "Leave it" of the security review.
            EventEngine.apply(&s, companyIndex: i, .object(["cyberTarget": 1]), ctx: c, event: GameEvent(id: "aft_secreview", json: .object([:])), data: data, context: ctx)
            XCTAssertTrue(kinds(s, id).contains("breachclaim"))
            s.week += 20
            Aftermath.weekly(&s, data: data, context: ctx)
            XCTAssertNotNil(s.inbox.first { $0.status == "open" && $0.str("ev") == "aft_breachclaim" })
        }
        let m = try XCTUnwrap(e.state.inbox.first { $0.str("ev") == "aft_breachclaim" })
        XCTAssertTrue(e.answer(messageID: m.id, option: 2), "ignore the letters")
        XCTAssertTrue(kinds(e.state, id).contains("breachpress"), "ignoring them brings the reporter")
    }

    func testSettlingTheBreachClaimEndsTheChain() throws {
        var (e, id) = try engineWithCompany()
        var asked: Message? = nil
        e.update { s, data, ctx in
            fire(Aftermath.event("breachclaim")!, &s, id, data: data, ctx: ctx)
            asked = s.inbox.first { $0.status == "open" && $0.str("ev") == "aft_breachclaim" }
        }
        XCTAssertTrue(e.answer(messageID: try XCTUnwrap(asked).id, option: 0))
        XCTAssertFalse(kinds(e.state, id).contains("breachpress"))
    }

    func testLateSupplierInvoicesStartTheSupplierChainAndDelayDeepensIt() throws {
        var (e, id) = try engineWithCompany()
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].set("lt", .array([.number(Double(s.week))]))
            Aftermath.scanTriggers(&s)
            XCTAssertTrue(kinds(s, id).contains("suppnotice"))
            Aftermath.scanTriggers(&s)
            XCTAssertEqual(AftermathQueue.pending(s, companyID: id).filter { $0.kind == "suppnotice" }.count, 1, "queued once")
            s.week += 5
            Aftermath.weekly(&s, data: data, context: ctx)
        }
        let m = try XCTUnwrap(e.state.inbox.first { $0.status == "open" && $0.str("ev") == "aft_suppnotice" })
        XCTAssertTrue(e.answer(messageID: m.id, option: 2), "ignore the letter")
        XCTAssertTrue(kinds(e.state, id).contains("suppstop"))
    }

    func testAPriceCutDrawsARivalReplyButAnEventPriceMoveDoesNot() throws {
        var (e, id) = try engineWithCompany()
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].set("lastW", .object(["units": 10]))
            s.companies[i].priceLevel = 0
            Aftermath.scanTriggers(&s)   // first sight: remembered, nothing queued
            XCTAssertFalse(kinds(s, id).contains("pwreply"))
            // A price level moved by an event answer is recorded as seen.
            let c = EventEngine.context(for: s.companies[i], data: data, country: World(state: s, data: data).country(s.companies[i]))
            EventEngine.apply(&s, companyIndex: i, .object(["pr": -1]), ctx: c, event: GameEvent(id: "r_priceWar", json: .object([:])), data: data, context: ctx)
            Aftermath.scanTriggers(&s)
            XCTAssertFalse(kinds(s, id).contains("pwreply"))
            // The player's own cut: some week of the next few draws the reply.
            var queued = false
            for w in 1...40 where !queued {
                s.week += 1
                let j = s.companyIndex(id)!
                s.companies[j].priceLevel = s.companies[j].priceLevel + 1
                Aftermath.scanTriggers(&s)
                s.companies[j].priceLevel = s.companies[j].priceLevel - 1
                Aftermath.scanTriggers(&s)
                queued = kinds(s, id).contains("pwreply")
                _ = w
            }
            XCTAssertTrue(queued)
        }
    }

    // MARK: Late-game answer and thinning

    func testLateGamePlayersGetAFourthAnswerAndEarlyOnesDoNot() throws {
        let lib = try EventLibrary.bundled()
        let ev = try XCTUnwrap(lib["g_late"])
        var (early, id) = try engineWithCompany()
        early.update { s, data, ctx in
            XCTAssertFalse(EventEngine.isLateGame(s))
            fire(ev, &s, id, data: data, ctx: ctx)
            XCTAssertEqual(s.inbox.first { $0.status == "open" && $0.str("ev") == "g_late" }?.options.count, ev.options.count)
        }
        var (late, lid) = try engineWithCompany(trades: ["cafe", "tutor", "handy"])
        late.update { s, data, ctx in
            XCTAssertTrue(EventEngine.isLateGame(s))
            fire(ev, &s, lid, data: data, ctx: ctx)
            let m = s.inbox.first { $0.status == "open" && $0.str("ev") == "g_late" && $0.companyID == lid }
            XCTAssertEqual(m?.options.count, ev.options.count + 1)
            XCTAssertEqual(m?.options.last?["fx"]["tier"].int, 4)
        }
        let m = try XCTUnwrap(late.state.inbox.first { $0.status == "open" && $0.str("ev") == "g_late" && $0.companyID == lid })
        let cash = late.state.company(lid)!.cash
        XCTAssertTrue(late.answer(messageID: m.id, option: m.options.count - 1))
        XCTAssertLessThan(late.state.company(lid)!.cash, cash, "the extra answer costs money")
        XCTAssertTrue(Ledger.gaps(late.state).isEmpty)
        // The extra answer is never the default when time runs out.
        late.update { s, data, ctx in
            fire(ev, &s, lid, data: data, ctx: ctx)
            s.week += 10
            EventEngine.expire(&s, data: data, context: ctx)
            let done = s.inbox.first { $0.str("ev") == "g_late" && $0.flag("auto") }
            XCTAssertNotNil(done)
            XCTAssertLessThan(done?.value("pick").int ?? 99, ev.options.count)
        }
    }

    func testGoodEventsNeedFewerWeeksForASecondCompany() throws {
        var (e, _) = try engineWithCompany(trades: ["cafe", "tutor"])
        e.update { s, _, _ in
            let own = s.companies.indices.filter { s.companies[$0].type != "hold" }
            XCTAssertGreaterThanOrEqual(own.count, 2)
            XCTAssertEqual(EventEngine.goodEventMinimumWeeks(s, companyIndex: own[0]), 12)
            XCTAssertEqual(EventEngine.goodEventMinimumWeeks(s, companyIndex: own[1]), 6)
        }
    }

    func testCooldownVariesByToneAndStaysInRange() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        e.update { s, _, _ in
            var seen = Set<Double>()
            for w in 1...30 {
                s.week = w
                let good = EventEngine.cooldownWeeks(s, companyID: 1, event: GameEvent(id: "x", json: .object(["tone": "good"])))
                let bad = EventEngine.cooldownWeeks(s, companyID: 1, event: GameEvent(id: "y", json: .object(["tone": "bad"])))
                XCTAssertTrue((3.0...5.0).contains(good)); XCTAssertTrue((6.0...8.0).contains(bad))
                seen.insert(bad)
            }
            XCTAssertGreaterThan(seen.count, 1)
        }
    }

    // MARK: Trade packs

    func testEachStarterTradePackIsDefinedAttachedAndShaped() throws {
        let lib = try EventLibrary.bundled()
        let (data, _, _) = try GameEngine.loadResources()
        for trade in Self.packTrades {
            let t = try XCTUnwrap(data.catalog[trade], trade)
            let pack = t.eventIDs.filter { $0.hasPrefix(trade + "_") }
            XCTAssertTrue((3...4).contains(pack.count), "\(trade): \(pack.count) pack events")
            for id in pack {
                let e = try XCTUnwrap(lib[id], id)
                XCTAssertTrue((2...3).contains(e.options.count), id)
                XCTAssertGreaterThan(e.weight, 0, id)
                XCTAssertTrue(e.options.allSatisfy { !$0.detail.isEmpty }, id)
            }
        }
    }

    // MARK: Streaks

    /// A day whose goal ("play two weeks", counted from week -5) is already done, so the first read grows the streak.
    func dailyState(_ e: inout GameEngine, streak: Int, last: Date, day: Date, prot: Int = 0) {
        e.update { s, _, _ in
            var d: [String: JSONValue] = ["streak": .number(Double(streak)), "last": .string(GameEngine.dayString(last)), "d": .string(GameEngine.dayString(day)), "got": 0, "k": "weeks",
                                          "b": .object(["week": -5, "staff": 0, "cmp": 0, "nw": 1])]
            if prot > 0 { d["prot"] = .number(Double(prot)) }
            s.rest["dy59"] = .object(d)
        }
    }

    func testStreakMilestoneGivesACreditBumpAndATitleButNoCash() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 8)
        let day = Date(timeIntervalSince1970: 1_800_000_000), yesterday = day.addingTimeInterval(-86400)
        dailyState(&e, streak: 2, last: yesterday, day: day)
        let credit = e.state.credit, cash = e.state.cash
        let g = try XCTUnwrap(e.dailyGoal(now: day))
        XCTAssertEqual(g.streak, 3)
        XCTAssertEqual(e.state.credit, min(100, credit + 1), accuracy: 1e-9)
        XCTAssertEqual(e.state.cash, cash, accuracy: 0.001)
        XCTAssertEqual(e.streakInfo(now: day).title, "Regular")
        XCTAssertEqual(e.streakInfo(now: day).nextMilestone, 7)
        _ = try XCTUnwrap(e.dailyGoal(now: day))
        XCTAssertEqual(e.state.credit, min(100, credit + 1), accuracy: 1e-9, "granted once")
    }

    func testSevenDaysGiveOneProtectionTokenAndOneMissedDayIsRestored() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 8)
        let day = Date(timeIntervalSince1970: 1_800_000_000), yesterday = day.addingTimeInterval(-86400), twoAgo = day.addingTimeInterval(-2 * 86400)
        dailyState(&e, streak: 6, last: yesterday, day: day)
        XCTAssertEqual(try XCTUnwrap(e.dailyGoal(now: day)).streak, 7)
        XCTAssertEqual(e.streakInfo(now: day).protectionTokens, 1)
        // A missed day with a token: coming back restores the streak and uses the token.
        dailyState(&e, streak: 4, last: twoAgo, day: day, prot: 1)
        XCTAssertTrue(e.streakInfo(now: day).savedByProtection)
        XCTAssertEqual(e.streakInfo(now: day).count, 4)
        XCTAssertEqual(try XCTUnwrap(e.dailyGoal(now: day)).streak, 5)
        XCTAssertEqual(e.streakInfo(now: day).protectionTokens, 0)
        // Without a token the streak starts again.
        dailyState(&e, streak: 4, last: twoAgo, day: day)
        XCTAssertEqual(e.streakInfo(now: day).count, 0)
        XCTAssertEqual(try XCTUnwrap(e.dailyGoal(now: day)).streak, 1)
    }

    func testAppVisitsCompleteTheGoalsThatWatchThem() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 8)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(e.noteVisit(app: "bank", now: day), "no goal watches the bank")
        e.update { s, _, _ in
            s.rest["dy59"] = .object(["streak": 0, "last": "", "d": .string(GameEngine.dayString(day)), "got": 0, "k": "news", "b": .object([:])])
        }
        XCTAssertFalse(try XCTUnwrap(e.dailyGoal(now: day)).done)
        XCTAssertTrue(e.noteVisit(app: "news", now: day))
        XCTAssertFalse(e.noteVisit(app: "news", now: day), "recorded once a day")
        let g = try XCTUnwrap(e.dailyGoal(now: day))
        XCTAssertTrue(g.done)
        XCTAssertEqual(g.streak, 1)
        XCTAssertEqual(g.link, "news")
    }

    func testReminderTextLeadsWithTheStreak() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 8)
        let day = Date(timeIntervalSince1970: 1_800_000_000), yesterday = day.addingTimeInterval(-86400)
        e.update { s, _, _ in s.rest["dy59"] = .object(["streak": 6, "last": .string(GameEngine.dayString(yesterday))]) }
        let r = SessionHooks.reminders(e.state, now: day)
        XCTAssertFalse(r.isEmpty)
        XCTAssertTrue(r.allSatisfy { $0.body.hasPrefix("Day 6 streak. ") })
        e.update { s, _, _ in s.rest["dy59"] = nil }
        XCTAssertTrue(SessionHooks.reminders(e.state, now: day).allSatisfy { !$0.body.contains("streak") })
    }

    // MARK: Advanced goals

    func testAdvancedGoalsAppearOnlyAfterTheLadderAndAreMarkedAdvanced() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 8)
        XCTAssertTrue(PlayerGoals.advancedGoals(e.state).isEmpty)
        XCTAssertEqual(PlayerGoals.ladder(e.state)?.count, 10)
        e.update { s, _, _ in
            s.rest["ldr"] = .object(["done": .object(Dictionary(uniqueKeysWithValues: (1...10).map { ("M\($0)", JSONValue.object(["w": .number(Double(s.week))])) }))])
        }
        let adv = PlayerGoals.advancedGoals(e.state)
        XCTAssertEqual(adv.map { $0.id }, ["A1", "A2"])
        XCTAssertTrue(adv.allSatisfy { $0.advanced && !$0.done && $0.reward.isEmpty })
        XCTAssertTrue(PlayerGoals.ladder(e.state)?.allSatisfy { !$0.advanced } ?? false)
    }

    // MARK: Recap and mastery reads

    func testSinceYouLeftReportsDaysPassedAndNothingWhenNothingChanged() throws {
        var (e, _) = try engineWithCompany(weeks: 1)
        e.markSeen()
        let seen = try XCTUnwrap(e.lastSeenDay)
        XCTAssertEqual(seen, e.gameDayNumber)
        let quiet = e.sinceYouLeft(lastSeenDay: seen)
        XCTAssertTrue(quiet == nil || !(quiet?.lines.contains { $0.contains("passed") } ?? false))
        for _ in 0..<3 { e.nextDay() }
        let r = try XCTUnwrap(e.sinceYouLeft(lastSeenDay: seen))
        XCTAssertEqual(r.title, "Since you left")
        XCTAssertTrue(r.lines.contains("3 days have passed."))
        XCTAssertLessThanOrEqual(r.lines.count, 4)
    }

    func testSinceYouLeftCountsExpiredDecisions() throws {
        var (e, id) = try engineWithCompany(weeks: 1)
        e.markSeen()
        let seen = try XCTUnwrap(e.lastSeenDay)
        e.update { s, _, _ in
            let opts = [JSONValue.option("A", "", effects: [:]), JSONValue.option("B", "", effects: [:])]
            let mid = s.addMessage(kind: "decision", from: "Test", title: "t", body: "", companyID: id, status: "open", options: opts, expiresWeek: s.week + 1)
            if let k = s.inbox.firstIndex(where: { $0.id == mid }) { s.inbox[k].set("status", "done"); s.inbox[k].set("auto", 1); s.inbox[k].set("pick", 0) }
            s.week += 2
        }
        let r = try XCTUnwrap(e.sinceYouLeft(lastSeenDay: seen))
        XCTAssertTrue(r.lines.contains("One decision ran out and took the default answer."))
    }

    func testDelegationLineAndThePlayingPanel() throws {
        var (e, id) = try engineWithCompany(weeks: 1)
        let before = e.delegationCounts(firstWeek: 0, lastWeek: e.state.week)
        e.update { s, _, _ in
            let opts = [JSONValue.option("A", "", effects: [:]), JSONValue.option("B", "", effects: [:])]
            for n in 0..<3 {
                let mid = s.addMessage(kind: "decision", from: "Test", title: "t\(n)", body: "", companyID: id, status: "open", options: opts)
                if let k = s.inbox.firstIndex(where: { $0.id == mid }) { s.inbox[k].set("w", s.week); if n < 2 { s.inbox[k].handledBy = "Mia, manager" } }
            }
        }
        let after = e.delegationCounts(firstWeek: 0, lastWeek: e.state.week)
        XCTAssertEqual(after.total, before.total + 3)
        XCTAssertEqual(after.team, before.team + 2)
        XCTAssertEqual(e.delegationLine(firstWeek: 0, lastWeek: e.state.week), "Decisions this week: \(after.total). Handled by your team: \(after.team). Escalated to you: \(after.you).")
        let rows = e.playingPanel()
        XCTAssertEqual(rows.map { $0.id }, ["delegation", "managers", "brand", "credit", "complaints"])
        XCTAssertTrue(rows.allSatisfy { !$0.why.isEmpty && !$0.value.isEmpty && ["good", "ok", "weak"].contains($0.tone) })
        XCTAssertTrue(e.seedLine.contains("\(e.state.seed)"))
    }
}
