import XCTest
import Simulation

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
            let c = AdPolicy.Context(reportWeek: w, m4Done: w >= m4Week, blockingInboxOpen: blocking.contains(w), now: t0.addingTimeInterval(Double(w) * minutesBetween * 60), entitlements: e)
            if AdPolicy.reportContinued(c, &l) { shown.append(w) }
        }
        return shown
    }

    func testThirtyWeekGameHasAtMostThirteenInterstitialsNeverEarlyNeverBackToBack() {
        let shown = script(m4Week: 1)
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
        XCTAssertFalse(AdPolicy.shouldAskTracking(reportWeek: 0, alreadyAsked: false))
        XCTAssertTrue(AdPolicy.shouldAskTracking(reportWeek: 1, alreadyAsked: false))
        XCTAssertFalse(AdPolicy.shouldAskTracking(reportWeek: 2, alreadyAsked: true))
    }
}
