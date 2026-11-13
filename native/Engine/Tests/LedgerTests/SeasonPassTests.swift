import XCTest
import GameCore
@testable import Simulation

final class SeasonPassTests: XCTestCase {
    private let day0 = 20_000

    private func snap(seed: Int = 1, week: Int = 1, cash: Double = 100, months: Int = 0, loans: Int = 0, goals: Int = 0, daily: String = "", counters: [String: Int] = [:]) -> SeasonPass.Snapshot {
        SeasonPass.Snapshot(seed: seed, week: week, cash: cash, profitMonths: months, loans: loans, goals: goals, dailyDone: daily, counters: counters)
    }

    func testTierMath() {
        XCTAssertEqual(SeasonPass.tier(forXP: 0), 0)
        XCTAssertEqual(SeasonPass.tier(forXP: 299), 0)
        XCTAssertEqual(SeasonPass.tier(forXP: 300), 1)
        XCTAssertEqual(SeasonPass.tier(forXP: 8_999), 29)
        XCTAssertEqual(SeasonPass.tier(forXP: 9_000), 30)
        XCTAssertEqual(SeasonPass.tier(forXP: 99_999), 30)
        var p = SeasonPass(today: day0)
        p.xp = 350
        XCTAssertEqual(p.tier, 1)
        XCTAssertEqual(p.xpIntoTier, 50)
        XCTAssertEqual(p.progressText, "Tier 1 of 30. 50 of 300 XP to tier 2")
        p.xp = 9_000
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.tierProgress, 1)
    }

    func testUnlockedTiersAddToProgressAndStopAtTheTop() {
        var p = SeasonPass(today: day0)
        p.xp = 350
        XCTAssertEqual(p.unlockTiers(10), 10 * SeasonPass.xpPerTier)
        XCTAssertEqual(p.tier, 11)
        XCTAssertEqual(p.xpIntoTier, 50, "progress inside the current tier is kept")
        p.unlockTiers(100)
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.unlockTiers(5), 0)
        XCTAssertEqual(p.unlockTiers(-3), 0)
    }

    func testDailyCapAndNewDay() {
        var p = SeasonPass(today: day0)
        XCTAssertEqual(p.award(.milestone, today: day0), 50)
        XCTAssertEqual(p.award(.milestone, today: day0), 10, "the second one is trimmed to what is left")
        XCTAssertEqual(p.award(.milestone, today: day0), 0, "cap of \(SeasonPass.dailyXPCap) reached")
        XCTAssertEqual(p.xp, SeasonPass.dailyXPCap)
        XCTAssertEqual(p.xpLeftToday(today: day0), 0)
        XCTAssertEqual(p.award(.dailyGoal, today: day0 + 1), 10, "a new real day has a fresh cap")
        XCTAssertEqual(p.award(.milestone, today: day0 + 1, count: 5), 50, "a batch is trimmed to what is left")
    }

    func testPassCannotBeOutrunInASeason() {
        var p = SeasonPass(today: day0)
        var firstFull: Int?
        for d in 0..<SeasonPass.seasonDays {
            p.award(.milestone, today: day0 + d, count: 99)
            if firstFull == nil && p.isComplete { firstFull = d + 1 }
        }
        XCTAssertEqual(firstFull, SeasonPass.tierCount * SeasonPass.xpPerTier / SeasonPass.dailyXPCap)
        XCTAssertLessThan(firstFull ?? 999, SeasonPass.seasonDays)
        p.xp = SeasonPass.tierCount * SeasonPass.xpPerTier - 10
        XCTAssertEqual(p.award(.milestone, today: day0 + 100), 10, "xp stops at the top tier")
    }

    func testObserveAwardsFromPlay() {
        var p = SeasonPass(today: day0)
        let login: Int = PassMissions.loginXP
        XCTAssertEqual(p.observe(snap(), today: day0), login, "first look only sets the baseline and pays the day's login")
        XCTAssertEqual(p.observe(snap(week: 2), today: day0), 15, "a finished week")
        XCTAssertEqual(p.observe(snap(week: 2, months: 1), today: day0 + 1), login + 30, "a month closed in profit")
        XCTAssertEqual(p.observe(snap(week: 2, months: 1, goals: 1), today: day0 + 2), login + 50, "a milestone")
        XCTAssertEqual(p.observe(snap(week: 2, months: 1, goals: 1, daily: "2026-1-1"), today: day0 + 3), login + 10, "daily goal")
        XCTAssertEqual(p.observe(snap(week: 2, months: 1, goals: 1, daily: "2026-1-1"), today: day0 + 3), 0, "same facts pay nothing twice")
        var l = SeasonPass(today: day0)
        l.observe(snap(loans: 1), today: day0)
        XCTAssertEqual(l.observe(snap(loans: 0), today: day0), 40, "a loan repaid")
        var q = SeasonPass(today: day0)
        q.observe(snap(), today: day0)
        XCTAssertEqual(q.observe(snap(counters: ["decision": 2]), today: day0), 4 + 10, "two decisions pay a little and finish the daily decision mission")
        XCTAssertEqual(q.observe(snap(counters: ["decision": 3]), today: day0), 2, "a finished mission pays once")
    }

    func testCashStreakPaysEveryFourPositiveWeeks() {
        var p = SeasonPass(today: day0)
        p.observe(snap(week: 1), today: day0)
        var paid = 0
        for w in 2...5 { paid += p.observe(snap(week: w), today: day0 + w) }
        XCTAssertEqual(paid, 4 * (15 + PassMissions.loginXP) + 25)
        XCTAssertEqual(p.observe(snap(week: 6, cash: -5), today: day0 + 9), 15 + PassMissions.loginXP, "negative cash pays no streak and resets it")
        XCTAssertEqual(p.cashStreak, 0)
    }

    func testOtherGameOrEarlierWeekPaysNothing() {
        var p = SeasonPass(today: day0)
        p.observe(snap(seed: 1, week: 10), today: day0)
        XCTAssertEqual(p.observe(snap(seed: 2, week: 50, months: 9), today: day0), 0)
        XCTAssertEqual(p.observe(snap(seed: 2, week: 3, months: 9), today: day0), 0, "an older save")
        XCTAssertEqual(p.xp, PassMissions.loginXP, "only the day's login was paid")
    }

    func testClaimingRules() {
        var p = SeasonPass(today: day0)
        XCTAssertEqual(p.claim(.free, tier: 1, isPlus: false), .tierNotReached)
        p.xp = SeasonPass.xpPerTier * 3
        guard case .claimed(let r) = p.claim(.free, tier: 1, isPlus: false) else { return XCTFail("free tier 1 should claim") }
        XCTAssertEqual(r.id, "outfit.s1.pennant")
        XCTAssertEqual(p.claim(.free, tier: 1, isPlus: false), .alreadyClaimed)
        XCTAssertEqual(p.claim(.free, tier: 2, isPlus: false), .noReward)
        XCTAssertEqual(p.claim(.premium, tier: 1, isPlus: false), .needsPlus, "Pro-once and free players get the free track only")
        XCTAssertFalse(p.canClaim(.premium, tier: 1, isPlus: false))
        XCTAssertTrue(p.canClaim(.premium, tier: 1, isPlus: true))
        guard case .claimed = p.claim(.premium, tier: 1, isPlus: true) else { return XCTFail("premium should claim with Plus") }
        XCTAssertTrue(p.owned.contains("outfit.s1.moss"))
        XCTAssertNil(p.equipped["outfit"], "an outfit is collected and worn from the avatar editor, not equipped here")
        XCTAssertEqual(p.claimableCount(isPlus: true), 3)
        XCTAssertEqual(p.claimableCount(isPlus: false), 1)
        XCTAssertEqual(p.claimAll(isPlus: false).map(\.id), ["plate.ledger"])
        XCTAssertEqual(p.claimAll(isPlus: true).map(\.id), ["plate.walnut", "advisor.patience"])
    }

    func testRewardsAreCosmeticOrComfortAndUnique() {
        let ids = SeasonRewards.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(SeasonRewards.all.allSatisfy { (1...SeasonPass.tierCount).contains($0.tier) })
        var seen = Set<String>()
        for r in SeasonRewards.all { XCTAssertTrue(seen.insert("\(r.season)\(r.premium)\(r.tier)").inserted, "one reward per tier and track") }
        XCTAssertNotNil(SeasonRewards.reward(.free, tier: 30))
        XCTAssertNotNil(SeasonRewards.reward(.premium, tier: 30))
    }

    func testEquipAndBonusSlot() {
        var p = SeasonPass(today: day0)
        p.xp = SeasonPass.tierCount * SeasonPass.xpPerTier
        _ = p.claimAll(isPlus: true)
        XCTAssertEqual(p.bonusSaveSlots, 1)
        p.equip("plate.marble")
        XCTAssertEqual(p.equipped["namePlate"], "plate.marble")
        p.equip("outfit.s1.pennant")
        XCTAssertNil(p.equipped["outfit"], "an outfit is collected, then worn from the avatar editor")
        var q = SeasonPass(today: day0)
        q.equip("plate.marble")
        XCTAssertNil(q.equipped["namePlate"], "an unowned reward cannot be equipped")
    }

    func testSeasonRollover() {
        var p = SeasonPass(today: day0)
        p.xp = 300
        _ = p.claimAll(isPlus: true)
        let owned = p.owned
        XCTAssertFalse(p.rollover(today: day0 + SeasonPass.seasonDays - 1))
        XCTAssertEqual(p.daysLeft(today: day0 + SeasonPass.seasonDays - 1), 1)
        XCTAssertTrue(p.rollover(today: day0 + SeasonPass.seasonDays))
        XCTAssertEqual(p.seasonNumber, 2)
        XCTAssertEqual(p.xp, 0)
        XCTAssertTrue(p.claimed.isEmpty)
        XCTAssertEqual(p.owned, owned, "owned cosmetics survive the rollover")
        XCTAssertEqual(p.startDay, day0 + SeasonPass.seasonDays)
        XCTAssertTrue(p.rollover(today: day0 + SeasonPass.seasonDays * 4 + 3))
        XCTAssertEqual(p.seasonNumber, 5)
        var q = SeasonPass(today: day0)
        q.xp = 900
        q.observe(snap(), today: day0 + SeasonPass.seasonDays + 4)
        XCTAssertEqual(q.seasonNumber, 2)
        XCTAssertEqual(q.xp, PassMissions.loginXP, "the new season starts fresh with the day's login")
    }

    func testTheLastDaysWarnAboutRewardsThatWouldBeLost() {
        var p = SeasonPass(today: day0)
        XCTAssertNil(p.endingNote(today: day0 + 10, isPlus: false), "no warning early in the season")
        p.xp = 4 * SeasonPass.xpPerTier
        let late = day0 + SeasonPass.seasonDays - 3
        let waiting = p.endingNote(today: late, isPlus: false)
        XCTAssertTrue(waiting?.contains("waiting") == true && waiting?.contains("lost") == true, waiting ?? "")
        _ = p.claimAll(isPlus: false)
        let close = p.endingNote(today: late, isPlus: false)
        XCTAssertTrue(close?.contains("tier 4") == true && close?.contains("XP away") == true, close ?? "")
        XCTAssertEqual(p.xpToNextTier, SeasonPass.xpPerTier)
        p.xp = SeasonPass.tierCount * SeasonPass.xpPerTier
        _ = p.claimAll(isPlus: true)
        XCTAssertNil(p.endingNote(today: late, isPlus: true), "a finished pass has nothing to warn about")
    }

    func testRolloverRemembersWhatWasLeftUnclaimed() {
        var p = SeasonPass(today: day0)
        p.xp = 5 * SeasonPass.xpPerTier
        XCTAssertEqual(p.unclaimedFree, 2, "tiers 1 and 3 hold free rewards")
        XCTAssertNil(p.missedNote)
        XCTAssertTrue(p.rollover(today: day0 + SeasonPass.seasonDays))
        XCTAssertEqual(p.missedFree, 2)
        XCTAssertTrue(p.missedNote?.contains("2 free rewards") == true)
        XCTAssertEqual(p.unclaimedFree, 0)
    }

    func testCodableRoundTrip() throws {
        var p = SeasonPass(today: day0)
        p.xp = 700; p.observe(snap(), today: day0); p.claimed = ["f1"]; p.owned = ["outfit.s1.pennant"]
        let back = try JSONDecoder().decode(SeasonPass.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testOpeningCompaniesPaysNoXp() throws {
        var e = try ChainsTests.engine("UK")
        var p = SeasonPass(today: day0)
        p.observe(SeasonPass.snapshot(e.state), today: day0)
        for t in ["cafe", "barber", "gym"] { _ = ChainsTests.start(&e, t) }
        XCTAssertEqual(p.observe(SeasonPass.snapshot(e.state), today: day0), 0)
        XCTAssertEqual(p.xp, PassMissions.loginXP)
    }

    func testOldSavedBaselineStillDecodesAndPaysNothingForExistingMonths() throws {
        let old = #"{"seed":1,"week":4,"cash":10,"companies":3,"loans":0,"goals":0,"dailyDone":""}"#
        let b = try JSONDecoder().decode(SeasonPass.Snapshot.self, from: Data(old.utf8))
        XCTAssertEqual(b.profitMonths, SeasonPass.Snapshot.unknownMonths)
        var p = SeasonPass(today: day0)
        p.baseline = b
        XCTAssertEqual(p.observe(snap(seed: 1, week: 4, months: 5), today: day0), 0)
    }

    func testSnapshotFromGameState() throws {
        let e = try ChainsTests.engine("UK")
        let s = SeasonPass.snapshot(e.state)
        XCTAssertEqual(s.seed, e.state.seed)
        XCTAssertEqual(s.week, e.state.week)
        XCTAssertEqual(s.dailyDone, "")
    }
}
