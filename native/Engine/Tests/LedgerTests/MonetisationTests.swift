import XCTest
@testable import Simulation
import GameCore
import Finance

/// EntitlementGatesTests and AdPolicyTests (pure rules; StoreKit and the ad SDK live in the app).
final class EntitlementGatesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testEveryLockedItemIsLockedForFreeAndUnlockedForProFounderAndPlus() {
        let free = EntitlementSnapshot.free
        let pro = EntitlementSnapshot(owned: [.pro])
        let founder = EntitlementSnapshot(owned: [.founder])
        let plus = EntitlementSnapshot(owned: [.plusYearly], plusExpires: now.addingTimeInterval(86_400))
        XCTAssertEqual(LockedFeature.allCases.count, 8)
        for f in LockedFeature.allCases {
            XCTAssertFalse(free.isUnlocked(f, now: now), f.rawValue)
            for (name, e) in [("pro", pro), ("founder", founder), ("plus", plus)] { XCTAssertTrue(e.isUnlocked(f, now: now), "\(f.rawValue) \(name)") }
        }
        XCTAssertFalse(free.isPro(now: now)); XCTAssertTrue(founder.isFounder()); XCTAssertFalse(pro.isFounder()); XCTAssertTrue(plus.isPlus(now: now))
    }

    func testPlusRelocksWhenItExpiresButProStays() {
        let plus = EntitlementSnapshot(owned: [.plusMonthly], plusExpires: now.addingTimeInterval(100))
        let later = now.addingTimeInterval(101)
        for f in LockedFeature.allCases { XCTAssertTrue(plus.isUnlocked(f, now: now)); XCTAssertFalse(plus.isUnlocked(f, now: later), f.rawValue) }
        XCTAssertTrue(plus.isAdFree(now: now)); XCTAssertFalse(plus.isAdFree(now: later))
        var both = plus; both.owned.insert(.pro)
        for f in LockedFeature.allCases { XCTAssertTrue(both.isUnlocked(f, now: later), "a Pro owner keeps Pro after Plus ends") }
    }

    func testSaveSlots() {
        let pro = EntitlementSnapshot(owned: [.pro])
        XCTAssertEqual(EntitlementSnapshot.free.saveSlots(now: now), 1)
        XCTAssertEqual(pro.saveSlots(now: now), 3)
    }

    func testTheOneDayPassUnlocksThenRelocks() {
        var l = AdLedger()
        XCTAssertTrue(AdPolicy.canOfferPass(entitlements: .free, now: now, l))
        let e = AdPolicy.grantPass(.free, now: now, &l)
        XCTAssertTrue(e.isPro(now: now.addingTimeInterval(23 * 3600)))
        XCTAssertFalse(e.isPro(now: now.addingTimeInterval(24 * 3600 + 1)))
        XCTAssertFalse(AdPolicy.canOfferPass(entitlements: .free, now: now.addingTimeInterval(6 * 86_400), l), "once per 7 real days")
        XCTAssertTrue(AdPolicy.canOfferPass(entitlements: .free, now: now.addingTimeInterval(7 * 86_400 + 1), l))
        XCTAssertFalse(AdPolicy.canOfferPass(entitlements: EntitlementSnapshot(owned: [.pro]), now: now, AdLedger()))
    }

    func testFreeTradesAreTheStarterTwelveAndTheCheapOnes() {
        XCTAssertTrue(TradeAccess.isFree(tradeID: "cafe", startUpCost: 9e9, medianWage: 100))
        XCTAssertTrue(TradeAccess.isFree(tradeID: "hotel", startUpCost: 199, medianWage: 100))
        XCTAssertFalse(TradeAccess.isFree(tradeID: "hotel", startUpCost: 200, medianWage: 100))
        XCTAssertFalse(TradeAccess.isFree(tradeID: "hotel", startUpCost: nil, medianWage: 100))
        XCTAssertTrue(TradeAccess.isUnlocked(tradeID: "hotel", startUpCost: 5000, medianWage: 100, entitlements: EntitlementSnapshot(owned: [.pro]), now: now))
    }
}

