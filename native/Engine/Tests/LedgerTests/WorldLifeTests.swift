import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

final class WorldLifeTests: XCTestCase {
    private func trading(seed: Int = 777) throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("UK", seed: seed)
        let id = ChainsTests.start(&e, "grocery")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].openedWeek = s.week - 50
            s.companies[i].set("lastW", .object(["units": .number(100), "rev": .number(5000), "cogs": .number(2000)]))
            s.week = 20
            s.day = 0
        }
        return (e, id)
    }

    private func offerOne(_ e: inout GameEngine) -> Bool {
        for w in 20..<80 {
            for d in 0..<6 {
                e.update { s, data, _ in
                    s.week = w
                    s.day = d
                    DailyOrders.runDay(&s, data: data)
                }
                if DailyOrders.hasOpenOffer(e.state) { return true }
            }
        }
        return false
    }

    func testTheStreakGrowsEachDayAndOnlyPausesWhenYouMissDays() {
        var st = LoginStreak()
        var r = LoginStreakRules.open(st, today: 100)
        XCTAssertEqual(r.streak.count, 1)
        XCTAssertNotNil(r.reward)
        st = r.streak
        XCTAssertNil(LoginStreakRules.open(st, today: 100).reward)
        r = LoginStreakRules.open(st, today: 101)
        XCTAssertEqual(r.streak.count, 2)
        st = r.streak
        r = LoginStreakRules.open(st, today: 105)
        XCTAssertEqual(r.streak.count, 3, "a short break keeps the streak where it was")
        st = r.streak
        r = LoginStreakRules.open(st, today: 200)
        XCTAssertEqual(r.streak.count, 2, "a long break halves it and never drops to zero")
        XCTAssertEqual(r.streak.best, 3)
        XCTAssertGreaterThanOrEqual(LoginStreakRules.open(LoginStreak(count: 1, best: 1, lastDay: 1), today: 500).streak.count, 2)
    }

    func testEverySeventhDayAddsABox() {
        XCTAssertEqual(LoginStreakRules.reward(day: 6).boxes, 0)
        XCTAssertEqual(LoginStreakRules.reward(day: 7).boxes, 1)
        XCTAssertEqual(LoginStreakRules.reward(day: 14).boxes, 1)
        XCTAssertLessThanOrEqual(LoginStreakRules.reward(day: 400).gold, 3)
        XCTAssertGreaterThan(LoginStreakRules.reward(day: 1).gold, 0)
        XCTAssertEqual(LoginStreakRules.daysToBox(LoginStreak(count: 3, best: 3, lastDay: 1)), 4)
    }

    func testTheRaceRanksByGrowthAndPaysTheTopThreeWithSomeoneBehind() {
        let list = [RaceEntry(id: "a", name: "Ann", growth: 0.02), RaceEntry(id: "me", name: "You", growth: 0.05, isYou: true),
                    RaceEntry(id: "b", name: "Bo", growth: 0.05), RaceEntry(id: "c", name: "Cy", growth: -0.01), RaceEntry(id: "d", name: "Di", growth: 0.0)]
        let order = FriendRace.standings(list).map(\.id)
        XCTAssertEqual(order, ["b", "me", "a", "d", "c"])
        XCTAssertEqual(FriendRace.place(of: "me", in: list), 2)
        XCTAssertEqual(FriendRace.reward(place: 1, racers: 5), 3)
        XCTAssertEqual(FriendRace.reward(place: 3, racers: 5), 1)
        XCTAssertEqual(FriendRace.reward(place: 4, racers: 5), 0)
        XCTAssertEqual(FriendRace.reward(place: 1, racers: 1), 0, "racing alone pays nothing")
        XCTAssertEqual(FriendRace.reward(place: 2, racers: 2), 0)
        XCTAssertEqual(FriendRace.reward(place: 1, racers: 2), 15)
        XCTAssertEqual(FriendRace.growth(base: 1000, now: 1100), 0.1, accuracy: 1e-9)
        XCTAssertEqual(FriendRace.growth(base: 0, now: 5), 0)
    }

    func testOneGiftADay() {
        XCTAssertTrue(GiftRules.canSend(lastSentDay: 10, today: 11))
        XCTAssertFalse(GiftRules.canSend(lastSentDay: 11, today: 11))
    }

    func testTheSharedGoalScalesWithTheGroupAndPicksAnUnownedReward() {
        XCTAssertEqual(SharedGoalRules.target(members: 4), 1200)
        XCTAssertEqual(SharedGoalRules.target(members: 1), 600)
        let first = SharedGoalRules.reward(week: 0, owned: [])
        XCTAssertEqual(first, SharedGoalRules.rewards[0])
        XCTAssertEqual(SharedGoalRules.reward(week: 0, owned: [SharedGoalRules.rewards[0]]), SharedGoalRules.rewards[1])
        XCTAssertNil(SharedGoalRules.reward(week: 3, owned: Set(SharedGoalRules.rewards)))
        let g = SharedGoalRules.state(week: 2, members: 3, contributions: [400, 300, 100], owned: [])
        XCTAssertFalse(g.met)
        XCTAssertTrue(SharedGoalRules.state(week: 2, members: 3, contributions: [400, 300, 250, 100], owned: []).met)
    }

    func testPassingARealPlayerIsNoticedOnceWithoutLeakingPrivateNames() throws {
        let rivals = [RichRival(id: "r1", name: "Real One", netWorth: 300, isReal: true, visible: true),
                      RichRival(id: "r2", name: "Fake", netWorth: 400, isReal: false, visible: true),
                      RichRival(id: "r3", name: "Hidden Person", netWorth: 200, isReal: true, visible: false),
                      RichRival(id: "r4", name: "Above", netWorth: 900, isReal: true, visible: true)]
        var e = try ChainsTests.engine("UK", seed: 5)
        XCTAssertTrue(e.notePassedPlayers(rivals, netWorth: 100).isEmpty, "the first look only sets the baseline")
        let found = e.notePassedPlayers(rivals, netWorth: 500)
        XCTAssertEqual(found.map(\.id), ["r1", "r3"])
        XCTAssertTrue(e.notePassedPlayers(rivals, netWorth: 600).isEmpty, "each player is announced once")
        XCTAssertEqual(RichPass.myNotice([found[0]]), "You passed Real One in net worth.")
        XCTAssertEqual(RichPass.myNotice([found[1]]), "You passed a player in net worth.")
        XCTAssertEqual(RichPass.myNotice(found), "You passed Real One and 1 more player in net worth.")
        XCTAssertNil(RichPass.myNotice([]))
        XCTAssertEqual(RichPass.theirNotice(passer: "Me", visible: false), "A player passed you in net worth.")
        XCTAssertEqual(RichPass.theirNotice(passer: "Me", visible: true), "Me passed you in net worth.")
        XCTAssertFalse(RichPass.myNotice(found)?.contains("Hidden") ?? true)
    }

    func testTheLocalNameStaysInsideItsCap() throws {
        XCTAssertEqual(LocalFame.target(reputations: [50], fined: 0), 0)
        XCTAssertEqual(LocalFame.target(reputations: [45, 55], fined: 0), 0)
        XCTAssertGreaterThan(LocalFame.target(reputations: [95], fined: 0), 40)
        XCTAssertLessThan(LocalFame.target(reputations: [5], fined: 0), -40)
        XCTAssertEqual(LocalFame.target(reputations: [100], fined: 0), 100)
        XCTAssertLessThan(LocalFame.target(reputations: [50], fined: 1), 0)
        XCTAssertEqual(LocalFame.target(reputations: [], fined: 3), 0)
        var s = try ChainsTests.engine("UK", seed: 5).state
        s.rest["fame"] = .object(["leeds": .number(100), "hull": .number(-100), "bath": .number(900)])
        XCTAssertEqual(LocalFame.demandFactor(s, city: "leeds"), 1.05, accuracy: 1e-12)
        XCTAssertEqual(LocalFame.demandFactor(s, city: "hull"), 0.95, accuracy: 1e-12)
        XCTAssertEqual(LocalFame.demandFactor(s, city: "bath"), 1.05, accuracy: 1e-12)
        XCTAssertEqual(LocalFame.demandFactor(s, city: "none"), 1)
    }

    func testAGoodNameGrowsLiftsDemandAndMakesNews() throws {
        let pair = try trading()
        var e = pair.0
        let id = pair.1
        var city = ""
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].reputation = 95
            city = s.companies[i].cityID
            for _ in 0..<40 { LocalFame.weekly(&s, data: data) }
        }
        let score = LocalFame.score(e.state, city: city)
        XCTAssertGreaterThan(score, 40)
        XCTAssertEqual(LocalFame.demandFactor(e.state, city: city), 1 + score / 100 * LocalFame.demandCap, accuracy: 1e-12)
        XCTAssertTrue((e.state.rest["news"]?.array ?? []).contains { $0["t"].string.contains("speaks well") })
        let stats = try XCTUnwrap(e.companyOverviewStats(companyID: id))
        XCTAssertEqual(stats.localName?.word, score >= 70 ? "Beloved" : "Well regarded")
        var part: Double?
        e.update { s, data, _ in
            guard let co = s.company(id), let bd = data.catalog[co.type] else { return }
            part = DemandModel.compute(co, bd, World(state: s, data: data)).part("local name")
        }
        XCTAssertEqual(try XCTUnwrap(part), LocalFame.demandFactor(e.state, city: city), accuracy: 1e-12)
    }

    func testABadNameShrinksDemandAndAnAverageOneChangesNothing() throws {
        let pair = try trading()
        var e = pair.0
        let id = pair.1
        var city = ""
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            city = s.companies[i].cityID
            for _ in 0..<10 { LocalFame.weekly(&s, data: data) }
        }
        XCTAssertNil(e.state.rest["fame"], "a neutral name leaves no trace")
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].reputation = 4
            for _ in 0..<40 { LocalFame.weekly(&s, data: data) }
        }
        XCTAssertLessThan(LocalFame.score(e.state, city: city), -40)
        XCTAssertGreaterThanOrEqual(LocalFame.demandFactor(e.state, city: city), 0.95)
        XCTAssertLessThan(LocalFame.demandFactor(e.state, city: city), 1)
        XCTAssertTrue((e.state.rest["news"]?.array ?? []).contains { $0["t"].string.contains("talking badly") })
    }

    func testASpecialOrderIsOfferedRepeatablyAndIgnoringItCostsNothing() throws {
        let pair = try trading()
        var a = pair.0
        let id = pair.1
        var b = try trading().0
        XCTAssertTrue(offerOne(&a))
        XCTAssertTrue(offerOne(&b))
        let ma = try XCTUnwrap(a.openDecisions.first { $0.actionID == DailyOrders.action })
        let mb = try XCTUnwrap(b.openDecisions.first { $0.actionID == DailyOrders.action })
        XCTAssertEqual(ma.title, mb.title)
        XCTAssertEqual(ma.body, mb.body)
        let cash = try XCTUnwrap(a.state.company(id)).cash
        a.update { s, data, _ in
            s.week += 3
            DailyOrders.runDay(&s, data: data)
        }
        XCTAssertEqual(try XCTUnwrap(a.state.company(id)).cash, cash)
        XCTAssertNil(DailyOrders.active(a.state))
    }

    func testAcceptingPaysABonusOnlyWhenTheWeekReachesTheTarget() throws {
        let pair = try trading()
        var e = pair.0
        let id = pair.1
        XCTAssertTrue(offerOne(&e))
        var m = try XCTUnwrap(e.openDecisions.first { $0.actionID == DailyOrders.action })
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        let act = try XCTUnwrap(DailyOrders.active(e.state))
        let bonus = act["bonus"].double
        XCTAssertGreaterThan(bonus, 0)
        let due = act["week"].int
        let before = try XCTUnwrap(e.state.company(id)).cash
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            s.week = due
            s.day = 6
            s.companies[i].set("lastW", .object(["units": .number(act["target"].double + 5), "rev": .number(5000), "cogs": .number(2000)]))
            DailyOrders.runDay(&s, data: data)
        }
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash - before, bonus, accuracy: 1)
        XCTAssertNil(DailyOrders.active(e.state))

        XCTAssertTrue(offerOne(&e))
        m = try XCTUnwrap(e.openDecisions.first { $0.actionID == DailyOrders.action })
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        let act2 = try XCTUnwrap(DailyOrders.active(e.state))
        let before2 = try XCTUnwrap(e.state.company(id)).cash
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            s.week = act2["week"].int
            s.day = 6
            s.companies[i].set("lastW", .object(["units": .number(1), "rev": .number(50), "cogs": .number(20)]))
            DailyOrders.runDay(&s, data: data)
        }
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, before2, accuracy: 1e-6)
        XCTAssertNil(DailyOrders.active(e.state))
    }

    func testNoOrdersComeBeforeTheFirstWeeksOrWithoutTradingHistory() throws {
        let pair = try trading()
        var e = pair.0
        let id = pair.1
        e.update { s, data, _ in
            s.week = 3
            XCTAssertNil(DailyOrders.offer(s, data: data))
            s.week = 30
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("lastW", .object(["units": .number(0), "rev": .number(0)]))
            XCTAssertNil(DailyOrders.offer(s, data: data))
        }
    }

    func testTheDailyTipComesFromRealStateAndAppearsOncePerDay() throws {
        let pair = try trading()
        var e = pair.0
        let id = pair.1
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("mods", .array([.object(["k": .string("cogsup"), "m": .number(1.12), "w": .number(4)])]))
        }
        let list = MarketTips.candidates(e.state, data: e.data)
        XCTAssertTrue(list.contains { $0.id == "sup.up.\(id)" })
        XCTAssertEqual(MarketTips.best(e.state, data: e.data), MarketTips.best(e.state, data: e.data))
        let before = (e.state.rest["news"]?.array ?? []).count
        e.update { s, data, _ in MarketTips.runDay(&s, data: data) }
        let after = (e.state.rest["news"]?.array ?? []).count
        XCTAssertEqual(after, before + 1)
        XCTAssertTrue((e.state.rest["news"]?.array.first?["t"].string ?? "").hasPrefix("Tip: "))
        e.update { s, data, _ in MarketTips.runDay(&s, data: data) }
        XCTAssertEqual((e.state.rest["news"]?.array ?? []).count, after, "one tip a day")
        e.update { s, data, _ in
            s.day = 1
            MarketTips.runDay(&s, data: data)
        }
        XCTAssertEqual((e.state.rest["news"]?.array ?? []).count, after + 1)
    }

    func testCheaperSuppliersGiveABuyingTipAndNothingHappensWithoutNews() throws {
        let pair = try trading()
        var e = pair.0
        let id = pair.1
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("mods", .array([.object(["k": .string("cogsup"), "m": .number(0.9), "w": .number(4)])]))
        }
        XCTAssertTrue(MarketTips.candidates(e.state, data: e.data).contains { $0.id == "sup.down.\(id)" && $0.text.contains("stock up") })
        e.update { s, data, _ in
            s.week = 2
            MarketTips.runDay(&s, data: data)
        }
        XCTAssertNil(e.state.rest["dtip"], "no tips in the first weeks")
    }
}
