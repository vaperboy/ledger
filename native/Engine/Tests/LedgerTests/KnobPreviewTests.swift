import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

extension GameEngine {
    /// Write a business option directly, free of any changeover (test set-up only; the app uses `changeKnob`).
    mutating func setKnob(companyID: Int, knob: String, option: Int) {
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            var k = s.companies[i].value("knob"); k[knob] = .number(Double(option)); s.companies[i].set("knob", k)
        }
    }
}

/// The "how you sell" preview is the engine's own demand, price, capacity and cost functions on the company as it is: it must
/// match what the engine then does, change nothing, and promise nothing.
final class KnobPreviewTests: XCTestCase {
    private static let seeds = [3, 11, 29, 57]

    private func open(_ e: inout GameEngine, _ trade: String) -> Int {
        let id = ChainsTests.start(&e, trade)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        ChainsTests.play(&e, days: 7 * 6)
        return id
    }

    /// A single-choice knob whose options need no licence, and the option that differs most from the current one in pull on customers.
    private func target(_ e: GameEngine, _ trade: String, _ id: Int) throws -> (Knob, Int) {
        let co = try XCTUnwrap(e.state.company(id))
        let k = try XCTUnwrap(e.data.catalog[trade]?.knobs.first { !$0.isMulti && $0.options.count >= 3 && $0.options.allSatisfy { $0.requiredDocs.isEmpty } })
        let cur = KnobChange.currentValue(co, k)
        let to = k.options.indices.filter { $0 != cur }.max { abs(log(k.options[$0].effects["d"] ?? 1) + abs(log(k.options[$0].effects["t"] ?? 1))) < abs(log(k.options[$1].effects["d"] ?? 1) + abs(log(k.options[$1].effects["t"] ?? 1))) }!
        return (k, to)
    }

    /// Evaluate the same functions directly on the engine after the choice was really written, week by week ahead.
    private func direct(_ e: GameEngine, _ id: Int) throws -> (demand: [Double], capacity: [Double], price: [Double]) {
        var d: [Double] = [], c: [Double] = [], p: [Double] = []
        for ahead in 0..<KnobChange.previewHorizon {
            var s = e.state; s.week += ahead
            let co = try XCTUnwrap(s.company(id)), bd = try XCTUnwrap(e.data.catalog[co.type])
            let w = World(state: s, data: e.data)
            d.append(DemandModel.compute(co, bd, w).customers); c.append(CapacityModel.compute(co, bd, w).capacity); p.append(Pricing.ticket(co, bd, w))
        }
        return (d, c, p)
    }

    func testThePreviewIsTheEnginesOwnNumbersForTheProposedChoiceAcrossSeedsAndTrades() throws {
        var checked = 0
        defer { XCTAssertGreaterThanOrEqual(checked, 8, "the comparison actually ran for several seeds and trades") }
        for seed in Self.seeds {
            for trade in ["cafe", "barber", "restaurant"] {
                var e = try ChainsTests.engine(seed: seed)
                let id = open(&e, trade)
                guard let (k, to) = try? target(e, trade, id) else { continue }
                checked += 1
                let pv = try XCTUnwrap(e.knobChangePreview(companyID: id, knob: k.id, option: to), "\(trade) seed \(seed)")
                e.setKnob(companyID: id, knob: k.id, option: to)
                let d = try direct(e, id)
                let tag = "\(trade) seed \(seed)"
                XCTAssertEqual(pv.demand.after.low, d.demand.min()!, accuracy: 1e-6 * max(1, d.demand.max()!), tag)
                XCTAssertEqual(pv.demand.after.high, d.demand.max()!, accuracy: 1e-6 * max(1, d.demand.max()!), tag)
                XCTAssertEqual(pv.demand.after.typical, d.demand.reduce(0, +) / 8, accuracy: 1e-6 * max(1, d.demand.max()!), tag)
                XCTAssertEqual(pv.capacity.after.typical, d.capacity.reduce(0, +) / 8, accuracy: 1e-6 * max(1, d.capacity.max()!), tag)
                XCTAssertEqual(pv.price.after.typical, d.price.reduce(0, +) / 8, accuracy: 1e-6 * max(1, d.price.max()!), tag)
            }
        }
    }