final class AdPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A scripted 30-week game; each report is continued 7 real minutes after the last. Returns the weeks that showed an interstitial.
    private func script(m4Week: Int, weeks: Int = 30, minutesBetween: Double = 7, blocking: Set<Int> = [], e: EntitlementSnapshot = .free) -> [Int] {
        var l = AdLedger(), shown: [Int] = []
        for w in 1...weeks {
            let at = t0.addingTimeInterval(Double(w) * minutesBetween * 60)
            if l.rolled(at).sessionsToday < 2 { l.beginSession(now: at); l.beginSession(now: at) }   // never the first session of the day
            let c = AdPolicy.Context(reportWeek: w, m4Done: w >= m4Week, blockingInboxOpen: blocking.contains(w), now: t0.addingTimeInterval(Double(w) * minutesBetween * 60), entitlements: e)
            if AdPolicy.reportContinued(c, &l) { shown.append(w) }
        }
        return shown
    }

    func testThirtyWeekGameHasAtMostThirteenInterstitialsNeverEarlyNeverBackToBack() {
        let shown = script(m4Week: 1, minutesBetween: 1440)
        XCTAssertLessThanOrEqual(shown.count, 13)
        XCTAssertEqual(shown.count, 13)
        XCTAssertTrue(shown.allSatisfy { $0 >= 5 }, "never in weeks 1 to 4")
        for (a, b) in zip(shown, shown.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 2, "never two reports in a row") }
    }

    func testNeverBeforeM4() {
        let shown = script(m4Week: 12)
        XCTAssertFalse(shown.isEmpty)
        XCTAssertTrue(shown.allSatisfy { $0 >= 12 })
        XCTAssertLessThanOrEqual(script(m4Week: 31).count, 0)
    }

    func testSixRealMinutesAndBlockingInboxAndPaidPlayers() {
        let fast = script(m4Week: 1, minutesBetween: 2)
        for (a, b) in zip(fast, fast.dropFirst()) { XCTAssertGreaterThanOrEqual(Double(b - a) * 2, 6, "at most once per 6 real minutes") }
        XCTAssertFalse(script(m4Week: 1, blocking: [5]).contains(5), "no ad while a blocking item is open")
        XCTAssertTrue(script(m4Week: 1, e: EntitlementSnapshot(owned: [.pro])).isEmpty)
        XCTAssertTrue(script(m4Week: 1, e: EntitlementSnapshot(owned: [.founder])).isEmpty)
        XCTAssertTrue(script(m4Week: 1, e: EntitlementSnapshot(owned: [.plusYearly], plusExpires: t0.addingTimeInterval(1e9))).isEmpty)
    }

    func testRewardedDoubleRules() {
        var l = AdLedger()
        let now = t0
        XCTAssertFalse(AdPolicy.canOfferRewardedDouble(week: 5, grantCashThisWeek: 0, entitlements: .free, now: now, l))
        XCTAssertTrue(AdPolicy.canOfferRewardedDouble(week: 5, grantCashThisWeek: 3000, entitlements: .free, now: now, l))
        XCTAssertFalse(AdPolicy.canOfferRewardedDouble(week: 4, grantCashThisWeek: 3000, entitlements: .free, now: now, l), "not in the first four weeks")
        XCTAssertFalse(AdPolicy.canOfferRewardedDouble(week: 5, grantCashThisWeek: 3000, entitlements: .free, now: now, decisionOpen: true, l), "not during a decision")
        XCTAssertFalse(AdPolicy.canOfferRewardedDouble(week: 5, grantCashThisWeek: 3000, entitlements: EntitlementSnapshot(owned: [.pro]), now: now, l))
        l.lastRewardedGrantWeek = 5
        XCTAssertFalse(AdPolicy.canOfferRewardedDouble(week: 5, grantCashThisWeek: 3000, entitlements: .free, now: now, l))
        XCTAssertTrue(AdPolicy.canOfferRewardedDouble(week: 6, grantCashThisWeek: 3000, entitlements: .free, now: now, l))
        XCTAssertEqual(AdPolicy.rewardedDoubleAmount(grantCash: 3000, companyCash: 10_000), 3000)
        XCTAssertEqual(AdPolicy.rewardedDoubleAmount(grantCash: 25_000, companyCash: 10_000), 5000, "cap: the higher of 2% of cash and 5,000")
        XCTAssertEqual(AdPolicy.rewardedDoubleAmount(grantCash: 25_000, companyCash: 1_000_000), 20_000)
    }

    func testConsentAndTracking() {
        XCTAssertTrue(AdPolicy.requestNonPersonalised(consentGranted: false))
        XCTAssertFalse(AdPolicy.requestNonPersonalised(consentGranted: true))
    }
}

