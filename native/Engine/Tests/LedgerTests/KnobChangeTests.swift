import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// How you sell: changing a method costs a changeover, a few weeks of reduced capacity and the licences it needs; nothing
/// is promised; chain standards and franchise agreements lock the choice; a chain-wide change is quoted per store first.
final class KnobChangeTests: XCTestCase {
    /// An open company of `trade` with plenty of cash.
    private func open(_ e: inout GameEngine, _ trade: String) -> Int {
        let id = ChainsTests.start(&e, trade)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return id
    }

    /// A single-choice knob and two different options of it.
    private func singleKnob(_ e: GameEngine, _ trade: String) throws -> (Knob, Int, Int) {
        let k = try XCTUnwrap(e.data.catalog[trade]?.knobs.first { !$0.isMulti && $0.options.count >= 3 && $0.options.allSatisfy { $0.requiredDocs.isEmpty } })
        return (k, k.defaultIndex, (k.defaultIndex + 1) % k.options.count)
    }

    func testAChangeoverCostsMoneyBooksItAndReducesCapacityForAFewWeeks() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let (k, from, to) = try singleKnob(e, "cafe")
        e.update { s, _, _ in if let i = s.companyIndex(id) { var kn = s.companies[i].value("knob"); kn[k.id] = .number(Double(from)); s.companies[i].set("knob", kn) } }
        let q = try XCTUnwrap(e.knobChangeQuote(companyID: id, knob: k.id, option: to))
        XCTAssertNil(q.blocked)
        XCTAssertGreaterThan(q.changeoverCost, 0)
        XCTAssertTrue((1...4).contains(q.transitionWeeks))
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        guard case .done(let done) = e.changeKnob(companyID: id, knob: k.id, option: to) else { return XCTFail("refused") }
        XCTAssertEqual(done, q, "what was quoted is what is charged")
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(cash0 - co.cash, q.totalCost, accuracy: 1)
        XCTAssertEqual(co.value("knob")[k.id].int, to)
        XCTAssertTrue(co.value("mods").array.contains { $0["k"].string == "cap" && $0["m"].double == 0.75 })
        XCTAssertEqual(co.value("hys56c")["n"].int, q.transitionWeeks)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // the reduced capacity ends by itself
        ChainsTests.play(&e, days: 7 * (q.transitionWeeks + 2))
        XCTAssertFalse(try XCTUnwrap(e.state.company(id)).value("mods").array.contains { $0["k"].string == "cap" && $0["m"].double == 0.75 })
    }

    func testNotEnoughCashRefusesAndChangesNothing() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let (k, from, to) = try singleKnob(e, "cafe")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var kn = s.companies[i].value("knob"); kn[k.id] = .number(Double(from)); s.companies[i].set("knob", kn)
            Payments.companyPays(&s, companyID: id, amount: max(0, s.companies[i].cash - 10), category: nil)
        }
        let before = try XCTUnwrap(e.state.company(id))
        guard case .refused(let why) = e.changeKnob(companyID: id, knob: k.id, option: to) else { return XCTFail("should be refused") }
        XCTAssertTrue(why.contains("Not enough cash"), why)
        let after = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(after.cash, before.cash)
        XCTAssertEqual(after.value("knob"), before.value("knob"))
        XCTAssertTrue(after.value("mods").array.isEmpty)
        XCTAssertTrue(after.value("hys56c").isNull)
    }

    func testChangingTheSameThingTwiceInTheTransitionIsRefusedAndAnUnchangedChoiceCostsNothing() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let (k, from, to) = try singleKnob(e, "cafe")
        e.update { s, _, _ in if let i = s.companyIndex(id) { var kn = s.companies[i].value("knob"); kn[k.id] = .number(Double(from)); s.companies[i].set("knob", kn) } }
        if case .refused = e.changeKnob(companyID: id, knob: k.id, option: from) {} else { XCTFail("same choice") }
        guard case .done = e.changeKnob(companyID: id, knob: k.id, option: to) else { return XCTFail() }
        let cash = try XCTUnwrap(e.state.company(id)).cash
        if case .refused = e.changeKnob(companyID: id, knob: k.id, option: from) {} else { XCTFail("flip-flopping during the changeover") }
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, cash, "a refusal costs nothing")
    }

    func testAnOptionThatNeedsALicenceAppliesForItAndPaysTheFee() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let k = try XCTUnwrap(e.data.catalog["cafe"]?.knobs.first { $0.id == "alc" })
        let q = try XCTUnwrap(e.knobToggleQuote(companyID: id, knob: k.id, option: 0, on: true))
        XCTAssertFalse(q.documents.isEmpty, "the alcohol option needs a licence the cafe does not hold")
        XCTAssertEqual(q.totalCost, q.documentFees)
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertEqual(e.toggleKnobOption(companyID: id, knob: k.id, option: 0, on: true), .done)
        let co = try XCTUnwrap(e.state.company(id))
        for d in q.documents { XCTAssertEqual(co.value("docs")[d.id]["st"].string, "applied", d.id) }
        XCTAssertEqual(cash0 - co.cash, q.totalCost, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAddOnsAreFreeToSwitchButNotWhileTheChainFixesThem() throws {
        var e = try ChainsTests.engine()
        let first = open(&e, "barber")
        ChainsTests.season(&e, first)
        e.update { s, _, _ in if let i = s.companyIndex(first) { s.companies[i].set("mgr", 0) } }
        let k = try XCTUnwrap(e.data.catalog["barber"]?.knobs.first { $0.isMulti })
        let cash = try XCTUnwrap(e.state.company(first)).cash
        XCTAssertEqual(e.toggleKnobOption(companyID: first, knob: k.id, option: 1, on: true), .done)
        XCTAssertEqual(try XCTUnwrap(e.state.company(first)).cash, cash, "an add-on without a licence costs nothing")
        let chain = try XCTUnwrap(e.makeChain(companyID: first, name: "Crew"))
        XCTAssertNotNil(e.knobGovernedBy(companyID: first, knob: k.id), "joining a chain makes its rules the standard")
        if case .refused(let why) = e.toggleKnobOption(companyID: first, knob: k.id, option: 0, on: true) { XCTAssertTrue(why.contains("Crew"), why) } else { XCTFail("chain standard") }
        e.releaseChainKnob(chainID: chain, knob: k.id)
        XCTAssertNil(e.knobGovernedBy(companyID: first, knob: k.id))
        XCTAssertEqual(e.toggleKnobOption(companyID: first, knob: k.id, option: 0, on: true), .done)
    }

    func testAChainWideChangeIsQuotedPerStoreThenAppliedWithExceptionsReported() throws {
        var e = try ChainsTests.engine()
        let first = open(&e, "cafe")
        ChainsTests.season(&e, first)
        e.update { s, _, _ in if let i = s.companyIndex(first) { s.companies[i].set("mgr", 0) } }
        let chain = try XCTUnwrap(e.makeChain(companyID: first, name: "Beans"))
        guard case .success(let second) = e.openChainStore(chainID: chain, cityID: e.state.player.cityID, size: 1) else { return XCTFail("store") }
        e.update { s, _, _ in if let i = s.companyIndex(second) { s.companies[i].status = .open } }
        let (k, from, to) = try singleKnob(e, "cafe")
        e.releaseChainKnob(chainID: chain, knob: k.id)
        e.update { s, _, _ in
            for id in [first, second] { if let i = s.companyIndex(id) { var kn = s.companies[i].value("knob"); kn[k.id] = .number(Double(from)); s.companies[i].set("knob", kn) } }
            // the second store cannot pay
            if let i = s.companyIndex(second) { Payments.companyPays(&s, companyID: second, amount: max(0, s.companies[i].cash - 10), category: nil) }
        }
        let plan = try XCTUnwrap(e.chainKnobPlan(chainID: chain, knob: k.id, value: to))
        XCTAssertEqual(plan.lines.count, 2)
        let firstQuote = try XCTUnwrap(e.knobChangeQuote(companyID: first, knob: k.id, option: to))
        XCTAssertEqual(plan.totalCost, firstQuote.totalCost, accuracy: 1, "only the store that can change is charged")
        XCTAssertEqual(plan.exceptions, 1)
        let cash0 = try XCTUnwrap(e.state.company(first)).cash, cash1 = try XCTUnwrap(e.state.company(second)).cash
        let done = e.setChainKnob(chainID: chain, knob: k.id, value: to)
        XCTAssertEqual(done.exceptions, 1)
        XCTAssertEqual(try XCTUnwrap(e.state.company(first)).value("knob")[k.id].int, to)
        XCTAssertEqual(try XCTUnwrap(e.state.company(second)).value("knob")[k.id].int, from, "the store that could not change keeps its choice")
        XCTAssertEqual(try XCTUnwrap(e.state.company(second)).cash, cash1)
        XCTAssertEqual(cash0 - (try XCTUnwrap(e.state.company(first)).cash), firstQuote.totalCost, accuracy: 1)
        // the weekly chain turn does not quietly override the exception or charge anything more
        ChainsTests.play(&e, days: 14)
        XCTAssertEqual(try XCTUnwrap(e.state.company(second)).value("knob")[k.id].int, from)
        XCTAssertNotNil(e.knobGovernedBy(companyID: first, knob: k.id))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testAFranchiseAgreementThatFixesAChoiceLocksItAndNoAgreementLeavesItFree() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let (k, _, to) = try singleKnob(e, "cafe")
        XCTAssertNil(e.knobGovernedBy(companyID: id, knob: k.id), "an independent decides")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].set("franchise", .object(["fran": 1, "brandName": "Brand", "knobStd": .object([k.id: .number(0)])])) } }
        XCTAssertNotNil(e.knobGovernedBy(companyID: id, knob: k.id))
        if case .refused = e.changeKnob(companyID: id, knob: k.id, option: to) {} else { XCTFail("franchise standard") }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].set("franchise", .object(["fran": 1, "brandName": "Brand"])) } }
        XCTAssertNil(e.knobGovernedBy(companyID: id, knob: k.id), "an agreement without standards leaves the choice to the franchisee")
    }

    func testABusinessNotYetOpenChangesFreeAndOldSavesWithoutTheRecordLoad() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .setup } }
        let (k, _, to) = try singleKnob(e, "cafe")
        let cash = try XCTUnwrap(e.state.company(id)).cash
        guard case .done(let q) = e.changeKnob(companyID: id, knob: k.id, option: to) else { return XCTFail() }
        XCTAssertEqual(q.totalCost, 0)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, cash)
        XCTAssertTrue(try XCTUnwrap(e.state.company(id)).value("hys56c").isNull)
    }
}
