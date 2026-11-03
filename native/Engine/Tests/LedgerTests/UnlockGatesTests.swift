import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Brief Part 5.1 and 5.2: every row of the gate table is hidden before its gate and open after it; the `firstYear` keys are read where each
/// behaviour lives.
final class UnlockGatesTests: XCTestCase {
    static func fresh() throws -> GameEngine { try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 5) }

    /// Mark ladder goals M1 to Mn as finished (and none after).
    static func doneUpTo(_ e: inout GameEngine, _ n: Int) {
        e.update { s, _, _ in
            var d = JSONValue.object([:])
            for k in 0..<n { d["M\(k + 1)"] = .object(["w": .number(Double(s.week))]) }
            s.rest["ldr"] = .object(["done": d])
        }
    }

    func vis(_ e: GameEngine, _ g: Gate) -> GateVisibility { Gates.visibility(g, e.state, data: e.data) }

    func testNewGameStartsTheLadderAndEveryGateIsClosedExceptWhatTheFirstWeeksNeed() throws {
        let e = try Self.fresh()
        XCTAssertTrue(Gates.ladderOn(e.state))
        for g in Gate.allCases { XCTAssertNotEqual(vis(e, g), .open, g.rawValue) }
    }

    func testOldSaveWithoutLadderGatesNothing() throws {
        var e = try Self.fresh()
        e.update { s, _, _ in s.rest["ldr"] = nil }
        for g in Gate.allCases { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
    }

    func testGoalGatesHiddenBeforeAndOpenAfter() throws {
        let rows: [(Gate, Int, String)] = [
            (.marketing, 3, "Unlocks after your first hire"), (.reviews, 3, "Unlocks after your first hire"),
            (.ownerMoney, 4, "Unlocks after your first decision"),
            (.bank, 7, "Unlocks after your first profitable month"), (.newCompany, 7, "Unlocks after your first profitable month"),
            (.management, 7, "Unlocks after your first profitable month"), (.techpro, 7, "Unlocks after your first profitable month"),
            (.accounting, 7, "Opens with your first profitable month"),
            (.insurance, 8, "Unlocks when a manager runs the company"), (.suppliers, 8, "Unlocks when a manager runs the company"),
            (.weather, 8, "Unlocks when a manager runs the company"), (.marketplace, 8, "Unlocks when a manager runs the company"),
            (.property, 9, "Unlocks with your second company"), (.rivals, 9, "Unlocks with your second company"),
            (.airstay, 9, "Unlocks with your second company"),
        ]
        var e = try Self.fresh()
        for (g, n, text) in rows {
            Self.doneUpTo(&e, 0)
            if n > 1 { XCTAssertEqual(vis(e, g), .hidden, "\(g) far before M\(n)") }
            Self.doneUpTo(&e, n - 1)
            XCTAssertEqual(vis(e, g), .locked(text), "\(g) one goal away")
            Self.doneUpTo(&e, n)
            XCTAssertEqual(vis(e, g), .open, "\(g) after M\(n)")
        }
    }

    func testHiringOpensInWeekThreeAndOwnerHoursInWeekThirteen() throws {
        var e = try Self.fresh()
        e.update { s, _, _ in s.week = 1 }
        XCTAssertEqual(vis(e, .hiring), .locked("Unlocks in week 3"))
        XCTAssertEqual(vis(e, .ownerHours), .hidden)
        e.update { s, _, _ in s.week = 3 }
        XCTAssertEqual(vis(e, .hiring), .open)
        XCTAssertEqual(Gates.ownerHoursCap(e.state), 45)
        e.update { s, _, _ in s.week = 13 }
        XCTAssertEqual(vis(e, .ownerHours), .open)
        XCTAssertEqual(Gates.ownerHoursCap(e.state), OwnerHours.weeklyCap)
    }

    func testThreeCompaniesOpenGroupAndAtlas() throws {
        var e = try ChainsTests.engine()
        Self.doneUpTo(&e, 0)
        _ = ChainsTests.start(&e, "cafe")
        for g in [Gate.group, .atlas] { XCTAssertEqual(vis(e, g), .hidden, g.rawValue) }
        _ = ChainsTests.start(&e, "kiosk")
        for g in [Gate.group, .atlas] { XCTAssertEqual(vis(e, g), .locked("Unlocks with three companies"), g.rawValue) }
        _ = ChainsTests.start(&e, "barber")
        for g in [Gate.group, .atlas] { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
    }

    func testVenturesNeedTwoClosedYearsWithProfit() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        func months(_ n: Int) {
            e.update { s, _, _ in
                guard let i = s.companyIndex(id) else { return }
                s.companies[i].monthlyHistory = (0..<n).map { MonthRecord(monthIndex: $0, revenue: 400_000, profit: 9_000, cash: 0) }
            }
        }
        months(3)
        XCTAssertEqual(vis(e, .ventures), .hidden)
        months(12)
        XCTAssertEqual(vis(e, .ventures), .locked("Unlocks after two profitable years"))
        months(24)
        for g in [Gate.ventures, .venturesFeed] { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
    }

    func testLuxuryOpensAboveFiftyMedianWages() throws {
        var e = try Self.fresh()
        XCTAssertEqual(vis(e, .luxury), .hidden)
        let limit = Gates.netWorthLimit(e.state, data: e.data)
        XCTAssertEqual(limit, e.homeCountry.medianMonthlyWage * 50, accuracy: 1)
        e.update { s, _, _ in Ledger.move(&s, .me, limit * 2, why: "Test funds") }
        XCTAssertEqual(vis(e, .luxury), .open)
    }

    // MARK: First year (5.2)

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

    func testFirstYearDemandIsHigherEarlyOnAndTheAuthorityWaitsForThreeCompanies() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let f = e.data.balance.firstYear
        XCTAssertFalse(f.competitionAuthorityActive(e.state))
        _ = ChainsTests.start(&e, "kiosk"); _ = ChainsTests.start(&e, "barber")
        XCTAssertTrue(f.competitionAuthorityActive(e.state))
        let w = World(state: e.state, data: e.data)
        let co = try XCTUnwrap(e.state.company(id))
        let bd = try XCTUnwrap(e.data.catalog[co.type])
        let early = DemandModel.compute(co, bd, w)
        XCTAssertEqual(early.parts.first { $0.name == "firstYear" }?.value, 1.25)
    }

    func testAccountInTheRedBeforeWeek27IsFrozenNotBankrupt() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        UnlocksTests.opened(&e, id, weeksAgo: 0)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].cash = -1_000; s.companies[i].weeksNegative = 4
        }
        e.update { s, d, _ in FirstYear.freezeSweep(&s, balance: d.balance); FirstYear.freezeSweep(&s, balance: d.balance) }
        let items = e.state.inbox.filter { $0.title.hasPrefix("Account frozen") }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.body, "The bank has frozen the account until the balance is back above zero.")
        XCTAssertEqual(items.first?.options.count, 1)
        XCTAssertTrue(e.answer(messageID: try XCTUnwrap(items.first).id, option: 0))
        // The weekly loop does not bust it before week 27.
        e.update { s, _, _ in s.week = 10; if let i = s.companyIndex(id) { s.companies[i].weeksNegative = 30; s.companies[i].cash = -5_000_000_000 } }
        for _ in 0..<7 { e.nextDay() }
        XCTAssertNotEqual(e.state.company(id)?.status, .bust)
    }
}
