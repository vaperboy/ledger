import XCTest
@testable import Events
@testable import Businesses
import GameCore
import Countries
import Finance
import Simulation

final class EventNoticeTests: XCTestCase {
    private static let ownCode: Set<String> = ["g_review", "v_critic", "g_award", "g_audit", "g_inspect", "v_health", "v_bigwin", "c_market", "d_market",
                                               "g_lawsuit", "f_storm", "f_run", "f_default", "e_price", "e_geo"]

    private func engineWithCompany() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        for _ in 0..<(3 * 7) { e.nextDay() }
        var extra = 0
        while e.state.company(id)?.status != .open && extra < 14 { e.nextDay(); extra += 1 }
        return (e, id)
    }

    private func fire(_ base: GameEngine, _ id: Int, _ ev: GameEvent) -> [Message] {
        var e = base
        var fresh: [Message] = []
        e.update { s, data, ctx in
            let top: Int = s.inbox.map { $0.id }.max() ?? 0
            guard let i = s.companyIndex(id) else { return }
            let c = EventEngine.context(for: s.companies[i], data: data, country: World(state: s, data: data).country(s.companies[i]))
            EventEngine.fire(&s, companyIndex: i, ev, ctx: c, data: data, context: ctx)
            fresh = s.inbox.filter { $0.id > top }
        }
        return fresh
    }

    func testEveryOrdinaryEventLeavesAClearNotice() throws {
        let (base, id) = try engineWithCompany()
        let lib = base.events
        var problems: [String] = []
        var fired = 0
        for ev in lib.events.values.sorted(by: { $0.id < $1.id }) where !ev.text.isEmpty && !lib.special.contains(ev.id) && !Self.ownCode.contains(ev.id) {
            let fresh: [Message] = fire(base, id, ev)
            fired += 1
            if fresh.isEmpty { problems.append("\(ev.id): no notice"); continue }
            for m in fresh {
                if m.title.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("\(ev.id): empty title") }
                if m.body.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("\(ev.id): empty body") }
                if m.title.contains("{") || m.body.contains("{") { problems.append("\(ev.id): unresolved token") }
            }
        }
        XCTAssertGreaterThan(fired, 150)
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "; "))
    }

    func testEveryQuestionIsOpenWithADeadlineOrAnsweredByTheManager() throws {
        let (base, id) = try engineWithCompany()
        let lib = base.events
        var problems: [String] = []
        for ev in lib.events.values.sorted(by: { $0.id < $1.id }) where !ev.options.isEmpty && !ev.text.isEmpty && !lib.special.contains(ev.id) && !Self.ownCode.contains(ev.id) {
            let fresh: [Message] = fire(base, id, ev)
            for m in fresh where m.status == "open" {
                if m.expiresWeek == nil { problems.append("\(ev.id): no deadline") }
                if m.options.count < 2 { problems.append("\(ev.id): fewer than two answers") }
                if !m.body.contains("Answer within") { problems.append("\(ev.id): body does not say when to answer") }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "; "))
    }

    func testAnEventThatCanCostMoneyTellsTheOwnerWhetherInsuranceCoversIt() throws {
        let (base, id) = try engineWithCompany()
        let lib = base.events
        var checked = 0
        for ev in lib.events.values.sorted(by: { $0.id < $1.id }) where ["liab", "prop", "cyber", "prof", "bi"].contains(ev.category) && !ev.options.isEmpty && !ev.text.isEmpty
            && !lib.special.contains(ev.id) && !Self.ownCode.contains(ev.id) {
            for m in fire(base, id, ev) where m.status == "open" && m.body.contains("insurance") {
                checked += 1
                XCTAssertTrue(m.body.contains("no ") || m.body.contains("covers"), ev.id)
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testTheLibraryHasNoPaperworkRequestsAndKeepsDemandTransportAndInsuranceEvents() throws {
        let lib = try EventLibrary.bundled()
        for ev in lib.events.values {
            let words: String = ([ev.text] + ev.options.map { $0.label + " " + $0.detail }).joined(separator: " ").lowercased()
            for banned in ["paperwork", "work permit", "timesheet", "payroll form"] {
                XCTAssertFalse(words.contains(banned), "\(ev.id) mentions \(banned)")
            }
        }
        for id in ["l_fuel", "l_toll", "l_freight", "l_port", "l_hours"] { XCTAssertNotNil(lib[id], id) }
        var shifting = 0
        for ev in lib.events.values where ev.options.contains(where: { (o: GameEvent.Option) -> Bool in !o.effects["dem"].isNull }) { shifting += 1 }
        XCTAssertGreaterThan(shifting, 10)
        for cat in ["prop", "liab", "prof", "cyber", "bi"] {
            XCTAssertFalse(lib.events.values.filter { $0.category == cat }.isEmpty, cat)
        }
        for ev in lib.events.values where !ev.options.isEmpty {
            XCTAssertTrue(["none", "prop", "liab", "prof", "cyber", "bi"].contains(ev.category), ev.id)
            XCTAssertTrue(["good", "bad", "n"].contains(ev.tone), ev.id)
        }
    }

    func testWaitingDecisionsAreCapped() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 3)
        e.update { s, _, _ in
            XCTAssertTrue(EventEngine.decisionRoom(s))
            var added = 0
            while EventEngine.decisionRoom(s) && added < 40 {
                let opts = [JSONValue.option("Take the hit", "", effects: [:]), JSONValue.option("Pay", "", effects: ["cash": .number(-1)])]
                _ = s.addMessage(kind: "decision", from: "Test", title: "Question \(added)", body: "Body", status: "open", options: opts)
                added += 1
            }
            XCTAssertGreaterThanOrEqual(added, 4)
            XCTAssertLessThanOrEqual(added, EventEngine.decisionCap)
            XCTAssertFalse(EventEngine.decisionRoom(s))
            if let k = s.inbox.indices.first { s.inbox[k].set("status", "done") }
            XCTAssertTrue(EventEngine.decisionRoom(s), "answering one makes room for the next")
        }
    }
}
