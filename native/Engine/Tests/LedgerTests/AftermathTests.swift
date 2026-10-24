import XCTest
@testable import Events
@testable import Businesses
import GameCore
import Countries
import Finance
import Simulation

/// Event chains: a lost lawsuit, a patched machine, a resignation, a failed supplier, a cyber attack and a failed inspection
/// each queue a follow-up that arrives later as an Inbox decision, changes real state, fires once and is written to the report.
final class AftermathTests: XCTestCase {
    func engineWithCompany(trade: String = "cafe", weeks: Int = 3) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    func kinds(_ s: GameState, _ id: Int) -> Set<String> { Set(AftermathQueue.pending(s, companyID: id).map { $0.kind }) }
    func ev(_ id: String) -> GameEvent { GameEvent(id: id, json: .object([:])) }
    func apply(_ s: inout GameState, _ id: Int, event: String, fx: JSONValue, data: GameData, ctx: FinanceContext) {
        let i = s.companyIndex(id)!
        let c = EventEngine.context(for: s.companies[i], data: data, employerFactor: 1)
        EventEngine.apply(&s, companyIndex: i, fx, ctx: c, event: ev(event), data: data, context: ctx)
    }
    /// Move the clock until everything queued is due, then fire it.
    func fireDue(_ s: inout GameState, data: GameData, ctx: FinanceContext) {
        s.week += 20
        Aftermath.weekly(&s, data: data, context: ctx)
    }
    func openAft(_ s: GameState, _ id: Int, _ kind: String) -> Message? {
        s.inbox.first { $0.companyID == id && $0.status == "open" && $0.str("ev") == "aft_" + kind }
    }
    func hasMod(_ s: GameState, _ id: Int, _ key: String) -> Bool { s.company(id)!.value("mods").array.contains { $0["k"].string == key } }

    func testEveryFollowUpHasThreeCostedOptionsAndKeepsTheBooksBalanced() throws {
        let (base, id) = try engineWithCompany()
        XCTAssertEqual(Aftermath.templates.count, 11)   // the twelfth chain, the copycat lawsuit, reuses `Lawsuits.begin`
        for kind in Aftermath.templates.keys.sorted() {
            let template = try XCTUnwrap(Aftermath.event(kind), kind)
            XCTAssertEqual(template.options.count, 3, kind)
            XCTAssertTrue(template.options.allSatisfy { !$0.detail.isEmpty }, "\(kind): every option explains cost, benefit and risk")
            for n in 0..<template.options.count {
                var e = base
                var asked: Message? = nil
                e.update { s, data, ctx in
                    let i = s.companyIndex(id)!
                    let c = EventEngine.context(for: s.companies[i], data: data, employerFactor: 1)
                    EventEngine.fire(&s, companyIndex: i, template, ctx: c, data: data, context: ctx)
                    asked = s.inbox.first { $0.status == "open" && $0.str("ev") == "aft_" + kind }
                }
                let m = try XCTUnwrap(asked, kind)
                XCTAssertNotNil(m.expiresWeek, "\(kind) has a deadline")
                XCTAssertTrue(e.answer(messageID: m.id, option: n), "\(kind) option \(n)")
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(kind) option \(n): \(Ledger.gaps(e.state))")
            }
        }
    }

    func testLostLawsuitHurtsReviewsThenRepricesInsuranceAndInvitesCopycats() throws {
        var (e, id) = try engineWithCompany()
        let repBefore = e.state.company(id)!.reputation
        e.update { s, data, ctx in
            Lawsuits.lose(&s, id, .object(["claim": 20000, "who": "A. Client", "big": true]), data: data)
            XCTAssertLessThan(s.company(id)!.reputation, repBefore)
            XCTAssertTrue(hasMod(s, id, "dem"), "reviews dip")
            XCTAssertEqual(kinds(s, id), ["premium", "copycat"])
            // Losing a second time while one is queued does not stack follow-ups.
            Lawsuits.lose(&s, id, .object(["claim": 1000, "who": "B", "big": true]), data: data)
            XCTAssertEqual(AftermathQueue.pending(s, companyID: id).count, 2)
            XCTAssertTrue((s.rest["rep"]?["ev"].array ?? []).contains { $0["co"].int == id && $0["t"].string.contains("press") }, "the report mentions it")

            fireDue(&s, data: data, ctx: ctx)
            XCTAssertTrue(AftermathQueue.pending(s, companyID: id).isEmpty, "processed once")
            XCTAssertNotNil(openAft(s, id, "premium"))
            XCTAssertTrue(s.inbox.contains { $0.companyID == id && $0.actionID == "sue16" && $0.status == "open" }, "a new claim arrives")
            // Cooldown: the same chain cannot be queued again straight away.
            XCTAssertFalse(AftermathQueue.schedule(&s, companyID: id, kind: "premium", delay: 1))
        }
        let m = try XCTUnwrap(e.state.inbox.first { $0.str("ev") == "aft_premium" })
        XCTAssertTrue(e.answer(messageID: m.id, option: 1))
        let flags = e.state.company(id)!.value("flags")
        XCTAssertEqual(flags["premUp"].double, 0.08, accuracy: 1e-9)
        XCTAssertGreaterThan(flags["premUntil"].double, Double(e.state.week))
    }

