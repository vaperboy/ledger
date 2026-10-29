import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The changeover slowdown lasts exactly the weeks the quote says, and the licence weeks shown are the ones the application takes.
final class KnobTransitionTests: XCTestCase {
    private func open(_ e: inout GameEngine, _ trade: String) -> Int {
        let id = ChainsTests.start(&e, trade)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        ChainsTests.play(&e, days: 7 * 3)
        return id
    }

    /// Run until the week counter moves once.
    private func nextWeek(_ e: inout GameEngine) {
        let w = e.state.week
        while e.state.week == w { ChainsTests.play(&e, days: 1) }
    }

    private func slowdown(_ e: GameEngine, _ id: Int) -> Bool {
        (e.state.company(id)?.value("mods").array ?? []).contains { $0["k"].string == "cap" && $0["m"].double == KnobChange.capacityDuringChangeover }
    }

    private func singleKnob(_ e: GameEngine, _ trade: String) throws -> Knob {
        try XCTUnwrap(e.data.catalog[trade]?.knobs.first { !$0.isMulti && $0.options.count >= 3 && $0.options.allSatisfy { $0.requiredDocs.isEmpty } })
    }

    func testTheSlowdownLastsExactlyTheQuotedWeeksForEveryLengthAndSeed() throws {
        var lengthsSeen = Set<Int>()
        for seed in [3, 11, 29] {
            var e = try ChainsTests.engine(seed: seed)
            let id = open(&e, "cafe")
            let k = try singleKnob(e, "cafe")
            for to in k.options.indices {
                // wait out any earlier changeover of the same knob, then change
                while let c = e.state.company(id)?.value("hys56c"), !c.isNull, Double(e.state.week) < c["end"].double { nextWeek(&e) }
                guard let q = e.knobChangeQuote(companyID: id, knob: k.id, option: to), q.blocked == nil, q.transitionWeeks > 0 else { continue }
                lengthsSeen.insert(q.transitionWeeks)
                guard case .done = e.changeKnob(companyID: id, knob: k.id, option: to) else { return XCTFail("refused") }
                XCTAssertTrue(slowdown(e, id), "on from the moment of the change")
                for week in 1...q.transitionWeeks {
                    nextWeek(&e)
                    XCTAssertTrue(slowdown(e, id), "seed \(seed): still slowed in week \(week) of \(q.transitionWeeks)")
                }
                nextWeek(&e)
                XCTAssertFalse(slowdown(e, id), "seed \(seed): gone in week \(q.transitionWeeks + 1)")
            }
        }
        XCTAssertGreaterThanOrEqual(lengthsSeen.count, 2, "several different lengths were exercised: \(lengthsSeen)")
    }

    func testTheCapacityServedIsReducedOnlyDuringThoseWeeks() throws {
        var e = try ChainsTests.engine(seed: 11)
        let id = open(&e, "cafe")
        let k = try singleKnob(e, "cafe")
        // a change with a known length of 2 or more weeks
        let to = try XCTUnwrap(k.options.indices.first { (e.knobChangeQuote(companyID: id, knob: k.id, option: $0)?.transitionWeeks ?? 0) >= 2 })
        let q = try XCTUnwrap(e.knobChangeQuote(companyID: id, knob: k.id, option: to))
        _ = e.changeKnob(companyID: id, knob: k.id, option: to)
        var caps: [Double] = []
        for _ in 0..<(q.transitionWeeks + 2) { nextWeek(&e); caps.append(e.state.company(id)?.value("lastW")["cap"].double ?? 0) }
        let normal = caps[q.transitionWeeks]
        for week in 0..<q.transitionWeeks { XCTAssertEqual(caps[week] / normal, KnobChange.capacityDuringChangeover, accuracy: 0.03, "week \(week + 1): \(caps)") }
        XCTAssertEqual(caps[q.transitionWeeks + 1] / normal, 1, accuracy: 0.03, "\(caps)")
    }

    func testTheLicenceWeeksShownIncludeTheSlowerPaperworkAbroad() throws {
        var e = try ChainsTests.engine("UK")
        let home = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in s.companies[s.companyIndex(home)!].reputation = 60; s.companies[s.companyIndex(home)!].status = .open }
        let option = try XCTUnwrap(e.abroadOptions(companyID: home).first)
        guard case .success(let id) = e.expandAbroad(companyID: home, countryCode: option.countryCode) else { return XCTFail("no expansion") }
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].status = .open; _ = Payments.injectCash(&s, companyID: id, amount: 5_000_000) }
        let k = try XCTUnwrap(e.data.catalog["cafe"]?.knobs.first { $0.id == "alc" })
        let q = try XCTUnwrap(e.knobToggleQuote(companyID: id, knob: k.id, option: 0, on: true))
        let doc = try XCTUnwrap(q.documents.first)
        let co = try XCTUnwrap(e.state.company(id))
        let def = try XCTUnwrap(Documents.definition(doc.id, country: try XCTUnwrap(e.data.countries[co.countryCode]), tables: e.data.catalog.tables))
        XCTAssertEqual(doc.weeks, Documents.waitWeeks(doc.id, definition: def, company: co, World(state: e.state, data: e.data)))
        XCTAssertNotEqual(doc.weeks, def.weeks, "abroad the wait is not the home-country figure (bureaucracy, no head-office desk): \(doc.weeks) vs \(def.weeks)")
        // what the application then takes is exactly what was shown
        XCTAssertEqual(e.toggleKnobOption(companyID: id, knob: k.id, option: 0, on: true), .done)
        let rec = try XCTUnwrap(e.state.company(id)).value("docs")[doc.id]
        XCTAssertEqual(Int(rec["done"].double - rec["w0"].double), doc.weeks)
    }

    func testAtHomeTheShownWeeksAreTheDocumentsOwnWeeks() throws {
        var e = try ChainsTests.engine()
        let id = open(&e, "cafe")
        let k = try XCTUnwrap(e.data.catalog["cafe"]?.knobs.first { $0.id == "alc" })
        let q = try XCTUnwrap(e.knobToggleQuote(companyID: id, knob: k.id, option: 0, on: true))
        let doc = try XCTUnwrap(q.documents.first)
        XCTAssertEqual(e.toggleKnobOption(companyID: id, knob: k.id, option: 0, on: true), .done)
        let rec = try XCTUnwrap(e.state.company(id)).value("docs")[doc.id]
        XCTAssertEqual(Int(rec["done"].double - rec["w0"].double), doc.weeks)
    }
}
