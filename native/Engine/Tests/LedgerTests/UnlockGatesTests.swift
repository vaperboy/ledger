import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Every row of the gate table is hidden before its gate and open after it; the `firstYear` keys are read where each
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

    /// A company whose books show `rev` of sales and the given closed months.
    private func trade(_ e: inout GameEngine, rev: Double = 0, months: [Double] = [], week: Int) throws {
        if e.state.companies.isEmpty { _ = ChainsTests.start(&e, "cafe") }
        e.update { s, _, _ in
            s.week = week
            guard let i = s.companies.indices.first(where: { s.companies[$0].type != "hold" }) else { return }
            var b = s.companies[i].books
            b.total["rev"] = rev
            b.total["loss"] = 0
            b.total["fine"] = 0
            s.companies[i].books = b
            s.companies[i].monthlyHistory = months.enumerated().map { MonthRecord(monthIndex: $0.offset, revenue: 1, profit: $0.element, cash: 0) }
        }
    }

    func testSuppliersOpenAfterTheFirstWeekOfSales() throws {
        var e = try ChainsTests.engine()
        Self.doneUpTo(&e, 0)
        try trade(&e, rev: 0, week: 0)
        XCTAssertEqual(vis(e, .suppliers), .hidden)
        try trade(&e, rev: 0, week: 3)
        XCTAssertEqual(vis(e, .suppliers), .locked("Unlocks after your first week of sales"))
        try trade(&e, rev: 5_000, week: 0)
        XCTAssertNotEqual(vis(e, .suppliers), .open, "the week has not closed")
        try trade(&e, rev: 5_000, week: 1)
        for g in [Gate.suppliers, .marketplace] { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
    }

    func testInsuranceOpensWithTheFirstProfitableMonthOrTheFirstLoss() throws {
        var e = try ChainsTests.engine()
        Self.doneUpTo(&e, 0)
        try trade(&e, months: [], week: 3)
        XCTAssertEqual(vis(e, .insurance), .locked("Unlocks with your first profitable month or your first loss"))
        try trade(&e, months: [5_000], week: 6)
        for g in [Gate.insurance, .weather] { XCTAssertEqual(vis(e, g), .open, "profit: " + g.rawValue) }
        try trade(&e, months: [-2_000], week: 6)
        XCTAssertEqual(vis(e, .insurance), .open, "a month at a loss")
        try trade(&e, months: [], week: 6)
        e.update { s, _, _ in
            guard let i = s.companies.indices.first(where: { s.companies[$0].type != "hold" }) else { return }
            var b = s.companies[i].books
            b.total["fine"] = 400
            s.companies[i].books = b
        }
        XCTAssertEqual(vis(e, .insurance), .open, "a fine is a loss event")
    }

    func testManagerFeaturesStayWithTheLadderAndTheChain() throws {
        XCTAssertEqual(Gate.management.rule, .goal(7))
        XCTAssertEqual(Gates.entry(.unlock("chain")).rule, .weeksTraded(Unlocks.weeksChain))
        XCTAssertEqual(Gates.entry(.unlock("board")).rule, .boardSeat)
    }

    func testEveryGateAndUnlockHasOneRowInTheTable() {
        for g in Gate.allCases { XCTAssertEqual(Gates.table.filter { $0.feature == .gate(g) }.count, 1, g.rawValue) }
        for d in Unlocks.defs { XCTAssertEqual(Gates.table.filter { $0.feature == .unlock(d.id) }.count, 1, d.id) }
    }

    func testRoadmapListsLockedFeaturesWithConditionsAndProgress() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        Self.doneUpTo(&e, 2)
        let road = e.unlockRoadmap()
        let ids = road.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        for want in ["gate.marketing", "gate.insurance", "gate.suppliers", "gate.group", "gate.luxury", "unlock.chain", "unlock.franchise", "unlock.research"] {
            XCTAssertTrue(ids.contains(want), "\(want) is locked and listed")
        }
        XCTAssertFalse(ids.contains("gate.reviews"), "systems that follow another are not listed twice")
        XCTAssertFalse(ids.contains("unlock.marketplace"))
        for item in road {
            XCTAssertFalse(item.title.isEmpty); XCTAssertFalse(item.condition.isEmpty, item.id)
            XCTAssertTrue((0...1).contains(item.progress), item.id)
        }
        XCTAssertEqual(road.first { $0.id == "gate.group" }?.detail, "1 of 3 companies")
        XCTAssertEqual(road.first { $0.id == "unlock.chain" }?.companyID, id)
        XCTAssertEqual(road.map { $0.progress }, road.map { $0.progress }.sorted(by: >), "closest first")
        // Opening something removes it from the list.
        try trade(&e, rev: 5_000, week: 1)
        XCTAssertFalse(e.unlockRoadmap().contains { $0.id == "gate.suppliers" })
        // An old save without a ladder has no locked app surface.
        e.update { s, _, _ in s.rest["ldr"] = nil }
        XCTAssertFalse(e.unlockRoadmap().contains { $0.id.hasPrefix("gate.") })
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