    func testThePreviewChangesNothingAndNeverPromises() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let (k, to) = try target(e, "cafe", id)
        let before = try XCTUnwrap(e.state.company(id))
        let pv = try XCTUnwrap(e.knobChangePreview(companyID: id, knob: k.id, option: to))
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).value("knob"), before.value("knob"))
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, before.cash)
        XCTAssertTrue(pv.notes.contains { $0.contains("worse than the low end") }, "the estimate says it is not a guarantee")
        XCTAssertLessThan(pv.revenue.after.low, pv.revenue.after.typical)
        XCTAssertGreaterThan(pv.revenue.after.high, pv.revenue.after.typical)
        XCTAssertNil(e.knobChangePreview(companyID: id, knob: k.id, option: 99))
        XCTAssertNil(e.knobChangePreview(companyID: id, knob: "nope", option: 0))
    }

    func testTheCurrentChoiceAgainstItselfIsNoChange() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let (k, _) = try target(e, "cafe", id)
        let cur = KnobChange.currentValue(try XCTUnwrap(e.state.company(id)), k)
        let pv = try XCTUnwrap(e.knobChangePreview(companyID: id, knob: k.id, option: cur))
        XCTAssertEqual(pv.revenue.change, 0, accuracy: 1e-9)
        XCTAssertEqual(pv.demand.change, 0, accuracy: 1e-9)
        XCTAssertTrue(pv.revenue.uncertain)
    }

    func testWhatTheShopThenSellsFallsInsideThePreviewedRangeAcrossSeeds() throws {
        // After the changeover weeks, real weekly sales (with all the engine's other dynamics: awareness, reputation, luck) stay
        // within 35% of the previewed range. A stated tolerance, not a target.
        let tolerance = 0.35
        for seed in Self.seeds {
            var e = try ChainsTests.engine(seed: seed)
            let id = open(&e, "cafe")
            let (k, to) = try target(e, "cafe", id)
            let pv = try XCTUnwrap(e.knobChangePreview(companyID: id, knob: k.id, option: to))
            guard case .done(let q) = e.changeKnob(companyID: id, knob: k.id, option: to) else { return XCTFail("refused") }
            ChainsTests.play(&e, days: 7 * q.transitionWeeks)
            var revenue: [Double] = []
            for _ in 0..<KnobChange.previewHorizon {
                ChainsTests.play(&e, days: 7)
                revenue.append(try XCTUnwrap(e.state.company(id)).value("lastW")["rev"].double)
            }
            let mean = revenue.reduce(0, +) / Double(revenue.count)
            XCTAssertGreaterThan(mean, pv.revenue.after.low * (1 - tolerance), "seed \(seed): \(mean) vs \(pv.revenue.after)")
            XCTAssertLessThan(mean, pv.revenue.after.high * (1 + tolerance), "seed \(seed): \(mean) vs \(pv.revenue.after)")
        }
    }

    func testALicenceOptionIsPreviewedAsIfApprovedAndSaysSo() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let k = try XCTUnwrap(e.data.catalog["cafe"]?.knobs.first { $0.id == "alc" })
        let pv = try XCTUnwrap(e.knobTogglePreview(companyID: id, knob: k.id, option: 0, on: true))
        XCTAssertFalse(pv.waitingForLicence.isEmpty)
        XCTAssertTrue(pv.notes.contains { $0.contains("licence") })
    }

    func testTradesWithoutAnOrdinaryWeeklySalesModelGetNoPreview() throws {
        var e = try ChainsTests.engine()
        let trade = try XCTUnwrap(e.data.catalog.trades.values.first { RentalFinance.handles($0) && !$0.knobs.isEmpty })
        let id = open(&e, trade.id)
        let k = trade.knobs[0]
        XCTAssertNil(e.knobChangePreview(companyID: id, knob: k.id, option: (KnobChange.currentValue(try XCTUnwrap(e.state.company(id)), k) + 1) % max(1, k.options.count)))
    }
}
