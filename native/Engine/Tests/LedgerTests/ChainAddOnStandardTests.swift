import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Chain standards for add-ons (the bit-mask knobs): the whole set of add-ons is the standard; stores that cannot follow are listed.
final class ChainAddOnStandardTests: XCTestCase {
    func testAChainCanFixTheSetOfAddOnsAndStoreExceptionsAreListedAcrossSeeds() throws {
        for seed in [3, 11, 29] {
            var e = try ChainsTests.engine(seed: seed)
            let first = ChainsTests.start(&e, "cafe")
            e.update { s, _, _ in if let i = s.companyIndex(first) { s.companies[i].status = .open } }
            ChainsTests.season(&e, first)
            e.update { s, _, _ in if let i = s.companyIndex(first) { s.companies[i].set("mgr", 0) } }
            let chain = try XCTUnwrap(e.makeChain(companyID: first, name: "Crew"))
            guard case .success(let second) = e.openChainStore(chainID: chain, cityID: e.state.player.cityID, size: 1) else { return XCTFail("store") }
            e.update { s, _, _ in if let i = s.companyIndex(second) { s.companies[i].status = .open } }
            let k = try XCTUnwrap(e.data.catalog["cafe"]?.knobs.first { $0.isMulti })
            e.releaseChainKnob(chainID: chain, knob: k.id)
            XCTAssertNil(e.chainKnobStandard(chainID: chain, knob: k.id))
            XCTAssertTrue(e.chainKnobExceptions(chainID: chain, knob: k.id).isEmpty)
            let mask = (1 << 1) | (1 << 2)
            XCTAssertNotNil(e.chainKnobPlan(chainID: chain, knob: k.id, value: mask))
            e.setChainKnob(chainID: chain, knob: k.id, value: mask)
            XCTAssertEqual(e.chainKnobStandard(chainID: chain, knob: k.id), mask)
            for id in [first, second] { XCTAssertEqual(try XCTUnwrap(e.state.company(id)).value("knob")[k.id].int, mask, "seed \(seed)") }
            XCTAssertTrue(e.chainKnobExceptions(chainID: chain, knob: k.id).isEmpty, "everyone follows")
            // the standard locks the add-ons
            XCTAssertNotNil(e.knobGovernedBy(companyID: first, knob: k.id))
            if case .refused = e.toggleKnobOption(companyID: first, knob: k.id, option: 0, on: true) {} else { XCTFail("fixed by the chain") }
            // a store that is still changing over, or otherwise cannot follow a new set, is listed and keeps what it has
            let other = (1 << 0)
            e.update { s, _, _ in
                if let i = s.companyIndex(second) { Payments.companyPays(&s, companyID: second, amount: max(0, s.companies[i].cash - 1), category: nil) }
                // documents for add-ons cost money; a store with no cash cannot apply, but a free add-on still switches. Force a difference.
                if let i = s.companyIndex(second) { var kn = s.companies[i].value("knob"); kn[k.id] = .number(Double(mask)); s.companies[i].set("knob", kn) }
            }
            let done = e.setChainKnob(chainID: chain, knob: k.id, value: other)
            XCTAssertEqual(e.chainKnobStandard(chainID: chain, knob: k.id), other)
            let listed = Set(e.chainKnobExceptions(chainID: chain, knob: k.id).map { $0.storeID })
            let actual = Set([first, second].filter { try! XCTUnwrap(e.state.company($0)).value("knob")[k.id].int != other })
            XCTAssertEqual(listed, actual, "exceptions are exactly the stores that differ (seed \(seed))")
            XCTAssertEqual(done.exceptions, listed.count)
            XCTAssertEqual(listed, [second], "the store without cash cannot pay for the alcohol licence and keeps its add-ons")
            ChainsTests.play(&e, days: 14)
            XCTAssertEqual(Set(e.chainKnobExceptions(chainID: chain, knob: k.id).map { $0.storeID }), listed, "the weekly turn does not silently override or fix them")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
            e.releaseChainKnob(chainID: chain, knob: k.id)
            XCTAssertNil(e.chainKnobStandard(chainID: chain, knob: k.id))
        }
    }
}
