import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Events
@testable import Simulation

final class DecisionDeliveryTests: XCTestCase {
    private func cafe(seed: Int = 21) throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine(seed: seed, ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        UnlocksTests.opened(&e, id, weeksAgo: 10)
        return (e, id)
    }

    private func route(_ from: String, _ title: String, tone: String = "n", sev: Int = 0, open: Bool = false, owner: Bool = true, kind: String = "info") -> MessageRoute {
        MessageRoutes.classify(kind: kind, from: from, title: title, status: open ? "open" : "done", hasOptions: open, tone: tone, sev: sev, ownerAddressed: owner)
    }

    func testEachKindOfMessageHasOneRoute() {
        XCTAssertEqual(route("Cafe", "A guest asks", open: true), .decision)
        XCTAssertEqual(route("Cafe", "A guest asks", open: true, owner: false), .inbox, "a desk's question stays with the desk")
        XCTAssertEqual(route("Bank", "Missed loan payment at Cafe", tone: "bad", sev: 3), .alert)
        XCTAssertEqual(route("Competition authority", "Price collusion uncovered at Cafe", tone: "bad"), .alert)
        XCTAssertEqual(route("Your broker", "A market crash looks close", tone: "bad"), .alert)
        XCTAssertEqual(route("X", "t", tone: "bad", sev: 3, owner: false), .inbox, "something a desk handled is not an alert")
        XCTAssertEqual(route("Payroll", "Payday: 900 paid"), .drop)
        XCTAssertEqual(route("Trophy wall", "First million", tone: "good"), .drop)
        XCTAssertEqual(route("Ambition", "Milestone: Ten shops", tone: "good"), .drop)
        XCTAssertEqual(route("Ambition", "What do you want to build?"), .inbox)
        XCTAssertEqual(route("Ann", "Cafe: what I did"), .report)
        XCTAssertEqual(route("Deliveries", "Parcel arrived"), .report)
        XCTAssertEqual(route("Market", "Rival opens next to Cafe"), .report)
        XCTAssertEqual(route("Market research", "Survey ready for Cafe", kind: "doc"), .inbox)
        XCTAssertEqual(route("Cafe", "A quiet week"), .inbox)
    }

    func testAReportLineIsNoMessageAndIsNotRepeated() throws {
        var (e, id) = try cafe()
        let before: Int = e.state.inbox.count
        e.update { s, _, _ in
            s.addMessage(from: "Deliveries", title: "Parcel arrived", body: "b", companyID: id)
            s.note("Parcel arrived")
        }
        XCTAssertEqual(e.state.inbox.count, before)
        XCTAssertEqual(e.state.feedToday().map { $0.text }, ["Parcel arrived"])
        XCTAssertEqual((e.state.rest["rep"]?["ev"].array ?? []).filter { $0["t"].string == "Parcel arrived" }.count, 1)
    }

    func testDecisionsArriveTheSameDayOtherNewsIsSpreadOut() throws {
        var (e, id) = try cafe()
        let mark = e.beginSlice()
        e.update { s, _, _ in
            s.addMessage(kind: "ask", from: "Cafe", title: "Today's question", body: "b", companyID: id, status: "open", options: [.option("Yes"), .option("No")])
            s.addMessage(from: "Bank", title: "Overdraft limit exceeded", body: "b", tone: "bad")
        }
        e.endSlice(mark)
        e.releaseDay(e.state.day)
        XCTAssertTrue(e.state.inbox.contains { $0.title == "Today's question" })
        XCTAssertTrue(e.state.inbox.contains { $0.title == "Overdraft limit exceeded" })
    }

    func testOneDecisionPopsUpAtATimeAndLaterMovesItToTheInbox() throws {
        var (e, id) = try cafe()
        var first = 0, second = 0
        e.update { s, _, _ in
            first = s.addMessage(kind: "ask", from: "Cafe", title: "One", body: "b", companyID: id, status: "open", options: [.option("Yes")])
            second = s.addMessage(kind: "ask", from: "Cafe", title: "Two", body: "b", companyID: id, status: "open", options: [.option("Yes")])
        }
        XCTAssertEqual(Array(e.popupDecisions.map { $0.id }.prefix(2)), [first, second], "oldest first")
        XCTAssertTrue(e.suggestions(limit: 20).contains { $0.action == .openMessage(first) })
        e.deferDecision(messageID: first)
        XCTAssertFalse(e.popupDecisions.contains { $0.id == first })
        let m = try XCTUnwrap(e.state.inbox.first { $0.id == first })
        XCTAssertEqual(e.decisionChannel(m), .inbox)
        XCTAssertFalse(e.suggestions(limit: 20).contains { $0.action == .openMessage(first) }, "Home no longer shows it")
        XCTAssertEqual(m.status, "open", "it can still be answered from the inbox")
        XCTAssertEqual(e.popupDecisions.first?.id, second)
    }

