import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class CafeCapacityTests: XCTestCase {
    private func newCafe() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 2026)
        e.update { s, _, _ in Ledger.move(&s, .me, 20_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 4_000_000, quickSetup: false) else { throw XCTSkip("could not start a company") }
        e.update { s, d, _ in _ = CompanySetup.quickSetupReport(&s, companyID: id, data: d, options: CompanySetup.SetupOptions(optionalEquipment: true)) }
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

    private func breakDown(_ e: inout GameEngine, _ id: Int, _ equipmentIDs: [String], days: Double = 10) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var units = s.companies[i].value("units")
            for eq in equipmentIDs {
                var list = units[eq].array
                XCTAssertFalse(list.isEmpty, eq)
                for n in list.indices { list[n]["down"] = .number(days) }
                units[eq] = .array(list)
            }
            s.companies[i].set("units", units)
        }
    }

    private func capacity(_ e: GameEngine, _ id: Int) throws -> CapacityResult {
        let co = try XCTUnwrap(e.state.company(id))
        return CapacityModel.compute(co, try XCTUnwrap(e.data.catalog[co.type]), World(state: e.state, data: e.data))
    }

    private func demand(_ e: GameEngine, _ id: Int) throws -> Double {
        let co = try XCTUnwrap(e.state.company(id))
        return DemandModel.compute(co, try XCTUnwrap(e.data.catalog[co.type]), World(state: e.state, data: e.data)).customers
    }

    func testFridgeInRepairTakesOnlyTheChilledItems() throws {
        var (e, id) = try newCafe()
        for _ in 0..<60 { e.nextDay() }
        let base = try capacity(e, id).capacity, baseD = try demand(e, id)
        XCTAssertGreaterThan(base, 0)
        breakDown(&e, id, ["disp"])
        let r = try capacity(e, id)
        let lost = 1 - r.capacity / base
        XCTAssertEqual(lost, 4.5 / 12.5, accuracy: 0.01)
        XCTAssertEqual(1 - (try demand(e, id)) / baseD, 4.5 / 12.5, accuracy: 0.01)
        XCTAssertEqual(r.bottleneck?.key, "eq:disp")
        XCTAssertEqual(r.bottleneck?.label, "Display fridge (broken, in repair)")
        XCTAssertEqual(r.outage?.note, "Display fridge in repair: chilled items off sale, about 36% fewer customers served.")
    }

    func testTwoMachinesDownCutMoreButNotEverything() throws {
        var (e, id) = try newCafe()
        for _ in 0..<60 { e.nextDay() }
        let base = try capacity(e, id).capacity
        var one = e
        breakDown(&one, id, ["disp"])
        breakDown(&e, id, ["disp", "dish"])
        let c1 = try capacity(one, id).capacity, c2 = try capacity(e, id).capacity
        XCTAssertLessThan(c2, c1)
        XCTAssertGreaterThan(c2, 0)
        XCTAssertEqual(c2 / base, (1 - 4.5 / 12.5) * (1 - EquipmentOutage.otherRequiredShare), accuracy: 0.01)
        breakDown(&e, id, ["esp", "oven", "pos"])
        XCTAssertGreaterThan(try capacity(e, id).capacity, 0)
    }

    func testPartWeekRepairCostsItsShareOfTheWeek() throws {
        var (e, id) = try newCafe()
        for _ in 0..<60 { e.nextDay() }
        let base = try capacity(e, id).capacity
        breakDown(&e, id, ["dish"], days: 3.5)
        XCTAssertEqual(1 - (try capacity(e, id)).capacity / base, 0.5 * EquipmentOutage.otherRequiredShare, accuracy: 0.01)
    }

    func testWeekWithMachineInRepairStillSellsAndSaysWhatWasLost() throws {
        var (e, id) = try newCafe()
        for _ in 0..<60 { e.nextDay() }
        var broken = e
        breakDown(&broken, id, ["disp"], days: 21)
        for _ in 0..<14 { e.nextDay(); broken.nextDay() }
        let ok = try XCTUnwrap(e.state.company(id)).value("lastW"), lw = try XCTUnwrap(broken.state.company(id)).value("lastW")
        XCTAssertGreaterThan(lw["units"].double, 0)
        XCTAssertLessThan(lw["units"].double, ok["units"].double * 0.8, "\(lw) vs \(ok)")
        XCTAssertEqual(lw["bot"].string, "Display fridge (broken, in repair)")
        XCTAssertTrue(lw["out"].string.contains("chilled items off sale"))
        XCTAssertTrue(ok["out"].isNull)
        let co = try XCTUnwrap(broken.state.company(id))
        XCTAssertEqual(broken.companyHealth(co).bottleneck, "Display fridge (broken, in repair)")
        XCTAssertTrue(broken.insights(for: co, limit: 10).contains { $0.id == "repair" && $0.text.contains("fewer customers served") })
    }

    func testRequiredMachineNeverBoughtStillStopsTrade() throws {
        var (e, id) = try newCafe()
        for _ in 0..<60 { e.nextDay() }
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var eq = s.companies[i].value("eq"); eq["disp"]["n"] = 0; s.companies[i].set("eq", eq)
            var units = s.companies[i].value("units"); units["disp"] = .array([]); s.companies[i].set("units", units)
        }
        let r = try capacity(e, id)
        XCTAssertEqual(r.capacity, 0)
        XCTAssertEqual(r.bottleneck?.label, "Display fridge (required)")
    }

    func testWeekThatServedNoOneKeepsItsReason() throws {
        var (e, id) = try newCafe()
        for _ in 0..<60 { e.nextDay() }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].set("lastW", .object(["units": 0, "rev": 0, "D": 250, "cap": 0, "util": 0, "bot": "Space (0 m2)"])) } }
        let h = e.companyHealth(try XCTUnwrap(e.state.company(id)))
        XCTAssertEqual(h.servedLastWeek, 0)
        XCTAssertEqual(h.bottleneck, "Space (0 m2)")
    }

    func testOnlyVanInRepairCutsButDoesNotStopTheRound() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: "handy", cityID: s.player.cityID, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: "handy", cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 0) * 1.2)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(10 * 7) { e.nextDay() }
        guard e.state.company(id)?.status == .open else { throw XCTSkip("handyman did not open") }
        let base = try capacity(e, id).capacity
        XCTAssertGreaterThan(base, 0)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var vs = s.companies[i].value("veh").array
            XCTAssertFalse(vs.isEmpty)
            for n in vs.indices { vs[n]["down"] = .number(10) }
            s.companies[i].set("veh", .array(vs))
        }
        let r = try capacity(e, id)
        XCTAssertEqual(r.capacity / base, 1 - EquipmentOutage.maxLoss, accuracy: 0.01)
        XCTAssertTrue(r.bottleneck?.label.hasSuffix("(broken, in repair)") ?? false)
    }
}
