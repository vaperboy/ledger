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
            (.marketing, 3, "Unlocks after your first hire, or in week 6"), (.reviews, 3, "Unlocks after your first hire, or in week 6"),
            (.ownerMoney, 4, "Unlocks after your first decision, or in week 8"),
            (.bank, 7, "Unlocks after your first profitable month or loss, or in week 8"),
            (.newCompany, 7, "Unlocks after your first profitable month, or in week 13"),
            (.management, 7, "Unlocks after your first profitable month, or in week 13"),
            (.techpro, 7, "Unlocks after your first profitable month, or in week 13"),
            (.accounting, 7, "Opens with your first profitable month or loss, or in week 8"),
            (.property, 9, "Unlocks after your first quarter of trading, or in week 17"),
            (.rivals, 9, "Unlocks after your first quarter of trading, or in week 17"),
            (.airstay, 9, "Unlocks after your first quarter of trading, or in week 17"),
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
        XCTAssertEqual(Gate.management.rule, .anyOf([.goal(7), .week(13)]))
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
        e.update { s, d, _ in
            let nw = Valuation.netWorth(s, trades: d.catalog).total
            Ledger.move(&s, .me, Gates.netWorthLimit(s, data: d) * 0.5 - nw, why: "Test funds")
        }
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
        XCTAssertEqual(road.first { $0.id == "gate.group" }?.detail, "Goal 2 of 7")
        XCTAssertEqual(road.first { $0.id == "unlock.chain" }?.companyID, id)
        XCTAssertEqual(road.map { $0.progress }, road.map { $0.progress }.sorted(by: >), "closest first")
        try trade(&e, rev: 5_000, week: 1)
        XCTAssertFalse(e.unlockRoadmap().contains { $0.id == "gate.suppliers" })
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

    func testOneCompanyOpensGroupWithTheFirstProfitableMonth() throws {
        var e = try ChainsTests.engine()
        Self.doneUpTo(&e, 0)
        _ = ChainsTests.start(&e, "cafe")
        XCTAssertEqual(vis(e, .group), .hidden)
        Self.doneUpTo(&e, 6)
        XCTAssertEqual(vis(e, .group), .locked("Unlocks after your first profitable month, or in week 13"))
        Self.doneUpTo(&e, 7)
        XCTAssertEqual(vis(e, .group), .open)
        XCTAssertEqual(Gate.atlas.lockText, Gate.insurance.lockText, "Atlas opens with the insurance gate")
    }

    func testAnOpenedGateStaysOpenAfterItsConditionIsLost() throws {
        var e = try Self.fresh()
        Self.doneUpTo(&e, 7)
        XCTAssertEqual(vis(e, .group), .open)
        e.update { s, d, _ in Gates.recordOpen(&s, data: d) }
        Self.doneUpTo(&e, 0)
        XCTAssertEqual(vis(e, .group), .open)
    }

    func testVenturesNeedOneProfitableQuarterOrWeek26() throws {
        var e = try ChainsTests.engine(ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        func months(_ n: Int) {
            e.update { s, _, _ in
                guard let i = s.companyIndex(id) else { return }
                s.companies[i].monthlyHistory = (0..<n).map { MonthRecord(monthIndex: $0, revenue: 400_000, profit: 9_000, cash: 0) }
            }
        }
        let text = "Unlocks after your first profitable quarter, or in week 26"
        e.update { s, _, _ in s.week = 3 }
        months(2)
        XCTAssertEqual(vis(e, .ventures), .locked(text))
        months(3)
        XCTAssertEqual(vis(e, .ventures), .open)
    }

    func testVenturesProgressCountsClosedMonthsAndWeekFallbackOpensThem() throws {
        var e = try ChainsTests.engine(ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].monthlyHistory = (0..<2).map { MonthRecord(monthIndex: $0, revenue: 400_000, profit: -9_000, cash: 0) }
            s.week = 5
        }
        let item = try XCTUnwrap(e.unlockRoadmap().first { $0.id == "gate.ventures" })
        XCTAssertGreaterThan(item.progress, 0.5)
        XCTAssertEqual(item.condition, "Unlocks after your first profitable quarter, or in week 26")
        XCTAssertNotEqual(vis(e, .ventures), .open)
        e.update { s, _, _ in s.week = 26 }
        XCTAssertEqual(vis(e, .ventures), .open)
    }

    func testLuxuryOpensAboveFiftyMedianWages() throws {
        var e = try Self.fresh()
        XCTAssertEqual(vis(e, .luxury), .hidden)
        let limit = Gates.netWorthLimit(e.state, data: e.data)
        XCTAssertEqual(limit, e.homeCountry.medianMonthlyWage * 50, accuracy: 1)
        e.update { s, _, _ in Ledger.move(&s, .me, limit * 2, why: "Test funds") }
        XCTAssertEqual(vis(e, .luxury), .open)
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
            s.companies[i].cash = -1_000; s.companies[i].weeksNegative = 4
        }
        e.update { s, d, _ in FirstYear.freezeSweep(&s, balance: d.balance); FirstYear.freezeSweep(&s, balance: d.balance) }
        let items = e.state.inbox.filter { $0.title.hasPrefix("Account frozen") }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.body, "The bank has frozen the account until the balance is back above zero.")
        XCTAssertEqual(items.first?.options.count, 1)
        XCTAssertTrue(e.answer(messageID: try XCTUnwrap(items.first).id, option: 0))
        e.update { s, _, _ in s.week = 10; if let i = s.companyIndex(id) { s.companies[i].weeksNegative = 30; s.companies[i].cash = -5_000_000_000 } }
        for _ in 0..<7 { e.nextDay() }
        XCTAssertNotEqual(e.state.company(id)?.status, .bust)
    }
}
