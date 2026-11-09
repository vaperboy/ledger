import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import SaveSystem
@testable import Events
@testable import Simulation

/// Events rebalance: the first-year ramp, the one-bad-event-a-week cap, blocking decisions, options on every
/// non-information event, and that the new state survives a save.
final class EventRebalanceTests: XCTestCase {
    /// Events that stay read-only Inbox rows: no options, `auto` (or the two untagged special ids).
    static let information: Set<String> = ["g_review", "g_award", "v_critic", "v_bigwin", "c_market", "d_market", "pr_subsidy", "rival_call", "probe", "g_heat"]

    func testRampWeightsByWeek() throws {
        let b = try Balance.bundled()
        for w in 1...4 { XCTAssertEqual(b.eventRampMultiplier(week: w), 0.0, "week \(w)") }
        for w in [5, 8, 12] { XCTAssertEqual(b.eventRampMultiplier(week: w), 0.35, "week \(w)") }
        for w in [13, 20, 26] { XCTAssertEqual(b.eventRampMultiplier(week: w), 0.7, "week \(w)") }
        for w in [27, 52, 400] { XCTAssertEqual(b.eventRampMultiplier(week: w), 1.0, "week \(w)") }
    }

    func testNoBadEventFiresInTheFirstFourWeeks() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 91)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 5_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        var bad = 0
        while e.state.week < 4 {
            let before = e.state.inbox.count
            e.nextDay()
            bad += e.state.inbox.prefix(max(0, e.state.inbox.count - before)).filter { $0.tone == "bad" && $0.companyID == id && $0.str("ev") != "" }.count
        }
        XCTAssertEqual(bad, 0)
    }

    func testOnlyOneBadEventAWeekInTheFirstTwelveWeeksTheSecondWaits() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 5)
        e.update { s, _, _ in
            s.week = 6
            XCTAssertTrue(EventEngine.takeBadSlot(&s, companyID: 1, eventID: "g_theft"))
            XCTAssertFalse(EventEngine.takeBadSlot(&s, companyID: 2, eventID: "g_theft"), "a second bad event in the same week waits")
            XCTAssertFalse(EventEngine.takeBadSlot(&s, companyID: 1, eventID: "g_power"))
            XCTAssertEqual(s.rest["evBad"]?["later"].array.count, 2)
            s.week = 7   // next week the slot is free again
            XCTAssertTrue(EventEngine.takeBadSlot(&s, companyID: 2, eventID: "g_theft"))
            XCTAssertFalse(EventEngine.takeBadSlot(&s, companyID: 1, eventID: "g_power"))
            s.week = 13  // the cap ends after week 12
            XCTAssertTrue(EventEngine.takeBadSlot(&s, companyID: 1, eventID: "g_power"))
            XCTAssertTrue(EventEngine.takeBadSlot(&s, companyID: 2, eventID: "g_power"))
        }
    }

    func testADeferredBadEventFiresNextWeek() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 12)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 5_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        for _ in 0..<(3 * 7) { e.nextDay() }
        // The company's own weekday decides when its paperwork clears and it opens: play on until it has.
        var extra = 0
        while e.state.company(id)?.status != .open && extra < 14 { e.nextDay(); extra += 1 }
        let lib = e.events
        e.update { s, data, ctx in
            XCTAssertEqual(s.company(id)?.status, .open)
            s.week = 8
            XCTAssertTrue(EventEngine.takeBadSlot(&s, companyID: 99, eventID: "g_theft"))   // another company used this week's slot
            XCTAssertFalse(EventEngine.takeBadSlot(&s, companyID: id, eventID: "g_theft"))
            let before = s.inbox.count
            s.week = 9
            let i = s.companyIndex(id)!
            EventEngine.fireDeferred(&s, companyIndex: i, library: lib, data: data, context: ctx)
            XCTAssertGreaterThan(s.inbox.count, before, "the put-off event arrives the next week")
            XCTAssertTrue(s.rest["evBad"]?["later"].array.isEmpty ?? true)
        }
    }

    func testBlockingEventsAreFewAndFollowTheRule() throws {
        let lib = try EventLibrary.bundled()
        let blocking = lib.events.values.filter { $0.blocking }
        XCTAssertLessThanOrEqual(blocking.count, 8)
        XCTAssertFalse(blocking.isEmpty)
        for e in blocking {
            XCTAssertEqual(e.expiresAfterWeeks, 1, e.id)
            XCTAssertTrue(["liab", "cyber"].contains(e.category), e.id)
            XCTAssertFalse(e.options.isEmpty, "\(e.id): a blocking event must be answerable")
        }
        let qualifying = lib.events.values.filter { $0.expiresAfterWeeks == 1 && ["liab", "cyber"].contains($0.category) }.sorted { $0.weight > $1.weight }
        XCTAssertEqual(Set(blocking.map { $0.id }), Set(qualifying.prefix(8).map { $0.id }))
    }

    func testHasBlockingDecisionFollowsTheOpenInbox() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 3)
        XCTAssertFalse(e.hasBlockingDecision)
        var plain = 0, blocking = 0
        e.update { s, _, _ in
            let opts = [JSONValue.option("Take the hit", "", effects: [:]), JSONValue.option("Pay", "", effects: ["cash": .number(-1)])]
            plain = s.addMessage(kind: "decision", from: "Test", title: "plain", body: "", status: "open", options: opts)
            if let k = s.inbox.firstIndex(where: { $0.id == plain }) { s.inbox[k].set("ev", "g_power") }
        }
        XCTAssertFalse(e.hasBlockingDecision, "a non-blocking decision does not block")
        e.update { s, _, _ in
            let opts = [JSONValue.option("Take the hit", "", effects: [:]), JSONValue.option("Pay", "", effects: [:])]
            blocking = s.addMessage(kind: "decision", from: "Test", title: "blocking", body: "", status: "open", options: opts)
            if let k = s.inbox.firstIndex(where: { $0.id == blocking }) { s.inbox[k].set("ev", "g_it") }
        }
        XCTAssertTrue(e.hasBlockingDecision)
        e.update { s, _, _ in
            if let k = s.inbox.firstIndex(where: { $0.id == blocking }) { s.inbox[k].set("status", "done") }
        }
        XCTAssertFalse(e.hasBlockingDecision, "answered: Play is free again")
    }

    func testEveryNonInformationEventHasOptions() throws {
        let lib = try EventLibrary.bundled()
        for e in lib.events.values {
            let info = Self.information.contains(e.id) || (e.automatic && e.tone == "good")
            if info {
                XCTAssertTrue(e.options.isEmpty, "\(e.id): information events carry no options")
            } else {
                XCTAssertFalse(e.options.isEmpty, "\(e.id): needs options")
                XCTAssertFalse(e.automatic, "\(e.id): not auto")
            }
            XCTAssertFalse(e.tone.isEmpty)
        }
        for id in ["g_theft", "g_it", "g_audit", "r_stockout", "e_dryHole", "f_storm"] {
            XCTAssertEqual(lib[id]?.options.count, 2, id)
            XCTAssertEqual(lib[id]?.options.first?.label, "Take the hit", id)
        }
    }

    func testEveryTradeEventIsDefinedAndNewEventsAreAttached() throws {
        let lib = try EventLibrary.bundled()
        let (data, _, _) = try GameEngine.loadResources()
        var used = Set<String>()
        for (_, t) in data.catalog.trades { for id in t.eventIDs { XCTAssertNotNil(lib[id], "trade lists an unknown event \(id)"); used.insert(id) } }
        for id in lib.events.keys where id.hasPrefix("g_") || id.contains("_") {
            if ["rival_call", "probe", "v_health", "v_poison", "v_cold", "v_critic"].contains(id) { continue }
            XCTAssertTrue(used.contains(id), "\(id) is attached to no trade")
        }
    }

    func testMitigationHalvesTheEffectAndCostsCash() throws {
        let lib = try EventLibrary.bundled()
        let fuel = try XCTUnwrap(lib["l_fuel"])
        XCTAssertEqual(fuel.options[0].effects["price"][0].double, 1.18, accuracy: 1e-9)
        XCTAssertEqual(fuel.options[1].effects["price"][0].double, 1.09, accuracy: 1e-9)
        XCTAssertEqual(fuel.options[1].effects["cash"].double, -2000)
        let hole = try XCTUnwrap(lib["e_dryHole"])
        XCTAssertEqual(hole.options[1].effects["cash"].double, -2_000_000)
    }

    func testNewStateSurvivesSaveAndReload() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 44)
        e.update { s, _, _ in
            s.week = 6
            _ = EventEngine.takeBadSlot(&s, companyID: 1, eventID: "g_theft")
            _ = EventEngine.takeBadSlot(&s, companyID: 2, eventID: "g_power")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-evr-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(e.state, summary: store.summary(of: e.state, trades: e.data.catalog))
        let loaded = try store.load()
        XCTAssertEqual(loaded, e.state)
        XCTAssertEqual(loaded.rest["evBad"]?["later"].array.count, 1)
        let (data, events, marketing) = try GameEngine.loadResources()
        var b = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        for _ in 0..<(10 * 7) { e.nextDay(); b.nextDay() }
        XCTAssertEqual(e.state, b.state, "a reloaded game plays on exactly like the original")
    }

    func testSameSeedSameEventsIncludingTheCap() throws {
        func run() throws -> GameState {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 2024)
            e.update { s, data, ctx in
                Ledger.move(&s, .me, 50_000_000, why: "Test funds")
                if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) {
                    Payments.injectCash(&s, companyID: i, amount: 5_000_000)
                    _ = CompanySetup.quickSetup(&s, companyID: i, data: data, faithfulHiring: false)
                }
            }
            for _ in 0..<(30 * 7) { e.nextDay() }
            return e.state
        }
        XCTAssertEqual(try run(), try run())
    }
}