    func testPatchedMachineRelapsesAndIgnoringItCostsCustomers() throws {
        var (e, id) = try engineWithCompany()
        e.update { s, data, ctx in
            apply(&s, id, event: "g_break", fx: .object(["fixeq": 1, "cap": .array([0.78, 2])]), data: data, ctx: ctx)
            XCTAssertEqual(kinds(s, id), ["relapse"])
            fireDue(&s, data: data, ctx: ctx)
            XCTAssertNotNil(openAft(s, id, "relapse"))
            let repBefore = s.company(id)!.reputation
            // Ignored: the cheapest answer is to keep running it.
            s.week += 5
            EventEngine.expire(&s, data: data, context: ctx)
            XCTAssertNil(openAft(s, id, "relapse"))
            XCTAssertLessThan(s.company(id)!.reputation, repBefore)
            XCTAssertTrue(hasMod(s, id, "dem") && hasMod(s, id, "cap"))
            XCTAssertTrue((s.rest["rep"]?["ev"].array ?? []).contains { $0["co"].int == id && $0["t"].string.contains("No answer in time") })
        }
    }

    func testResignationDropsCapacityThenOffersCoverAndAHeadhuntingCounterOffer() throws {
        var (e, id) = try engineWithCompany()
        e.update { s, data, ctx in
            apply(&s, id, event: "g_quit", fx: .object(["quit": 1]), data: data, ctx: ctx)
            XCTAssertTrue(hasMod(s, id, "cap"), "capacity drops at once")
            XCTAssertEqual(kinds(s, id), ["hire", "headhunt"])
            fireDue(&s, data: data, ctx: ctx)
            XCTAssertNotNil(openAft(s, id, "hire"))
            if !s.company(id)!.staff.isEmpty {
                let m = openAft(s, id, "headhunt")
                XCTAssertNotNil(m)
                XCTAssertEqual(m?.options.count, 3)
            }
        }
    }

    func testSupplierFailureLeadsToAShortageAndLaterATermsNegotiation() throws {
        var (e, id) = try engineWithCompany()
        e.update { s, data, ctx in
            apply(&s, id, event: "g_supbust", fx: .object(["cap": .array([0.75, 3])]), data: data, ctx: ctx)
            apply(&s, id, event: "g_supbust", fx: .object(["price": .array([1.12, 8])]), data: data, ctx: ctx)
            XCTAssertEqual(kinds(s, id), ["shortage", "negotiate"])
        }
        e.update { s, data, ctx in fireDue(&s, data: data, ctx: ctx) }
        let m = try XCTUnwrap(e.state.inbox.first { $0.str("ev") == "aft_negotiate" && $0.status == "open" })
        let cashBefore = e.state.company(id)!.cash
        XCTAssertTrue(e.answer(messageID: m.id, option: 1))
        XCTAssertLessThan(e.state.company(id)!.cash, cashBefore, "the deposit is paid")
        XCTAssertTrue(hasMod(e.state, id, "price"))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testCyberAttackAndFailedInspectionQueueTheirFollowUps() throws {
        var (e, id) = try engineWithCompany()
        e.update { s, data, _ in
            Cyber.hit(&s, companyID: id, kind: "leak", data: data)
            XCTAssertTrue(kinds(s, id).contains("secreview"))
        }
        e.update { s, data, ctx in
            fireDue(&s, data: data, ctx: ctx)
            XCTAssertNotNil(openAft(s, id, "secreview"))
        }
        let m = try XCTUnwrap(e.state.inbox.first { $0.str("ev") == "aft_secreview" && $0.status == "open" })
        XCTAssertTrue(e.answer(messageID: m.id, option: 2))
        let cy = e.state.company(id)!.value("cy56")
        XCTAssertGreaterThanOrEqual(cy["lvl"].int, 2)
        XCTAssertEqual(cy["tr"].int, e.state.week)
        e.update { s, _, _ in
            XCTAssertTrue(AftermathQueue.schedule(&s, companyID: id, kind: "reinspect", delay: 4))
            XCTAssertFalse(AftermathQueue.schedule(&s, companyID: id, kind: "reinspect", delay: 4), "queued once")
        }
    }

    func testOpportunitiesComeAfterRivalsOrdersAndRoadworks() throws {
        var (e, id) = try engineWithCompany()
        e.update { s, data, ctx in
            apply(&s, id, event: "g_rival", fx: .object([:]), data: data, ctx: ctx)
            apply(&s, id, event: "g_offer", fx: .object(["dem": .array([1.4, 5])]), data: data, ctx: ctx)
            apply(&s, id, event: "g_roadwork", fx: .object([:]), data: data, ctx: ctx)
            XCTAssertEqual(kinds(s, id), ["distressed", "bulk", "premises"])
            fireDue(&s, data: data, ctx: ctx)
            for k in ["distressed", "bulk", "premises"] { XCTAssertNotNil(openAft(s, id, k), k) }
        }
        let m = try XCTUnwrap(e.state.inbox.first { $0.str("ev") == "aft_distressed" && $0.status == "open" })
        let cash = e.state.company(id)!.cash
        XCTAssertTrue(e.answer(messageID: m.id, option: 2))
        XCTAssertLessThan(e.state.company(id)!.cash, cash)
        XCTAssertTrue(hasMod(e.state, id, "dem"))
    }
}
