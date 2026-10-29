import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Multi-choice "how you sell" knobs are bit masks: several add-ons can be on at once.
final class KnobMultiTests: XCTestCase {
    func testSeveralAddOnsRunTogetherAndSwitchOffIndependently() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "barber")
        let bd = try XCTUnwrap(e.data.catalog["barber"])
        let k = try XCTUnwrap(bd.knobs.first { $0.isMulti })
        XCTAssertGreaterThanOrEqual(k.options.count, 3)
        XCTAssertEqual(e.toggleKnobOption(companyID: id, knob: k.id, option: 0, on: true), .done)
        XCTAssertEqual(e.toggleKnobOption(companyID: id, knob: k.id, option: 2, on: true), .done)
        var co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(Knobs.activeOptions(co, k).map { $0.id }, [k.options[0].id, k.options[2].id])
        XCTAssertEqual(e.toggleKnobOption(companyID: id, knob: k.id, option: 0, on: false), .done)
        co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(Knobs.activeOptions(co, k).map { $0.id }, [k.options[2].id])
        // switching on twice does not change anything
        e.toggleKnobOption(companyID: id, knob: k.id, option: 2, on: true)
        XCTAssertEqual(Knobs.activeOptions(try XCTUnwrap(e.state.company(id)), k).count, 1)
    }

    func testRefusesSingleChoiceKnobsAndBadOptions() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let single = try XCTUnwrap(e.data.catalog["cafe"]?.knobs.first { !$0.isMulti })
        if case .refused = e.toggleKnobOption(companyID: id, knob: single.id, option: 1, on: true) {} else { XCTFail("single-choice knob must use setKnob") }
        if case .refused = e.toggleKnobOption(companyID: id, knob: "nope", option: 0, on: true) {} else { XCTFail("unknown knob") }
        let bid = ChainsTests.start(&e, "barber")
        let k = try XCTUnwrap(e.data.catalog["barber"]?.knobs.first { $0.isMulti })
        if case .refused = e.toggleKnobOption(companyID: bid, knob: k.id, option: 99, on: true) {} else { XCTFail("bad option") }
    }

    func testChainRuleMaskStillAppliesSeveralAddOns() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "barber")
        ChainsTests.season(&e, id)
        let k = try XCTUnwrap(e.data.catalog["barber"]?.knobs.first { $0.isMulti })
        var chainID = 0
        e.update { s, _, _ in chainID = Chains.make(&s, companyID: id, name: "Crew") ?? 0 }
        XCTAssertNotEqual(chainID, 0)
        e.setChainRule(chainID: chainID, rule: .knob(id: k.id, option: 0b101))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.value("knob")[k.id].int, 0b101)
        XCTAssertEqual(Knobs.activeOptions(co, k).map { $0.id }, [k.options[0].id, k.options[2].id])
    }

    func testMaskHelper() {
        XCTAssertEqual(Knobs.mask(0, option: 1, on: true), 2)
        XCTAssertEqual(Knobs.mask(7, option: 1, on: false), 5)
        XCTAssertEqual(Knobs.mask(5, option: -1, on: true), 5)
    }
}