/// The ad caps: real-time marks survive a new save, daily limits, quiet hour, paid players never see an offer.
final class AdCapsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testNewSaveKeepsTheRealTimeMarksAndClearsTheWeekOnes() {
        var l = AdLedger()
        _ = AdPolicy.grantPass(.free, now: t0, &l)
        l.lastInterstitialWeek = 9; l.lastInterstitialAt = t0; l.lastReportWeek = 9; l.lastRewardedGrantWeek = 9; l.doubledGrantWeek = 9; l.secondChanceUsed = true
        l.beginSession(now: t0); l.doublesToday = 2
        l.resetForNewSave()
        XCTAssertEqual(l.lastPassAt, t0); XCTAssertEqual(l.lastInterstitialAt, t0); XCTAssertEqual(l.doublesToday, 2); XCTAssertEqual(l.sessionsToday, 1)
        XCTAssertNil(l.lastInterstitialWeek); XCTAssertNil(l.lastReportWeek); XCTAssertNil(l.lastRewardedGrantWeek); XCTAssertNil(l.doubledGrantWeek); XCTAssertFalse(l.secondChanceUsed)
        XCTAssertFalse(AdPolicy.canOfferPass(entitlements: .free, now: t0.addingTimeInterval(3600), l), "Retry or a new game does not re-offer the pass")
    }

    func testOldSavedLedgerStillDecodes() throws {
        let old = #"{"lastInterstitialWeek":6,"lastPassAt":1800000000}"#
        let l = try JSONDecoder().decode(AdLedger.self, from: Data(old.utf8))
        XCTAssertEqual(l.lastInterstitialWeek, 6); XCTAssertEqual(l.sessionsToday, 0); XCTAssertFalse(l.secondChanceUsed)
        let again = try JSONDecoder().decode(AdLedger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(again, l)
    }

    func testInterstitialDailyCapFirstSessionAndQuietHour() {
        var l = AdLedger()
        func ctx(_ w: Int, _ min: Double) -> AdPolicy.Context { AdPolicy.Context(reportWeek: w, m4Done: true, now: t0.addingTimeInterval(min * 60)) }
        l.beginSession(now: t0)
        XCTAssertFalse(AdPolicy.canShowInterstitial(ctx(5, 0), l), "none in the first session of a day")
        l.beginSession(now: t0)
        var shown = 0
        for i in 0..<10 { if AdPolicy.reportContinued(ctx(5 + 2 * i, Double(i) * 10), &l) { shown += 1 } }
        XCTAssertEqual(shown, 4, "at most four a day")
        var q = AdLedger(); q.beginSession(now: t0); q.beginSession(now: t0)
        XCTAssertTrue(AdPolicy.canShowInterstitial(ctx(5, 1), q))
        q.noteDeclined(now: t0)
        XCTAssertFalse(AdPolicy.canShowInterstitial(ctx(5, 59), q), "an hour without ads after a declined offer")
        XCTAssertFalse(AdPolicy.canOfferRewardedDouble(week: 6, grantCashThisWeek: 100, entitlements: .free, now: t0.addingTimeInterval(59 * 60), q))
        XCTAssertTrue(AdPolicy.canShowInterstitial(ctx(5, 61), q))
    }

    func testDoubleDailyCapAndPaidPlayersNeverSeeIt() {
        var l = AdLedger()
        for w in 5...7 { XCTAssertTrue(AdPolicy.canOfferRewardedDouble(week: w, grantCashThisWeek: 1, entitlements: .free, now: t0, l)); AdPolicy.recordDouble(week: w, now: t0, &l) }
        XCTAssertFalse(AdPolicy.canOfferRewardedDouble(week: 8, grantCashThisWeek: 1, entitlements: .free, now: t0, l), "three a real day")
        XCTAssertTrue(AdPolicy.canOfferRewardedDouble(week: 8, grantCashThisWeek: 1, entitlements: .free, now: t0.addingTimeInterval(86_400 * 2), l))
        let far = t0.addingTimeInterval(1e6)
        let paid: [EntitlementSnapshot] = [EntitlementSnapshot(owned: [.pro]), EntitlementSnapshot(owned: [.founder]),
            EntitlementSnapshot(plusExpires: far), EntitlementSnapshot(passExpires: far), EntitlementSnapshot(giftExpires: far)]
        for e in paid {
            XCTAssertFalse(AdPolicy.canOfferRewardedDouble(week: 9, grantCashThisWeek: 1, entitlements: e, now: t0, AdLedger()))
            XCTAssertFalse(AdPolicy.canOfferPass(entitlements: e, now: t0, AdLedger()), "no pass offer to anyone who already has the full game")
        }
    }

    func testGraceKeepsPlusOnUntilItEnds() {
        let e = EntitlementSnapshot(owned: [.plusMonthly], plusExpires: t0.addingTimeInterval(-86_400), plusGraceUntil: t0.addingTimeInterval(3600))
        XCTAssertTrue(e.isPlus(now: t0)); XCTAssertTrue(e.isPro(now: t0))
        XCTAssertFalse(e.isPlus(now: t0.addingTimeInterval(3601)))
    }

    func testEntitlementCacheKeepsPaidStateOfflineAndDropsOnlyOnAnswer() throws {
        let plus = EntitlementSnapshot(owned: [.plusYearly], plusExpires: t0.addingTimeInterval(1e6))
        let cached = StoredEntitlements(plus, verifiedAt: t0)
        XCTAssertEqual(try JSONDecoder().decode(StoredEntitlements.self, from: JSONEncoder().encode(cached)).snapshot, plus)
        let offline = EntitlementCache.resolve(fresh: .free, cached: cached, storeAnswered: false, now: t0)
        XCTAssertEqual(offline.snapshot, plus); XCTAssertFalse(offline.plusEnded); XCTAssertEqual(offline.stored, cached)
        let answered = EntitlementCache.resolve(fresh: .free, cached: cached, storeAnswered: true, now: t0)
        XCTAssertEqual(answered.snapshot, .free); XCTAssertTrue(answered.plusEnded); XCTAssertNil(answered.stored)
        let pro = EntitlementSnapshot(owned: [.pro])
        let kept = EntitlementCache.resolve(fresh: pro, cached: cached, storeAnswered: false, now: t0)
        XCTAssertEqual(kept.snapshot, pro); XCTAssertTrue(kept.plusEnded, "the store listed Pro without Plus")
        XCTAssertFalse(EntitlementCache.resolve(fresh: .free, cached: nil, storeAnswered: false, now: t0).plusEnded)
    }
}

