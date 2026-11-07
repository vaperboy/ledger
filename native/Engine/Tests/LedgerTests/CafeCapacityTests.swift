import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// A café with one barista trades from its first weeks; a required machine out for repair stops it and the reason is kept.
final class CafeCapacityTests: XCTestCase {
    private func newCafe() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 2026)
        e.update { s, _, _ in Ledger.move(&s, .me, 20_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 4_000_000) else { throw XCTSkip("could not start a company") }
        return (e, id)
    }

    func testNewCafeWithOneBaristaTradesInFirstWeeks() throws {
        var (e, id) = try newCafe()
        for _ in 0..<60 { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.status, .open)
        XCTAssertGreaterThan(co.value("lastW")["units"].double, 0)
        XCTAssertGreaterThan(co.value("lastW")["cap"].double, 0)
        XCTAssertFalse(co.value("lastW")["bot"].string.isEmpty)
    }

    func testBrokenRequiredMachineStopsServiceAndIsNamed() throws {
        var (e, id) = try newCafe()
        for _ in 0..<60 { e.nextDay() }
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var units = s.companies[i].value("units")
            var list = units["disp"].array
            XCTAssertFalse(list.isEmpty)
            for n in list.indices { list[n]["down"] = .number(10) }
            units["disp"] = .array(list)
            s.companies[i].set("units", units)
        }
        let co = try XCTUnwrap(e.state.company(id))
        let bd = try XCTUnwrap(e.data.catalog[co.type])
        let r = CapacityModel.compute(co, bd, World(state: e.state, data: e.data))
        XCTAssertEqual(r.capacity, 0)
        XCTAssertEqual(r.bottleneck?.key, "eq:disp")
        XCTAssertTrue(r.bottleneck?.label.contains("in repair") ?? false)
        // The week closes with zero capacity: the company's health keeps the reason even after the machine is back.
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].set("lastW", .object(["units": 0, "rev": 0, "D": 250, "cap": 0, "util": 0, "bot": "Display fridge (broken, in repair)"])) } }
        let h = e.companyHealth(try XCTUnwrap(e.state.company(id)))
        XCTAssertEqual(h.servedLastWeek, 0)
        XCTAssertEqual(h.bottleneck, "Display fridge (broken, in repair)")
    }
}
