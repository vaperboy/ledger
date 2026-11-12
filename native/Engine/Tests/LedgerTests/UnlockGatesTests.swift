import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

final class UnlockGatesTests: XCTestCase {
    static func fresh() throws -> GameEngine { try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 5) }

    static func doneUpTo(_ e: inout GameEngine, _ n: Int) {
        e.update { s, _, _ in
            var d = JSONValue.object([:])
            for k in 0..<n { d["M\(k + 1)"] = .object(["w": .number(Double(s.week))]) }
            s.rest["ldr"] = .object(["done": d])
        }
    }

    func vis(_ e: GameEngine, _ g: Gate) -> GateVisibility { Gates.visibility(g, e.state, data: e.data) }

    func testNewGameOpensTheCoreAndLocksTheRest() throws {
        let e = try Self.fresh()
        XCTAssertTrue(Gates.ladderOn(e.state))
        for g in Gate.allCases { XCTAssertEqual(vis(e, g) == .open, g.feature == nil, g.rawValue) }
    }

    func testOldSaveWithoutLadderGatesNothing() throws {
        var e = try Self.fresh()
        e.update { s, _, _ in s.rest["ldr"] = nil }
        for g in Gate.allCases { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
    }

    func testGoalsAndWeeksNoLongerOpenAnything() throws {
        var e = try Self.fresh()
        Self.doneUpTo(&e, 9)
        e.update { s, _, _ in s.week = 60 }
        XCTAssertNotEqual(vis(e, .newCompany), .open)
        XCTAssertNotEqual(vis(e, .ventures), .open)
    }

    func testOwnerHoursAreCappedForTheFirstQuarter() throws {
        var e = try Self.fresh()
        e.update { s, _, _ in s.week = 1 }
        XCTAssertEqual(vis(e, .hiring), .open, "hiring is part of the core game")
        XCTAssertEqual(Gates.ownerHoursCap(e.state), 45)
        e.update { s, _, _ in s.week = 13 }
        XCTAssertEqual(Gates.ownerHoursCap(e.state), OwnerHours.weeklyCap)
    }

    func testFirstYearKeysAreInBalanceJson() throws {
        let f = try Balance.bundled().firstYear
        XCTAssertEqual(f.demandMult, [1.25, 1.15, 1.05, 1.0])
        XCTAssertFalse(f.supplierCutoffEnabled); XCTAssertFalse(f.competitionAuthorityEnabled); XCTAssertFalse(f.bankruptcyEnabled)
        XCTAssertEqual(f.supplierCutoffWeek, 27); XCTAssertEqual(f.bankruptcyWeek, 27)
        XCTAssertEqual(f.demandMultiplier(week: 0), 1.25)
        XCTAssertEqual(f.demandMultiplier(week: 13), 1.15)
        XCTAssertEqual(f.demandMultiplier(week: 30), 1.05)
        XCTAssertEqual(f.demandMultiplier(week: 51), 1.0)
        XCTAssertEqual(f.demandMultiplier(week: 52), 1.0)
        XCTAssertFalse(f.supplierCutoffActive(week: 26)); XCTAssertTrue(f.supplierCutoffActive(week: 27))
        XCTAssertFalse(f.bankruptcyActive(week: 26)); XCTAssertTrue(f.bankruptcyActive(week: 27))
    }

    func testFirstYearDemandIsHigherEarlyOnAndTheAuthorityWaitsForAYear() throws {
        var e = try ChainsTests.engine(ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        let f = e.data.balance.firstYear
        XCTAssertFalse(f.competitionAuthorityActive(e.state))
        e.update { s, _, _ in s.week = 52 }
        XCTAssertTrue(f.competitionAuthorityActive(e.state))
        e.update { s, _, _ in s.week = 0 }
        let w = World(state: e.state, data: e.data)
        let co = try XCTUnwrap(e.state.company(id))
        let bd = try XCTUnwrap(e.data.catalog[co.type])
        let untended = DemandModel.compute(co, bd, w)
        XCTAssertEqual(untended.parts.first { $0.name == "firstYear" }?.value, f.untendedDemand)
        e.update { s, _, _ in s.rest["ldr"] = .object(["done": .object(["M1": .object([:]), "M2": .object([:])])]) }
        let chosen = World(state: e.state, data: e.data)
        let early = DemandModel.compute(co, bd, chosen)
        XCTAssertEqual(early.parts.first { $0.name == "firstYear" }?.value, 1.25)
    }

    func testAccountInTheRedBeforeWeek27IsFrozenNotBankrupt() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        UnlocksTests.opened(&e, id, weeksAgo: 0)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            Ledger.set(&s, to: -1_000); s.companies[i].weeksNegative = 4
        }
        e.update { s, d, _ in FirstYear.freezeSweep(&s, balance: d.balance); FirstYear.freezeSweep(&s, balance: d.balance) }
        let items = e.state.inbox.filter { $0.title.hasPrefix("Account frozen") }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.body, "The bank has frozen the account until the balance is back above zero.")
        XCTAssertEqual(items.first?.options.count, 1)
        XCTAssertTrue(e.answer(messageID: try XCTUnwrap(items.first).id, option: 0))
        e.update { s, _, _ in s.week = 10; if let i = s.companyIndex(id) { s.companies[i].weeksNegative = 30; Ledger.set(&s, to: -5_000_000_000) } }
        for _ in 0..<7 { e.nextDay() }
        XCTAssertNotEqual(e.state.company(id)?.status, .bust)
    }
}