/// Payouts of the rewarded ads post through the ledger: the books balance and the caps hold.
final class AdRewardsTests: XCTestCase {
    func testLabelsMatchTheLadderGrants() throws {
        var e = try ChainsTests.engine()
        _ = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        var seen: Set<String> = []
        e.update { s, _, _ in
            for id in ["M3", "M4", "M5", "M6", "M8", "M10"] {
                let before = s.statement.count
                _ = PlayerGoals.ladderReward(&s, id, cur)
                if s.statement.count > before { seen.insert(s.statement[0].label) }
            }
        }
        XCTAssertEqual(seen, AdRewards.grantLabels)
    }

    func testDoublePaysOnceCappedAndTheBooksBalance() throws {
        var e = try ChainsTests.engine()
        _ = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        e.update { s, _, _ in s.week = 6; _ = PlayerGoals.ladderReward(&s, "M6", cur) }   // the town grant
        let grant = cur.scaledPrice(25_000)
        var paid = 0.0
        let cashBefore = e.state.cash
        e.update { s, _, _ in
            XCTAssertEqual(AdRewards.grantCash(s, doubledThrough: nil), grant, accuracy: 1)
            paid = AdRewards.payDouble(&s, currency: cur, doubledThrough: nil)
        }
        let live = e.state.companies.filter { $0.status.isLive }.reduce(0.0) { $0 + $1.cash }
        XCTAssertEqual(paid, jsRound(min(grant, max(0.02 * live, cur.scaledPrice(5000)))), accuracy: 1)
        XCTAssertGreaterThan(paid, 0); XCTAssertLessThanOrEqual(paid, grant)
        XCTAssertEqual(e.state.cash - cashBefore, paid, accuracy: 0.5)
        XCTAssertEqual(e.state.statement[0].label, AdRewards.doubleLabel)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        e.update { s, _, _ in
            XCTAssertEqual(AdRewards.grantCash(s, doubledThrough: s.week), 0, "a doubled grant is not doubled again")
            XCTAssertEqual(AdRewards.payDouble(&s, currency: cur, doubledThrough: s.week), 0)
        }
    }

