import XCTest
import GameCore
@testable import Simulation

/// Season Pass: tier math, the daily XP cap, claiming rules, XP from observed play and the real-date season rollover.
final class SeasonPassTests: XCTestCase {
    private let day0 = 20_000

    private func snap(seed: Int = 1, week: Int = 1, cash: Double = 100, companies: Int = 1, loans: Int = 0, goals: Int = 0, daily: String = "") -> SeasonPass.Snapshot {
        SeasonPass.Snapshot(seed: seed, week: week, cash: cash, companies: companies, loans: loans, goals: goals, dailyDone: daily)
    }

    func testTierMath() {
        XCTAssertEqual(SeasonPass.tier(forXP: 0), 0)
        XCTAssertEqual(SeasonPass.tier(forXP: 149), 0)
        XCTAssertEqual(SeasonPass.tier(forXP: 150), 1)
        XCTAssertEqual(SeasonPass.tier(forXP: 4_499), 29)
        XCTAssertEqual(SeasonPass.tier(forXP: 4_500), 30)
        XCTAssertEqual(SeasonPass.tier(forXP: 99_999), 30)
        var p = SeasonPass(today: day0)
        p.xp = 200
        XCTAssertEqual(p.tier, 1)
        XCTAssertEqual(p.xpIntoTier, 50)
        XCTAssertEqual(p.progressText, "Tier 1 of 30. 50 of 150 XP to tier 2")
        p.xp = 4_500
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.tierProgress, 1)
    }

    func testDailyCapAndNewDay() {
        var p = SeasonPass(today: day0)
        XCTAssertEqual(p.award(.milestone, today: day0), 50)
        XCTAssertEqual(p.award(.milestone, today: day0), 50)
        XCTAssertEqual(p.award(.milestone, today: day0), 0, "cap of \(SeasonPass.dailyXPCap) reached")
        XCTAssertEqual(p.xp, 100)
        XCTAssertEqual(p.xpLeftToday(today: day0), 0)
        XCTAssertEqual(p.award(.dailyGoal, today: day0 + 1), 30, "a new real day has a fresh cap")
        XCTAssertEqual(p.award(.milestone, today: day0 + 1, count: 5), 70, "a batch is trimmed to what is left")
    }

    func testPassCannotBeOutrunInASeason() {
        var p = SeasonPass(today: day0)
        var firstFull: Int?
        for d in 0..<SeasonPass.seasonDays {
            p.award(.milestone, today: day0 + d, count: 99)
            if firstFull == nil && p.isComplete { firstFull = d + 1 }
        }
        // Even at the daily cap every day, the top tier takes 45 days.
        XCTAssertEqual(firstFull, 45)
        p.xp = SeasonPass.tierCount * SeasonPass.xpPerTier - 10
        XCTAssertEqual(p.award(.milestone, today: day0 + 100), 10, "xp stops at the top tier")
    }

    func testObserveAwardsFromPlay() {
        var p = SeasonPass(today: day0)
        XCTAssertEqual(p.observe(snap(), today: day0), 0, "first look only sets the baseline")
        XCTAssertEqual(p.observe(snap(week: 2), today: day0), 20, "a finished week")
        XCTAssertEqual(p.observe(snap(week: 2, companies: 2), today: day0 + 1), 40, "a company opened")
        XCTAssertEqual(p.observe(snap(week: 2, companies: 2, goals: 1), today: day0 + 2), 50, "a milestone")
        XCTAssertEqual(p.observe(snap(week: 2, companies: 2, goals: 1, daily: "2026-1-1"), today: day0 + 3), 30, "daily goal")
        XCTAssertEqual(p.observe(snap(week: 2, companies: 2, goals: 1, daily: "2026-1-1"), today: day0 + 3), 0, "same facts pay nothing twice")
        var l = SeasonPass(today: day0)
        l.observe(snap(loans: 1), today: day0)
        XCTAssertEqual(l.observe(snap(loans: 0), today: day0), 40, "a loan repaid")
    }

    func testCashStreakPaysEveryFourPositiveWeeks() {
        var p = SeasonPass(today: day0)
        p.observe(snap(week: 1), today: day0)
        var paid = 0
        for w in 2...5 { paid += p.observe(snap(week: w), today: day0 + w) }
        XCTAssertEqual(paid, 4 * 20 + 25)
        XCTAssertEqual(p.observe(snap(week: 6, cash: -5), today: day0 + 9), 20, "negative cash pays no streak and resets it")
        XCTAssertEqual(p.cashStreak, 0)
    }

    func testOtherGameOrEarlierWeekPaysNothing() {
        var p = SeasonPass(today: day0)
        p.observe(snap(seed: 1, week: 10), today: day0)
        XCTAssertEqual(p.observe(snap(seed: 2, week: 50, companies: 9), today: day0), 0)
        XCTAssertEqual(p.observe(snap(seed: 2, week: 3, companies: 9), today: day0), 0, "an older save")
        XCTAssertEqual(p.xp, 0)
    }

    func testClaimingRules() {
        var p = SeasonPass(today: day0)
        XCTAssertEqual(p.claim(.free, tier: 1, isPlus: false), .tierNotReached)
        p.xp = 150 * 3
        guard case .claimed(let r) = p.claim(.free, tier: 1, isPlus: false) else { return XCTFail("free tier 1 should claim") }
        XCTAssertEqual(r.id, "badge.s1.first")
        XCTAssertEqual(p.claim(.free, tier: 1, isPlus: false), .alreadyClaimed)
        XCTAssertEqual(p.claim(.free, tier: 2, isPlus: false), .noReward)
        XCTAssertEqual(p.claim(.premium, tier: 1, isPlus: false), .needsPlus, "Pro-once and free players get the free track only")
        XCTAssertFalse(p.canClaim(.premium, tier: 1, isPlus: false))
        XCTAssertTrue(p.canClaim(.premium, tier: 1, isPlus: true))
        guard case .claimed = p.claim(.premium, tier: 1, isPlus: true) else { return XCTFail("premium should claim with Plus") }
        XCTAssertTrue(p.owned.contains("theme.moss"))
        XCTAssertEqual(p.equipped["theme"], "theme.moss", "the first of a kind is equipped")
        // Everything open at tier 3: free tier 3, premium tiers 2 and 3.
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
        for r in SeasonRewards.all { XCTAssertTrue(seen.insert("\(r.premium)\(r.tier)").inserted, "one reward per tier and track") }
        // The finisher of each track sits on the last tier.
        XCTAssertNotNil(SeasonRewards.reward(.free, tier: 30))
        XCTAssertNotNil(SeasonRewards.reward(.premium, tier: 30))
    }

    func testEquipAndBonusSlot() {
        var p = SeasonPass(today: day0)
        p.xp = 4_500
        _ = p.claimAll(isPlus: true)
        XCTAssertEqual(p.bonusSaveSlots, 1)
        p.equip("theme.ocean")
        XCTAssertEqual(p.equipped["theme"], "theme.ocean")
        p.equip("badge.s1.first")
        XCTAssertNil(p.equipped["badge"], "a badge is collected, not equipped")
        var q = SeasonPass(today: day0)
        q.equip("theme.ocean")
        XCTAssertNil(q.equipped["theme"], "an unowned reward cannot be equipped")
    }

    func testSeasonRollover() {
        var p = SeasonPass(today: day0)
        p.xp = 300
        _ = p.claimAll(isPlus: true)
        let owned = p.owned
        XCTAssertFalse(p.rollover(today: day0 + 55))
        XCTAssertEqual(p.daysLeft(today: day0 + 55), 1)
        XCTAssertTrue(p.rollover(today: day0 + 56))
        XCTAssertEqual(p.seasonNumber, 2)
        XCTAssertEqual(p.xp, 0)
        XCTAssertTrue(p.claimed.isEmpty)
        XCTAssertEqual(p.owned, owned, "owned cosmetics survive the rollover")
        XCTAssertEqual(p.startDay, day0 + 56)
        // A long absence lands in the right season, not the next one.
        XCTAssertTrue(p.rollover(today: day0 + 56 * 4 + 3))
        XCTAssertEqual(p.seasonNumber, 5)
        // Observing rolls the season over too.
        var q = SeasonPass(today: day0)
        q.xp = 900
        q.observe(snap(), today: day0 + 60)
        XCTAssertEqual(q.seasonNumber, 2)
        XCTAssertEqual(q.xp, 0)
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
        XCTAssertEqual(p.unclaimedFree, 4, "tiers 1, 3, 4 and 5 hold free rewards")
        XCTAssertNil(p.missedNote)
        XCTAssertTrue(p.rollover(today: day0 + SeasonPass.seasonDays))
        XCTAssertEqual(p.missedFree, 4)
        XCTAssertTrue(p.missedNote?.contains("4 free rewards") == true)
        XCTAssertEqual(p.unclaimedFree, 0)
    }

    func testCodableRoundTrip() throws {
        var p = SeasonPass(today: day0)
        p.xp = 700; p.observe(snap(), today: day0); p.claimed = ["f1"]; p.owned = ["badge.s1.first"]
        let back = try JSONDecoder().decode(SeasonPass.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testSnapshotFromGameState() throws {
        let e = try ChainsTests.engine("UK")
        let s = SeasonPass.snapshot(e.state)
        XCTAssertEqual(s.seed, e.state.seed)
        XCTAssertEqual(s.week, e.state.week)
        XCTAssertEqual(s.dailyDone, "")
    }
}
