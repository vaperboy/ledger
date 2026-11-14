import XCTest
@testable import Events
@testable import Businesses
@testable import Simulation
import GameCore
import Countries
import Finance

final class DecisionChoiceTests: XCTestCase {
    func engineWithCompany(trade: String = "cafe", weeks: Int = 3, seed: Int = 4242) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        var extra = 0
        while e.state.company(id)?.status != .open && extra < 28 { e.nextDay(); extra += 1 }
        return (e, id)
    }

    func fire(_ ev: GameEvent, _ s: inout GameState, _ id: Int, data: GameData, ctx: FinanceContext) {
        let i = s.companyIndex(id)!
        let c = EventEngine.context(for: s.companies[i], data: data, country: World(state: s, data: data).country(s.companies[i]))
        EventEngine.fire(&s, companyIndex: i, ev, ctx: c, data: data, context: ctx)
    }

    func openEvent(_ s: GameState, _ id: String) -> Message? {
        s.inbox.first { (m: Message) -> Bool in m.status == "open" && m.str("ev") == id }
    }

    // MARK: The tapped answer is the one applied

    func testATestEventAppliesExactlyTheTappedAnswer() throws {
        let (base, id) = try engineWithCompany()
        let json: JSONValue = .object([
            "t": "A test choice at {n}.", "w": 0.01, "tone": "n", "exp": 2,
            "opts": .array([
                .object(["l": "First", "d": "Reputation.", "fx": .object(["rep": 2])]),
                .object(["l": "Second", "d": "Awareness.", "fx": .object(["aware": 6])]),
                .object(["l": "Third", "d": "Money.", "fx": .object(["cash": -1500])])]),
        ])
        let ev = GameEvent(id: "test_pick", json: json)
        for k in 0..<3 {
            var e = base
            var asked: Message? = nil
            e.update { s, data, ctx in fire(ev, &s, id, data: data, ctx: ctx); asked = openEvent(s, "test_pick") }
            let m = try XCTUnwrap(asked)
            let before = try XCTUnwrap(e.state.company(id))
            XCTAssertTrue(e.answer(messageID: m.id, option: k))
            let after = try XCTUnwrap(e.state.company(id))
            XCTAssertEqual(after.reputation > before.reputation, k == 0, "option \(k): reputation")
            XCTAssertEqual(after.awareness > before.awareness, k == 1, "option \(k): awareness")
            XCTAssertEqual(after.cash < before.cash - 1, k == 2, "option \(k): cash")
            let done = e.state.inbox.first { $0.id == m.id }
            XCTAssertEqual(done?.status, "done")
            XCTAssertEqual(done?.value("pick").int, k)
        }
    }

    func testEveryLibraryAnswerAppliesItsOwnEffects() throws {
        let lib = try EventLibrary.bundled()
        let (base, id) = try engineWithCompany()
        var checked = 0
        for ev in lib.events.values.sorted(by: { $0.id < $1.id }) where ev.options.count >= 2 {
            for k in 0..<ev.options.count {
                var a = base
                var asked: Message? = nil
                a.update { s, data, ctx in fire(ev, &s, id, data: data, ctx: ctx); asked = openEvent(s, ev.id) }
                guard let m = asked, m.options.indices.contains(k) else { continue }
                var b = a
                XCTAssertTrue(a.answer(messageID: m.id, option: k), "\(ev.id) option \(k)")
                b.update { s, data, ctx in
                    let i = s.companyIndex(id)!
                    let c = EventEngine.context(for: s.companies[i], data: data, country: World(state: s, data: data).country(s.companies[i]))
                    let e = GameEvent(id: m.str("ev"), json: .object(["cat": .string(m.str("cat", "none"))]))
                    EventEngine.apply(&s, companyIndex: i, m.options[k]["fx"], ctx: c, event: e, data: data, context: ctx)
                }
                XCTAssertEqual(a.state.company(id), b.state.company(id), "\(ev.id): answer \(k) applied something other than its own effects")
                XCTAssertEqual(a.state.inbox.first { $0.id == m.id }?.value("pick").int, k, ev.id)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 200)
    }

    func testStrategicAndStakeAnswersRunTheChosenOption() throws {
        let (base, id) = try engineWithCompany(weeks: 6)
        let def = try XCTUnwrap(StrategicDecisions.byID["st_contract"])
        var demand: [Double] = []
        for k in 0..<def.opts.count {
            var e = base
            var asked: Message? = nil
            e.update { s, data, ctx in
                let i = s.companyIndex(id)!
                XCTAssertTrue(StrategicDecisions.fire(&s, def, companyIndex: i, data: data, context: ctx))
                asked = s.inbox.first { $0.status == "open" && $0.actionID == StrategicDecisions.action }
            }
            let m = try XCTUnwrap(asked)
            XCTAssertTrue(e.answer(messageID: m.id, option: k))
            demand.append(DemandModel.modifier(try XCTUnwrap(e.state.company(id)), "dem"))
        }
        XCTAssertEqual(demand.count, 3)
        XCTAssertLessThan(demand[0], demand[2], "turning it down adds no work")
        XCTAssertLessThan(demand[2], demand[1], "half the volume is less than the full volume")
    }

    // MARK: What an answer reports

    func testAnswerDecisionSaysWhatHappenedAndPicksTheTappedIndex() throws {
        let (base, id) = try engineWithCompany()
        let json: JSONValue = .object([
            "t": "A risky choice at {n}.", "w": 0.01, "tone": "n", "exp": 2,
            "opts": .array([
                .object(["l": "Decline", "d": "Nothing changes.", "fx": .object([:])]),
                .object(["l": "Try it", "d": "It may work.", "fx": .object(["gamble": .object(["p": 0.5, "ok": .object(["aware": 5]), "bad": .object(["rep": -2])])])])]),
        ])
        let ev = GameEvent(id: "test_risk", json: json)
        var e = base
        var asked: Message? = nil
        e.update { s, data, ctx in fire(ev, &s, id, data: data, ctx: ctx); asked = openEvent(s, "test_risk") }
        let m = try XCTUnwrap(asked)
        var quiet = e
        let r = e.answerDecision(messageID: m.id, option: 1)
        XCTAssertTrue(r.applied)
        XCTAssertTrue(r.lines.contains("It worked out.") || r.lines.contains("It did not work out."), r.lines.joined(separator: " | "))
        XCTAssertEqual(e.state.inbox.first { $0.id == m.id }?.value("pick").int, 1)
        XCTAssertNil(e.state.rest[EventEngine.gambleKey])
        let n = quiet.answerDecision(messageID: m.id, option: 0)
        XCTAssertTrue(n.applied)
        XCTAssertEqual(n.lines, ["Nothing changes for now."])
        XCTAssertFalse(quiet.answerDecision(messageID: m.id, option: 0).applied, "a decision is answered once")
    }

    func testLinksPointAtTheScreenTheDecisionIsAbout() throws {
        let lib = try EventLibrary.bundled()
        let (base, id) = try engineWithCompany()
        func link(_ evID: String, _ k: Int) throws -> DecisionLink? {
            var e = base
            var asked: Message? = nil
            let ev = try XCTUnwrap(lib[evID], evID)
            e.update { s, data, ctx in fire(ev, &s, id, data: data, ctx: ctx); asked = openEvent(s, evID) }
            let m = try XCTUnwrap(asked, evID)
            return e.answerDecision(messageID: m.id, option: k).link
        }
        XCTAssertEqual(try link("g_quit", 0)?.section, "staff")
        XCTAssertEqual(try link("r_priceWar", 0)?.section, "salesMarket")
        XCTAssertEqual(try link("g_supply", 1)?.section, "operations")
        XCTAssertNil(try link("g_fire", 0), "no single screen helps with a fire")
    }

    // MARK: Order and wording

    func testNoSitsLeftYesRightAndTheRestGoBelow() throws {
        let pair = DecisionOrder.layout(["Accept", "Decline"])
        XCTAssertEqual(pair.no, 1)
        XCTAssertEqual(pair.yes, 0)
        XCTAssertEqual(pair.others, [])
        XCTAssertEqual(pair.kind(0), .yes)
        XCTAssertEqual(pair.kind(1), .no)
        let three = DecisionOrder.layout(["Take the full project", "Take the design phase only", "Decline"])
        XCTAssertEqual(three.no, 2)
        XCTAssertEqual(three.yes, 0)
        XCTAssertEqual(three.others, [1], "a third answer goes in its own row")
        XCTAssertEqual(three.kind(1), .neutral)
        XCTAssertEqual(DecisionOrder.layout(["Raise prices", "Wait it out", "Sign the deal"]).yes, 2, "a plain yes takes the right side")
        XCTAssertEqual(DecisionOrder.layout(["Vote yes", "Vote no"]).order, [1, 0])
        let equal = DecisionOrder.layout(["Repair now", "Run without it", "Replace"])
        XCTAssertFalse(equal.hasPair, "several paths with no turn-down are equal")
        XCTAssertEqual(equal.others, [0, 1, 2])
        XCTAssertTrue((0..<3).allSatisfy { equal.kind($0) == .neutral })
        XCTAssertFalse(DecisionOrder.layout(["Absorb it", "Pass part on to customers"]).hasPair)
        XCTAssertFalse(DecisionOrder.layout(["Skip it", "Decline"]).hasPair, "two ways of saying no are not a pair")
        XCTAssertFalse(DecisionOrder.layout(["Understood"]).hasPair)
    }

    func testEveryLayoutIsAPermutationAndPairsAreYesAndNo() throws {
        let lib = try EventLibrary.bundled()
        let library: [[String]] = lib.events.values.map { (e: GameEvent) -> [String] in e.options.map { (o: GameEvent.Option) -> String in o.label } }
        let pack: [[String]] = EventPack.events.map { (e: PackEvent) -> [String] in e.event.options.map { (o: GameEvent.Option) -> String in o.label } }
        let asks: [[String]] = StrategicDecisions.definitions.map { (d: StrategicDecisions.Def) -> [String] in d.opts.map { (o: StrategicDecisions.Opt) -> String in o.label } }
        let all: [[String]] = library + pack + asks
        var pairs = 0
        for labels in all where labels.count >= 2 {
            let l = DecisionOrder.layout(labels)
            XCTAssertEqual(l.order.sorted(), Array(labels.indices), labels.joined(separator: " / "))
            XCTAssertEqual(DecisionOrder.shown(labels), l.order)
            if let no = l.no, let yes = l.yes {
                pairs += 1
                XCTAssertTrue(DecisionOrder.isNo(labels[no]), "left is not a No: \(labels)")
                XCTAssertFalse(DecisionOrder.isNo(labels[yes]), "right is a No: \(labels)")
            } else {
                XCTAssertEqual(l.others, Array(labels.indices), "equal answers keep their own order: \(labels)")
            }
        }
        XCTAssertGreaterThan(pairs, 40)
    }

    func testAnswerResultsShowNoEngineNumbers() throws {
        let (base, id) = try engineWithCompany()
        let json: JSONValue = .object([
            "t": "A plain choice at {n}.", "w": 0.01, "tone": "n", "exp": 2,
            "opts": .array([
                .object(["l": "Decline", "d": "Nothing changes.", "fx": .object([:])]),
                .object(["l": "Run the campaign", "d": "More people hear of you.",
                         "fx": .object(["rep": 2, "aware": 6, "dem": .array([1.05, 3]), "cash": -150])])]),
        ])
        let ev = GameEvent(id: "test_story", json: json)
        var e = base
        var asked: Message? = nil
        e.update { s, data, ctx in fire(ev, &s, id, data: data, ctx: ctx); asked = openEvent(s, "test_story") }
        let m = try XCTUnwrap(asked)
        let r = e.answerDecision(messageID: m.id, option: 1)
        XCTAssertTrue(r.applied)
        let all = r.lines.joined(separator: " | ")
        XCTAssertTrue(r.lines.allSatisfy { DecisionStory.isPlain($0) }, all)
        XCTAssertFalse(all.lowercased().contains("reputation"), all)
        XCTAssertFalse(all.contains("%"), all)
        XCTAssertFalse(all.contains("cost you"), "a small cost is felt, not shown: \(all)")
        XCTAssertLessThanOrEqual(r.lines.count, DecisionStory.maxLines)
        XCTAssertTrue(r.lines.contains("People think better of you."), all)
    }

    func testABigChoiceShowsOneCostLine() throws {
        let (base, id) = try engineWithCompany()
        let weekly = try XCTUnwrap(base.state.company(id)).lastWeekRevenue
        let price = max(5000, weekly * 3)
        let json: JSONValue = .object([
            "t": "A lawsuit at {n}.", "w": 0.01, "tone": "bad", "exp": 2,
            "opts": .array([
                .object(["l": "Fight it", "d": "", "fx": .object(["rep": -1])]),
                .object(["l": "Settle", "d": "", "fx": .object(["cash": .number(-price)])])]),
        ])
        let ev = GameEvent(id: "test_settle", json: json)
        var e = base
        var asked: Message? = nil
        e.update { s, data, ctx in fire(ev, &s, id, data: data, ctx: ctx); asked = openEvent(s, "test_settle") }
        let m = try XCTUnwrap(asked)
        let r = e.answerDecision(messageID: m.id, option: 1)
        let costs = r.lines.filter { $0.hasPrefix("It cost you") }
        XCTAssertEqual(costs.count, 1, r.lines.joined(separator: " | "))
        XCTAssertTrue(r.lines.allSatisfy { DecisionStory.isPlain($0) }, "one account: no separate signed money lines: \(r.lines)")
        XCTAssertFalse(r.lines.contains { $0.hasPrefix("Your own cash") })
    }

    func testStoryLinesHaveNoNumbers() throws {
        let cur = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7).homeCurrency
        let fx: JSONValue = .object(["rep": 3, "aware": -2, "q": 1, "dem": .array([0.9, 4]), "cap": .array([1.1, 2]), "pr": 1, "raise": 0.05, "warn": true])
        let lines = EffectPreview.story(fx, currency: cur)
        XCTAssertFalse(lines.isEmpty)
        for l in lines { XCTAssertNil(l.range(of: #"\d"#, options: .regularExpression), l) }
        XCTAssertTrue(EffectPreview.story(.null, currency: cur).isEmpty)
        let paid = EffectPreview.story(.object(["cash": -500, "fine": 200]), currency: cur, money: true)
        XCTAssertEqual(paid.filter { $0.hasPrefix("It cost you") }.count, 1, "cash and fine are one cost line")
    }

    func testOptionTextsDoNotSayWhichAnswerIsBest() throws {
        let lib = try EventLibrary.bundled()
        let fromLibrary: [(String, GameEvent.Option)] = lib.events.values.flatMap { (e: GameEvent) -> [(String, GameEvent.Option)] in e.options.map { (o: GameEvent.Option) -> (String, GameEvent.Option) in (e.id, o) } }
        let fromPack: [(String, GameEvent.Option)] = EventPack.events.flatMap { (e: PackEvent) -> [(String, GameEvent.Option)] in e.event.options.map { (o: GameEvent.Option) -> (String, GameEvent.Option) in (e.id, o) } }
        let options: [(String, GameEvent.Option)] = fromLibrary + fromPack
        let banned = ["recommended", "(best)", "best option", "best choice", " safe.", "safe,", "safer", "safest", "the smart"]
        for (id, o) in options {
            let words = (" " + o.label + " " + o.detail).lowercased()
            for b in banned { XCTAssertFalse(words.contains(b), "\(id): \"\(o.label)\" says \(b)") }
            if case .object(let g) = o.effects["gamble"], case .object = g["p"] ?? .null {
                XCTAssertNil(o.detail.range(of: #"\d+ ?%"#, options: .regularExpression), "\(id): fixed odds in the text, but they depend on the situation")
            }
        }
        for def in StrategicDecisions.definitions {
            for o in def.opts {
                let words = (" " + o.label + " " + o.detail).lowercased()
                for b in banned { XCTAssertFalse(words.contains(b), "\(def.id): \"\(o.label)\" says \(b)") }
            }
        }
    }

    func testEachAnswerHasItsOwnConsequence() throws {
        let lib = try EventLibrary.bundled()
        let fromLibrary: [(String, [JSONValue])] = lib.events.values.map { (e: GameEvent) -> (String, [JSONValue]) in (e.id, e.options.map { (o: GameEvent.Option) -> JSONValue in o.effects }) }
        let fromPack: [(String, [JSONValue])] = EventPack.events.map { (e: PackEvent) -> (String, [JSONValue]) in (e.id, e.event.options.map { (o: GameEvent.Option) -> JSONValue in o.effects }) }
        let sets: [(String, [JSONValue])] = fromLibrary + fromPack
        for (id, fx) in sets where fx.count >= 2 {
            let neutral = fx.filter { $0.isNull || $0.object.isEmpty }.count
            XCTAssertLessThanOrEqual(neutral, 1, "\(id): more than one answer does nothing")
            for a in 0..<fx.count { for b in (a + 1)..<fx.count where !(fx[a].isNull && fx[b].isNull) { XCTAssertNotEqual(fx[a], fx[b], "\(id): answers \(a) and \(b) do the same") } }
        }
    }

    // MARK: The best answer varies with the situation

    func situations() -> [EventEngine.Context] {
        let low: [String: Double] = ["co.rep": 30, "co.q": 35, "co.mood": 35, "co.eqc": 0.45, "co.books": 0.2, "co.cashWk": 1, "co.util": 0.97, "co.mgrQ": 0.3, "co.payGap": 0.1, "co.staffN": 3, "k": 1]
        let high: [String: Double] = ["co.rep": 80, "co.q": 80, "co.mood": 85, "co.eqc": 1, "co.books": 0.9, "co.cashWk": 14, "co.util": 0.55, "co.mgrQ": 0.8, "co.payGap": 0, "co.staffN": 8, "k": 1]
        var out: [EventEngine.Context] = []
        for wk in [1000.0, 5000.0, 40000.0] {
            for st in [low, high] {
                let v: [String: Double] = st.merging(["wk": wk, "pay": wk * 0.4, "eqv": wk * 15]) { (_: Double, b: Double) -> Double in b }
                out.append(EventEngine.Context(wk: wk, pay: wk * 0.4, eqv: wk * 15, variables: v))
            }
        }
        return out
    }

    func testTheFirstAnswerIsNotSystematicallyTheBest() throws {
        let lib = try EventLibrary.bundled()
        let fromLibrary: [[JSONValue]] = lib.events.values.map { (e: GameEvent) -> [JSONValue] in e.options.map { (o: GameEvent.Option) -> JSONValue in o.effects } }
        let fromPack: [[JSONValue]] = EventPack.events.map { (e: PackEvent) -> [JSONValue] in e.event.options.map { (o: GameEvent.Option) -> JSONValue in o.effects } }
        let sets: [[JSONValue]] = fromLibrary + fromPack
        let ctxs = situations()
        var events = 0, firstAlways = 0, varies = 0
        for fx in sets where fx.count >= 2 {
            events += 1
            var winners = Set<Int>()
            for c in ctxs {
                let scores: [Double] = fx.map { EventEngine.score(EventEngine.resolve($0, c), c) }
                winners.insert(scores.indices.max { scores[$0] < scores[$1] } ?? 0)
            }
            if winners == [0] { firstAlways += 1 }
            if winners.count > 1 { varies += 1 }
        }
        XCTAssertGreaterThan(events, 200)
        XCTAssertLessThan(Double(firstAlways) / Double(events), 0.34, "\(firstAlways) of \(events) events: the first answer always wins")
        XCTAssertGreaterThan(Double(varies) / Double(events), 0.4, "only \(varies) of \(events) events change their best answer with the situation")
    }

    func testOddsFollowTheSituation() throws {
        let lib = try EventLibrary.bundled()
        let ev = try XCTUnwrap(lib["g_press"])
        let ctxs = situations()
        let lowP = EventEngine.resolve(ev.options[0].effects, ctxs[0])["gamble"]["p"].double
        let highP = EventEngine.resolve(ev.options[0].effects, ctxs[1])["gamble"]["p"].double
        XCTAssertLessThan(lowP, highP, "a well-liked company does better in an interview")
        XCTAssertTrue(lowP > 0.05 && highP < 0.95)
    }

    // MARK: Stake stories

    func testStakeStoriesAreCappedAndSpacedOut() throws {
        var (e, _) = try engineWithCompany()
        e.update { s, _, _ in
            s.rest.removeValue(forKey: StakeStories.key)
            XCTAssertTrue(StakeStories.room(s))
            StakeStories.record(&s)
            XCTAssertFalse(StakeStories.room(s), "two weeks apart")
            s.week += StakeStories.gapWeeks
            XCTAssertTrue(StakeStories.room(s))
            StakeStories.record(&s)
            s.week += 1
            XCTAssertFalse(StakeStories.room(s), "at most two in four weeks")
            s.week += StakeStories.windowWeeks
            XCTAssertTrue(StakeStories.room(s))
        }
    }

    func testAStakeStoryHasAFollowUpAWeekLater() throws {
        let (base, id) = try engineWithCompany(weeks: 6)
        let def = try XCTUnwrap(StrategicDecisions.byID["st_inspect"])
        for k in 0..<def.opts.count {
            var e = base
            var asked: Message? = nil
            e.update { s, data, ctx in
                let i = s.companyIndex(id)!
                XCTAssertTrue(StrategicDecisions.fire(&s, def, companyIndex: i, data: data, context: ctx))
                asked = s.inbox.first { $0.status == "open" && $0.actionID == StrategicDecisions.action }
            }
            let m = try XCTUnwrap(asked)
            XCTAssertTrue(e.answer(messageID: m.id, option: k))
            let top = e.state.inbox.map { $0.id }.max() ?? 0
            e.update { s, data, ctx in
                s.week += 1
                StrategicDecisions.weekly(&s, data: data, context: ctx)
            }
            let follow = e.state.inbox.filter { $0.id > top && $0.companyID == id && $0.title.hasPrefix("Inspection") }
            XCTAssertEqual(follow.count, 1, "option \(k): one inspection result")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        }
    }

    func testStakeStoriesArriveButNeverMoreThanTheCap() throws {
        var (e, _) = try engineWithCompany(weeks: 2, seed: 515)
        for _ in 0..<(48 * 7) {
            e.nextDay()
            for m in e.openDecisions where m.isOwnerAddressed && !m.options.isEmpty { _ = e.answer(messageID: m.id, option: m.options.count - 1) }
        }
        let weeks = StakeStories.firedWeeks(e.state)
        for w in weeks {
            let near = weeks.filter { $0 > w - StakeStories.windowWeeks && $0 <= w }
            XCTAssertLessThanOrEqual(near.count, StakeStories.perWindow, "weeks \(weeks)")
        }
        for (a, b) in zip(weeks, weeks.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, StakeStories.gapWeeks) }
        let stories = e.state.inbox.filter { StakeStories.pool.contains($0.value("data")["id"].string) }
        XCTAssertLessThanOrEqual(stories.count, (48 / StakeStories.windowWeeks + 1) * StakeStories.perWindow)
    }
}