    func testSecondChanceReopensOnceWithABalancedStake() throws {
        var e = try ChainsTests.engine()
        _ = ChainsTests.start(&e, "cafe")
        let cur = e.homeCurrency
        e.update { s, _, _ in
            XCTAssertFalse(AdRewards.canSecondChance(s, currency: cur), "only after the books closed")
            s.week = 9; s.gameOver = .object(["reason": "broke", "week": 9, "nw": 0])
        }
        var l = AdLedger()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(AdPolicy.canOfferSecondChance(e.state, currency: cur, entitlements: .free, now: now, l))
        XCTAssertFalse(AdPolicy.canOfferSecondChance(e.state, currency: cur, entitlements: EntitlementSnapshot(owned: [.pro]), now: now, l))
        let before = e.state.cash
        e.update { s, _, _ in XCTAssertTrue(AdRewards.applySecondChance(&s, currency: cur)) }
        l.secondChanceUsed = true
        XCTAssertFalse(e.state.isGameOver)
        XCTAssertEqual(e.state.cash - before, AdRewards.secondChanceStake(cur), accuracy: 0.5)
        XCTAssertEqual(e.state.statement[0].label, AdRewards.secondChanceLabel)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        e.update { s, _, _ in s.gameOver = .object(["reason": "broke"]) }
        XCTAssertFalse(AdPolicy.canOfferSecondChance(e.state, currency: cur, entitlements: .free, now: now, l), "once per save")
        l.resetForNewSave()
        XCTAssertTrue(AdPolicy.canOfferSecondChance(e.state, currency: cur, entitlements: .free, now: now, l))
        e.update { s, _, _ in s.week = 3 }
        XCTAssertFalse(AdPolicy.canOfferSecondChance(e.state, currency: cur, entitlements: .free, now: now, l), "not in the first four weeks")
        e.update { s, _, _ in s.week = 9; s.cash = -s.overdraftLimit * 2 }
        XCTAssertFalse(AdRewards.canSecondChance(e.state, currency: cur), "a stake that cannot lift the overdraft is not sold")
    }
}
