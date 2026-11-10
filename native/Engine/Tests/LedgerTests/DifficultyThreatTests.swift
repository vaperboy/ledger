import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Investments
@testable import Simulation

/// Difficulty modes and the success-scaled threats: the mode is kept in the save and set once at the start, it moves the first-year
/// protections and the event ramp, and the threats stay capped.
final class DifficultyThreatTests: XCTestCase {
    func fresh(_ d: Difficulty = .classic) throws -> GameEngine {
        try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test Co",
                               chooseFirstItem: true, difficulty: d)
    }

    func testSandboxIsFreeForEveryone() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test Co", difficulty: .sandbox)
        XCTAssertEqual(e.difficulty, .sandbox)
        XCTAssertNoThrow(try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, difficulty: .hard))
    }

    func testModeIsStoredAndSetOnlyAtTheStart() throws {
        XCTAssertEqual(try fresh().difficulty, .classic)
        XCTAssertEqual(try fresh(.hard).difficulty, .hard)
        var e = try fresh()
        XCTAssertTrue(e.setDifficulty(.sandbox))
        XCTAssertEqual(e.difficulty, .sandbox)
        XCTAssertFalse(e.setDifficulty(.hard), "the mode can be set once")
        XCTAssertEqual(e.difficulty, .sandbox)
        var later = try fresh()
        later.update { s, _, _ in s.week = 3 }
        XCTAssertFalse(later.setDifficulty(.hard), "no change once the game has started")
        XCTAssertEqual(later.difficulty, .classic)
    }

    func testFirstYearProtectionsFollowTheMode() {
        let base = FirstYear()
        let classic = base.applying(.classic), sandbox = base.applying(.sandbox), hard = base.applying(.hard)
        XCTAssertFalse(classic.bankruptcyActive(week: 26))
        XCTAssertTrue(classic.bankruptcyActive(week: 27))
        XCTAssertFalse(sandbox.bankruptcyActive(week: 5000))
        XCTAssertFalse(sandbox.supplierCutoffActive(week: 5000))
        XCTAssertGreaterThan(sandbox.noOverdraftWeeks, classic.noOverdraftWeeks)
        XCTAssertTrue(hard.bankruptcyActive(week: 0))
        XCTAssertTrue(hard.supplierCutoffActive(week: 0))
        XCTAssertLessThan(hard.noOverdraftWeeks, classic.noOverdraftWeeks)
    }

    func testEventRampIsTighterOnHardAndGentlerOnSandbox() throws {
        let b = try Balance.bundled()
        XCTAssertGreaterThan(Difficulty.hard.eventRamp(b, week: 3), Difficulty.classic.eventRamp(b, week: 3))
        XCTAssertLessThan(Difficulty.sandbox.eventRamp(b, week: 60), Difficulty.classic.eventRamp(b, week: 60))
        XCTAssertLessThan(Difficulty.sandbox.badEventCapWeeks, 100)
        XCTAssertGreaterThan(Difficulty.sandbox.badEventCapWeeks, Difficulty.classic.badEventCapWeeks)
        XCTAssertLessThan(Difficulty.hard.badEventCapWeeks, Difficulty.classic.badEventCapWeeks)
    }

    /// Every slide into a crash or a bear market is announced one to three weeks ahead.
    func testMarketDownturnsAreWarnedAhead() throws {
        for d in Difficulty.allCases {
            var s = try fresh(d).state
            var lastWarn = -99
            var bad = 0
            for _ in 0..<600 {
                let before = s.rest["mkt"]?["regime"].string ?? ""
                s.week += 1
                Markets.weekly(&s)
                for n in s.rest["news"]?.array ?? [] where n["t"].string.hasPrefix("MARKET WARNING") { lastWarn = max(lastWarn, n["w"].int) }
                let after = s.rest["mkt"]?["regime"].string ?? ""
                if after != before, after == "crash" || after == "bear" {
                    bad += 1
                    XCTAssertTrue((1...3).contains(s.week - lastWarn), "\(d.name): \(after) at week \(s.week), last warning week \(lastWarn)")
                }
            }
            XCTAssertGreaterThan(bad, 0, d.name)
        }
    }

    func testBidChanceScalesWithRankWealthAndModeAndStaysCapped() {
        let c = Threat.bidChance
        XCTAssertGreaterThan(c(1, 0.8, .classic), c(2, 0.8, .classic))
        XCTAssertEqual(c(3, 1, .hard), 0)
        XCTAssertGreaterThan(c(1, 1, .classic), c(1, 0, .classic))
        XCTAssertGreaterThan(c(1, 0.5, .hard), c(1, 0.5, .classic))
        XCTAssertLessThan(c(1, 0.5, .sandbox), c(1, 0.5, .classic))
        XCTAssertLessThanOrEqual(c(1, 1, .hard), 0.06)
    }

    func testComplaintDebtAndLateWagesWearReputationButCarefulPlayIsUntouched() throws {
        var careful = try fresh().state, late = careful
        XCTAssertEqual(careful.companies.count, 1)
        let rep0 = careful.companies[0].reputation
        late.companies[0].wageShortfall = 1
        for _ in 0..<10 {
            careful.week += 1; late.week += 1
            Threat.reputationDebt(&careful)
            Threat.reputationDebt(&late)
        }
        XCTAssertEqual(careful.companies[0].reputation, rep0, accuracy: 1e-9)
        XCTAssertLessThan(late.companies[0].reputation, rep0)
        XCTAssertGreaterThan(late.companies[0].reputation, rep0 - 5, "a slow wear, not a collapse")
        XCTAssertTrue(late.companies[0].value("mods").array.contains { $0["k"].string == "dem" && $0["m"].double < 1 })
    }

    func testRivalBidForAnAccountEitherFailsOrCostsTheAccountAndSaysSo() throws {
        var s = try fresh().state
        s.week = 40
        let account: JSONValue = .object(["id": .number(1), "name": .string("Acme"), "f": .number(0.2), "rel": .number(95), "w0": .number(0), "disc": .number(0)])
        s.companies[0].set("accts", .array([account]))
        var h = HashedRandom("bid")
        KeyAccounts.rivalApproach(&s, 0, rival: "Rival Ltd", &h)
        XCTAssertEqual(s.companies[0].value("accts").array.count, 1)
        let log = (s.rest["rep"]?["ev"].array ?? []).map { $0["t"].string }
        XCTAssertTrue(log.contains { $0.hasPrefix("Survived it") }, "\(log)")

        var weak = account
        weak["rel"] = .number(0)
        s.companies[0].set("accts", .array([weak]))
        s.companies[0].quality = 0
        KeyAccounts.rivalApproach(&s, 0, rival: "Rival Ltd", &h)
        XCTAssertTrue(s.companies[0].value("accts").array.isEmpty)
    }

    func testCreditorDriftIsSlowFlooredAndScaledByMode() throws {
        func run(_ d: Difficulty, weeks: Int) throws -> Double {
            let e = try fresh(d)
            var s = e.state
            let big = s.rest["group"]?["big"].double ?? 0
            XCTAssertGreaterThan(big, 0)
            s.netWorthHistory = [big * 8]
            s.credit = 70
            for w in 0..<weeks { s.week = w + 1; CreditorPressure.weekly(&s, data: e.data) }
            return s.credit
        }
        let classic = try run(.classic, weeks: 8), sandbox = try run(.sandbox, weeks: 8), hard = try run(.hard, weeks: 8)
        XCTAssertLessThan(classic, 70)
        XCTAssertGreaterThan(classic, 68, "one week is a small step")
        XCTAssertGreaterThan(sandbox, classic)
        XCTAssertLessThan(hard, classic)
        XCTAssertGreaterThanOrEqual(try run(.hard, weeks: 2000), CreditorPressure.floor)
    }
}