    func testTheWeeklyPlanLivesOnTheDeskWhileTheDeskIsOpen() throws {
        var (e, id) = try cafe()
        var plan = 0
        e.update { s, _, _ in plan = s.addMessage(kind: "ask", from: "Weekly plan", title: "Plan", body: "b", companyID: id, status: "open", options: [.option("Push sales")], action: WeeklyFocus.action) }
        XCTAssertTrue(e.popupDecisions.contains { $0.id == plan }, "no Desk yet: it pops up on Home")
        UnlocksTests.level(&e, FeatureUnlocks.unlockLevel(.desk))
        XCTAssertFalse(e.popupDecisions.contains { $0.id == plan })
        XCTAssertEqual(e.decisionChannel(try XCTUnwrap(e.state.inbox.first { $0.id == plan })), .desk)
    }

    func testAnAlertPopsUpOnceAndStaysAsAMessage() throws {
        var (e, _) = try cafe()
        var id = 0
        e.update { s, _, _ in id = s.addMessage(from: "Bank", title: "Final warning: forced sale in 3 weeks", body: "b", tone: "bad") }
        XCTAssertEqual(e.popupAlerts.map { $0.id }, [id])
        e.markAlertShown(messageID: id)
        XCTAssertTrue(e.popupAlerts.isEmpty)
        XCTAssertTrue(e.state.inbox.contains { $0.id == id })
    }

    func testAQuietDayGetsOneLightEventAndABusyDayNone() throws {
        var (e, id) = try cafe()
        let lib = e.events
        var fired: String?
        e.update { s, d, c in
            s.rest.removeValue(forKey: "feedD")
            s.inbox.removeAll { $0.status == "open" }
            fired = DailyBeat.ensure(&s, fresh: [], library: lib, data: d, context: c)
        }
        let ev = try XCTUnwrap(fired, "a starter cafe has light events to draw on")
        let event = try XCTUnwrap(lib[ev] ?? EventPack.byID[ev]?.event)
        XCTAssertNotEqual(event.tone, "bad")
        XCTAssertTrue(!event.options.isEmpty || !DailyBeat.hasEffects(event.automaticEffects), "a filler never hands out money or customers for nothing")
        XCTAssertTrue(e.state.inbox.contains { $0.flag(DailyBeat.fillerKey) }, "the filler's message is marked")
        XCTAssertTrue(e.state.inbox.contains { $0.companyID == id } || !e.state.feedToday().isEmpty, "the player sees something")
        let busy = Message(raw: ["title": .string("News"), "status": .string("done")])
        e.update { s, d, c in XCTAssertNil(DailyBeat.ensure(&s, fresh: [busy], library: lib, data: d, context: c)) }
    }

    func testFillerNeverRepeatsWithinAFewWeeksAndIsNeverBadNews() throws {
        var (e, _) = try cafe()
        let lib = e.events
        var seen: [String: Int] = [:]
        for day in 0..<(DailyBeat.repeatWeeks * 7) {
            e.update { s, d, c in
                s.week = 20 + day / 7
                s.day = day % 7
                s.rest.removeValue(forKey: "feedD")
                s.inbox.removeAll { $0.status == "open" }
                guard let id = DailyBeat.ensure(&s, fresh: [], library: lib, data: d, context: c) else { return }
                if let w = seen[id] { XCTFail("\(id) came back after \(s.week - w) weeks") }
                seen[id] = s.week
                XCTAssertNotEqual((lib[id] ?? EventPack.byID[id]?.event)?.tone, "bad", id)
            }
        }
        XCTAssertGreaterThan(seen.count, 1)
    }

    func testNoFillerWithoutTheLadder() throws {
        var (e, _) = try cafe()
        let lib = e.events
        e.update { s, d, c in
            s.rest["ldr"] = nil
            s.rest.removeValue(forKey: "feedD")
            XCTAssertNil(DailyBeat.ensure(&s, fresh: [], library: lib, data: d, context: c))
        }
    }
}
