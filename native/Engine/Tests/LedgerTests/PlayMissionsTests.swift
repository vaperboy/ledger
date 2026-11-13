import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

final class PlayMissionsTests: XCTestCase {
    private func game(seed: Int = 77, ladder: Bool = true) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 6_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            if ladder { PlayerGoals.startLadder(&s) } else { s.rest["ldr"] = nil }
        }
        return (e, id)
    }

    private let day0 = 740_000

    func testPoolsAreLongAndEveryEntryIsValid() throws {
        let (e, _) = try game()
        XCTAssertGreaterThanOrEqual(PlayMissions.poolSize(.day), 150)
        XCTAssertGreaterThanOrEqual(PlayMissions.poolSize(.week), 60)
        XCTAssertGreaterThanOrEqual(PlayMissions.poolSize(.season), 40)
        let metrics: Set<String> = ["advance", "decision", "event", "answered", "weeks", "rev", "profit", "mkt", "hire", "mgr", "cos", "loans", "recv", "cmp", "nw"]
        for p in PlayMissions.Period.allCases {
            var ids: Set<String> = []
            for d in PlayMissions.pool(p) {
                XCTAssertTrue(ids.insert(d.id).inserted, d.id)
                XCTAssertTrue(metrics.contains(d.metric), d.id)
                XCTAssertTrue(d.trades.allSatisfy { e.data.catalog[$0] != nil }, d.id)
                XCTAssertTrue(d.features.allSatisfy { LevelFeature(rawValue: $0) != nil }, d.id)
                XCTAssertFalse(d.title.isEmpty)
                if d.metric == "rev" || d.metric == "profit" { XCTAssertGreaterThan(d.days, 0, d.id) } else { XCTAssertGreaterThan(d.target, 0, d.id) }
            }
            XCTAssertGreaterThan(PlayMissions.pool(p).filter { $0.tier == .easy }.count, 20)
            XCTAssertGreaterThan(PlayMissions.pool(p).filter { $0.tier == .hard }.count, 20)
        }
    }

    func testDrawIsTheSameForOnePlayerAndDayButDiffersAcrossPlayersAndDays() throws {
        let (e, _) = try game()
        func ids(_ key: String, _ day: Int) -> [String] { PlayMissions.draw(.day, e.state, e.data, index: day, key: key).map { $0.id } }
        XCTAssertEqual(ids("player-a", day0), ids("player-a", day0))
        XCTAssertEqual(ids("player-a", day0 + 1), ids("player-a", day0 + 1))
        let players: Set<[String]> = Set((0..<30).map { ids("player-\($0)", day0) })
        XCTAssertGreaterThan(players.count, 15)
        let days: Set<[String]> = Set((0..<30).map { ids("player-a", day0 + $0) })
        XCTAssertGreaterThan(days.count, 15)
    }

    func testEveryPeriodHasTheRightEasyAndHardCount() throws {
        let (e, _) = try game()
        for p in PlayMissions.Period.allCases {
            for k in 0..<20 {
                let set: [PlayMissions.Def] = PlayMissions.draw(p, e.state, e.data, index: day0 + k, key: "k\(k)")
                XCTAssertEqual(set.filter { $0.tier == .easy }.count, p.easyCount, "\(p)")
                XCTAssertEqual(set.filter { $0.tier == .hard }.count, p.hardCount, "\(p)")
                XCTAssertEqual(Set(set.map { $0.id }).count, set.count)
                if p == .day { XCTAssertEqual(set.count, 5); XCTAssertEqual(set.last?.tier, .hard) }
            }
        }
    }

    func testNeverDrawsLockedFeaturesOrTradesThePlayerDoesNotRun() throws {
        let (e, _) = try game()
        XCTAssertFalse(e.levelOpen(.marketing))
        for p in PlayMissions.Period.allCases {
            for k in 0..<120 {
                for d in PlayMissions.draw(p, e.state, e.data, index: day0 + k, key: "who\(k % 7)") {
                    XCTAssertTrue(d.trades.allSatisfy { $0 == "cafe" }, d.id)
                    XCTAssertTrue(d.families.allSatisfy { $0 == "venue" }, d.id)
                    XCTAssertTrue(d.features.isEmpty, "\(d.id) needs \(d.features) that are locked")
                    XCTAssertFalse(d.title.contains("{"), d.id)
                }
            }
        }
    }

    func testOpenedFeaturesAndOwnedTradesCanBeDrawn() throws {
        var (e, _) = try game(ladder: false)
        e.update { s, data, ctx in
            _ = CompanySetup.create(&s, tradeID: "barber", cityID: s.player.cityID, data: data, context: ctx)
            for c in s.companies.indices { s.companies[c].status = .open }
        }
        var trades: Set<String> = []
        var features: Set<String> = []
        for k in 0..<300 {
            for d in PlayMissions.draw(.day, e.state, e.data, index: day0 + k, key: "p\(k)") {
                trades.formUnion(d.trades); features.formUnion(d.features)
            }
        }
        XCTAssertTrue(trades.isSubset(of: ["cafe", "barber"]), "\(trades)")
        XCTAssertTrue(trades.contains("barber"))
        XCTAssertTrue(features.contains("marketing"))
    }

    func testNothingIsDrawnWithoutAnOpenCompany() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 5)
        e.update { s, d, c in PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: day0) }
        XCTAssertTrue(PlayMissions.entries(e.state, .day, today: day0, currency: e.homeCurrency).isEmpty)
    }

    func testRewardsGrowWithDifficulty() throws {
        let (e, _) = try game()
        let cur: Currency = e.homeCurrency
        let easy: Int = 8, hard: Int = 120
        XCTAssertLessThan(PlayMissions.rewardXP(minutes: easy), PlayMissions.rewardXP(minutes: hard))
        XCTAssertLessThan(PlayMissions.rewardCash(minutes: easy, cur), PlayMissions.rewardCash(minutes: hard, cur))
        XCTAssertLessThan(PlayMissions.rewardGold(minutes: easy), PlayMissions.rewardGold(minutes: hard))
        XCTAssertLessThanOrEqual(PlayMissions.rewardGold(minutes: hard), 10, "gold stays small")
        for p in PlayMissions.Period.allCases {
            let pool: [PlayMissions.Def] = PlayMissions.pool(p)
            let easyMax: Int = pool.filter { $0.tier == .easy }.map { $0.minutes }.max() ?? 0
            let hardMin: Int = pool.filter { $0.tier == .hard }.map { $0.minutes }.min() ?? 0
            XCTAssertLessThan(easyMax, hardMin, "\(p)")
        }
    }

    func testDailySetTakesAboutHalfAnHourAndTheHardOneAboutTwoHours() throws {
        for d in PlayMissions.pool(.day) {
            if d.tier == .easy { XCTAssertTrue((4...12).contains(d.minutes), "\(d.id) \(d.minutes)") } else { XCTAssertTrue((90...145).contains(d.minutes), "\(d.id) \(d.minutes)") }
        }
    }

    func testPlayingMovesProgressAndASetStaysFixedForTheDay() throws {
        var (e, _) = try game()
        let today: Int = SeasonCatalog.today()
        let cur: Currency = e.homeCurrency
        e.update { s, d, c in PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: today, key: "p1") }
        let first: [String] = PlayMissions.entries(e.state, .day, today: today, currency: cur).map { $0.missionID }
        XCTAssertEqual(first.count, 5)
        e.update { s, d, c in PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: today) }
        XCTAssertEqual(PlayMissions.entries(e.state, .day, today: today, currency: cur).map { $0.missionID }, first)
        for _ in 0..<14 { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
        let after: [PlayMissions.Entry] = PlayMissions.entries(e.state, .day, today: today, currency: cur)
        XCTAssertEqual(after.map { $0.missionID }, first)
        XCTAssertTrue(after.contains { $0.progress > 0 }, "two weeks of play must move something")
        XCTAssertGreaterThanOrEqual(PlayMissions.reading("advance|all", e.state, e.data), 14)
        XCTAssertGreaterThanOrEqual(PlayMissions.reading("weeks|all", e.state, e.data), 2)
        XCTAssertGreaterThan(PlayMissions.reading("rev|trade:cafe", e.state, e.data), 0)
        XCTAssertEqual(PlayMissions.reading("rev|trade:barber", e.state, e.data), 0)
    }

    func testClaimPaysOnceAndOnlyWhenFinished() throws {
        var (e, _) = try game()
        let cur: Currency = e.homeCurrency
        e.update { s, d, c in PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: day0, key: "p2") }
        let entry: PlayMissions.Entry = PlayMissions.entries(e.state, .day, today: day0, currency: cur)[0]
        XCTAssertEqual(e.claimMission(.day, id: entry.missionID), .notReady)
        e.update { s, _, _ in
            var root: JSONValue = s.rest[PlayMissions.storeKey] ?? .null
            var list: [JSONValue] = root["d"]["l"].array
            list[0]["x"] = list[0]["n"]
            var set: JSONValue = root["d"]
            set["l"] = .array(list)
            root["d"] = set
            s.rest[PlayMissions.storeKey] = root
        }
        XCTAssertEqual(PlayMissions.ready(e.state, today: day0, currency: cur).count, 1)
        let cash0: Double = e.state.cash
        let xp0: Int = e.playerLevel.xp
        guard case .claimed(_, let xp, let cash, let gold) = e.claimMission(.day, id: entry.missionID) else { return XCTFail("not claimed") }
        XCTAssertEqual(xp, entry.xp); XCTAssertEqual(cash, entry.cash); XCTAssertEqual(gold, entry.gold)
        XCTAssertEqual(e.playerLevel.xp, xp0 + xp)
        XCTAssertEqual(e.state.cash, cash0 + cash, accuracy: 1)
        XCTAssertEqual(e.claimMission(.day, id: entry.missionID), .notReady)
        XCTAssertEqual(e.state.cash, cash0 + cash, accuracy: 1)
        XCTAssertTrue(PlayMissions.ready(e.state, today: day0, currency: cur).isEmpty)
    }

    func testFinishedUnclaimedMissionsCarryToTheNextDay() throws {
        var (e, _) = try game()
        let cur: Currency = e.homeCurrency
        e.update { s, d, c in PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: day0, key: "p3") }
        e.update { s, _, _ in
            var root: JSONValue = s.rest[PlayMissions.storeKey] ?? .null
            var set: JSONValue = root["d"]
            var list: [JSONValue] = set["l"].array
            list[1]["x"] = list[1]["n"]
            set["l"] = .array(list)
            root["d"] = set
            s.rest[PlayMissions.storeKey] = root
        }
        let id: String = PlayMissions.entries(e.state, .day, today: day0, currency: cur)[1].missionID
        e.update { s, d, c in PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: day0 + 1, key: "p3") }
        let next: [PlayMissions.Entry] = PlayMissions.entries(e.state, .day, today: day0 + 1, currency: cur)
        XCTAssertTrue(next.contains { $0.missionID == id && $0.carried && $0.ready })
        guard case .claimed = e.claimMission(.day, id: id) else { return XCTFail("carried mission not claimable") }
    }

    func testTwoFinishedDailyMissionsKeepTheDayStreak() throws {
        var (e, _) = try game()
        e.update { s, d, c in PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: day0, key: "p4") }
        XCTAssertEqual(PlayerGoals.streakInfo(e.state).count, 0)
        e.update { s, d, c in
            var root: JSONValue = s.rest[PlayMissions.storeKey] ?? .null
            var set: JSONValue = root["d"]
            var list: [JSONValue] = set["l"].array
            for i in 0..<2 { list[i]["x"] = list[i]["n"] }
            set["l"] = .array(list)
            root["d"] = set
            s.rest[PlayMissions.storeKey] = root
            PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: day0, key: "p4")
            PlayMissions.sync(&s, data: d, currency: c.homeCurrency(s), today: day0, key: "p4")
        }
        XCTAssertEqual(PlayerGoals.streakInfo(e.state).count, 1)
    }
}
