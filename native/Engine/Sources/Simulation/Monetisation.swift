import Foundation
import GameCore
import Countries
import Finance

// The rules of what a purchase unlocks and when an ad may show. Pure values, no StoreKit and no ad SDK, so the rules are
// testable on Linux. The app (Core/Entitlements, Core/Ads) feeds these with the store's answers and reads only their results.
// No purchase changes a sim number: these types gate content and comfort only.

/// The five store products. Ids are fixed; prices are never stored here (always StoreKit `displayPrice`).
public enum LedgerProduct: String, CaseIterable, Sendable {
    case pro = "com.ledger.pro"
    case founder = "com.ledger.founder"
    case plusMonthly = "com.ledger.plus.monthly"
    case plusYearly = "com.ledger.plus.yearly"

    public static let plusGroupID = "plus"
    public var isPlus: Bool { self == .plusMonthly || self == .plusYearly }
}

public enum LockedFeature: String, CaseIterable, Sendable {
    case saveSlots, cloudBackup

    public var plusOnly: Bool { false }

    public var paywallTitle: String {
        switch self {
        case .saveSlots: return "More save slots"
        case .cloudBackup: return "Cloud backup"
        }
    }
}

/// What the player owns right now. `isPro` is true for Pro, Founder, an active Plus, or a running one-day ad pass.
public struct EntitlementSnapshot: Equatable, Sendable {
    public var owned: Set<LedgerProduct>
    /// When the Plus period the store reported ends (nil: no Plus).
    public var plusExpires: Date?
    /// While Apple reports the subscription in its grace or billing-retry period: Plus stays on until then (nil: not in grace).
    public var plusGraceUntil: Date?
    /// When the 24-hour Pro pass from a rewarded ad ends (nil: none).
    public var passExpires: Date?

    public init(owned: Set<LedgerProduct> = [], plusExpires: Date? = nil, plusGraceUntil: Date? = nil, passExpires: Date? = nil) {
        self.owned = owned; self.plusExpires = plusExpires; self.plusGraceUntil = plusGraceUntil; self.passExpires = passExpires
    }

    public static let free = EntitlementSnapshot()

    public func isFounder() -> Bool { owned.contains(.founder) }
    public func ownsPro() -> Bool { owned.contains(.pro) || owned.contains(.founder) }
    public func isPlus(now: Date) -> Bool { (plusExpires.map { $0 > now } ?? false) || (plusGraceUntil.map { $0 > now } ?? false) }
    public func hasPass(now: Date) -> Bool { passExpires.map { $0 > now } ?? false }
    /// Everything Pro unlocks: bought Pro or Founder, Plus while active, or the one-day pass.
    public func isPro(now: Date) -> Bool { ownsPro() || isPlus(now: now) || hasPass(now: now) }
    /// Ads never show to Pro, Founder or Plus (a pass counts as Pro).
    public func isAdFree(now: Date) -> Bool { isPro(now: now) }

    public func isUnlocked(_ f: LockedFeature, now: Date) -> Bool { f.plusOnly ? isPlus(now: now) : isPro(now: now) }

    public func saveSlots(now: Date) -> Int { isPro(now: now) ? 3 : 1 }
}

/// What the store last confirmed, kept on the device so a cold start or an offline launch keeps what was paid for.
public struct StoredEntitlements: Codable, Equatable, Sendable {
    public var owned: [String]
    public var plusExpires: Date?
    public var plusGraceUntil: Date?
    public var verifiedAt: Date

    public init(_ s: EntitlementSnapshot, verifiedAt: Date) {
        owned = s.owned.map { $0.rawValue }.sorted(); plusExpires = s.plusExpires; plusGraceUntil = s.plusGraceUntil; self.verifiedAt = verifiedAt
    }
    /// The store-owned part of the snapshot (the pass is kept separately).
    public var snapshot: EntitlementSnapshot {
        EntitlementSnapshot(owned: Set(owned.compactMap { LedgerProduct(rawValue: $0) }), plusExpires: plusExpires, plusGraceUntil: plusGraceUntil)
    }
}

/// Decides between what the store just said and the last confirmed snapshot. An empty answer is only believed when the store really
/// answered; offline it says nothing, and a paying player must not be locked out or told Plus ended.
public enum EntitlementCache {
    public struct Outcome: Equatable, Sendable {
        public var snapshot: EntitlementSnapshot
        /// What to keep on the device (nil: remove it).
        public var stored: StoredEntitlements?
        /// True only when the store answered and Plus is gone.
        public var plusEnded: Bool
    }

    public static func resolve(fresh: EntitlementSnapshot, cached: StoredEntitlements?, storeAnswered: Bool, now: Date) -> Outcome {
        let empty: Bool = fresh.owned.isEmpty && fresh.plusExpires == nil && fresh.plusGraceUntil == nil
        if empty && !storeAnswered, let c = cached { return Outcome(snapshot: c.snapshot, stored: c, plusEnded: false) }
        let hadPlus: Bool = cached.map { $0.plusExpires != nil || $0.plusGraceUntil != nil } ?? false
        let hasPlus: Bool = fresh.plusExpires != nil || fresh.plusGraceUntil != nil
        return Outcome(snapshot: fresh, stored: empty ? nil : StoredEntitlements(fresh, verifiedAt: now), plusEnded: hadPlus && !hasPlus)
    }
}

/// Where the ad rules stand. One value per save plus the real-time marks; the app stores it beside the save.
public struct AdLedger: Equatable, Sendable, Codable {
    // Per save: game weeks restart with a new game, so these are cleared by `resetForNewSave`.
    public var lastInterstitialWeek: Int?
    /// The report week of the last report that was continued (to refuse two reports in a row).
    public var lastReportWeek: Int?
    public var lastRewardedGrantWeek: Int?
    /// The newest statement week whose grants were already doubled.
    public var doubledGrantWeek: Int?
    public var secondChanceUsed: Bool = false
    // Real time: kept across saves, so a new game or Retry cannot reset a cap.
    public var lastInterstitialAt: Date?
    public var lastPassAt: Date?
    /// When the player last turned a rewarded ad down or closed it early.
    public var lastDeclinedAt: Date?
    /// The real calendar day the three counters below belong to.
    public var dayIndex: Int?
    public var sessionsToday: Int = 0
    public var interstitialsToday: Int = 0
    public var doublesToday: Int = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastInterstitialWeek = try c.decodeIfPresent(Int.self, forKey: .lastInterstitialWeek)
        lastReportWeek = try c.decodeIfPresent(Int.self, forKey: .lastReportWeek)
        lastRewardedGrantWeek = try c.decodeIfPresent(Int.self, forKey: .lastRewardedGrantWeek)
        doubledGrantWeek = try c.decodeIfPresent(Int.self, forKey: .doubledGrantWeek)
        secondChanceUsed = try c.decodeIfPresent(Bool.self, forKey: .secondChanceUsed) ?? false
        lastInterstitialAt = try c.decodeIfPresent(Date.self, forKey: .lastInterstitialAt)
        lastPassAt = try c.decodeIfPresent(Date.self, forKey: .lastPassAt)
        lastDeclinedAt = try c.decodeIfPresent(Date.self, forKey: .lastDeclinedAt)
        dayIndex = try c.decodeIfPresent(Int.self, forKey: .dayIndex)
        sessionsToday = try c.decodeIfPresent(Int.self, forKey: .sessionsToday) ?? 0
        interstitialsToday = try c.decodeIfPresent(Int.self, forKey: .interstitialsToday) ?? 0
        doublesToday = try c.decodeIfPresent(Int.self, forKey: .doublesToday) ?? 0
    }

    public static func dayIndex(_ d: Date) -> Int { Calendar.current.ordinality(of: .day, in: .era, for: d) ?? 0 }

    /// The ledger with the daily counters zeroed when `now` is a new real day.
    public func rolled(_ now: Date) -> AdLedger {
        var l = self
        let d = Self.dayIndex(now)
        if l.dayIndex != d { l.dayIndex = d; l.sessionsToday = 0; l.interstitialsToday = 0; l.doublesToday = 0 }
        return l
    }

    /// One app launch. The first of a real day shows no interstitial.
    public mutating func beginSession(now: Date) { self = rolled(now); sessionsToday += 1 }

    /// A new save starts its own week count: only the week-based marks go. Real-time marks stay so a new game cannot re-offer the pass or skip a cap.
    public mutating func resetForNewSave() {
        lastInterstitialWeek = nil; lastReportWeek = nil; lastRewardedGrantWeek = nil; doubledGrantWeek = nil; secondChanceUsed = false
    }

    /// An interstitial that was counted but never showed gives its slot back.
    public mutating func refundInterstitial() {
        lastInterstitialWeek = nil; lastInterstitialAt = nil; interstitialsToday = max(0, interstitialsToday - 1)
    }

    public mutating func noteDeclined(now: Date) { lastDeclinedAt = now }

    /// True for an hour after the player declined a rewarded offer (also when the clock was set back).
    public func isQuiet(now: Date) -> Bool { lastDeclinedAt.map { now.timeIntervalSince($0) < AdPolicy.declineQuiet } ?? false }
}

/// Rules for ads and the rewarded offers. Free players only: `isAdFree` is true for Pro, Founder, Plus, and a running pass.
public enum AdPolicy {
    public static let minGameWeeksBetween = 2
    public static let minRealSecondsBetween: TimeInterval = 6 * 60
    public static let freeWeeksWithoutAds = 4
    public static let firstLadderGoalWithAds = 4
    public static let passDuration: TimeInterval = 24 * 3600
    public static let passCooldown: TimeInterval = 7 * 24 * 3600
    public static let interstitialsPerDay = 4
    public static let doublesPerDay = 3
    public static let declineQuiet: TimeInterval = 3600

    public struct Context: Sendable {
        public var reportWeek: Int            // the week number of the report just read (1 = first)
        public var m4Done: Bool
        public var blockingInboxOpen: Bool
        public var now: Date
        public var entitlements: EntitlementSnapshot
        public init(reportWeek: Int, m4Done: Bool, blockingInboxOpen: Bool = false, now: Date, entitlements: EntitlementSnapshot = .free) {
            self.reportWeek = reportWeek; self.m4Done = m4Done; self.blockingInboxOpen = blockingInboxOpen; self.now = now; self.entitlements = entitlements
        }
    }

    /// Placement 1: the interstitial when `Continue` is tapped on a week report. Never on Next day (there is no API for it here).
    public static func canShowInterstitial(_ c: Context, _ ledger: AdLedger) -> Bool {
        if c.entitlements.isAdFree(now: c.now) { return false }
        if c.reportWeek <= freeWeeksWithoutAds || !c.m4Done || c.blockingInboxOpen { return false }
        let l = ledger.rolled(c.now)
        if l.sessionsToday < 2 || l.interstitialsToday >= interstitialsPerDay || l.isQuiet(now: c.now) { return false }
        if let last = l.lastReportWeek, c.reportWeek - last <= 1, l.lastInterstitialWeek == last { return false }   // never two reports in a row
        if let w = l.lastInterstitialWeek, c.reportWeek - w < minGameWeeksBetween { return false }
        if let t = l.lastInterstitialAt, c.now.timeIntervalSince(t) < minRealSecondsBetween { return false }
        return true
    }

    /// Call when a week report is continued. Returns true when an interstitial should show now (and records it).
    @discardableResult
    public static func reportContinued(_ c: Context, _ l: inout AdLedger) -> Bool {
        let show = canShowInterstitial(c, l)
        l = l.rolled(c.now)
        l.lastReportWeek = c.reportWeek
        if show { l.lastInterstitialWeek = c.reportWeek; l.lastInterstitialAt = c.now; l.interstitialsToday += 1 }
        return show
    }

    /// Placement 2: the optional `double this week's grant` button. Needs cash paid by a ladder reward or grant this week, once per game week
    /// and three times per real day, never in the first four weeks or while a decision is open.
    public static func canOfferRewardedDouble(week: Int, grantCashThisWeek: Double, entitlements e: EntitlementSnapshot, now: Date, decisionOpen: Bool = false, _ ledger: AdLedger) -> Bool {
        guard !e.isAdFree(now: now), grantCashThisWeek > 0, week > freeWeeksWithoutAds, !decisionOpen else { return false }
        let l = ledger.rolled(now)
        return l.lastRewardedGrantWeek != week && l.doublesToday < doublesPerDay && !l.isQuiet(now: now)
    }

    /// Records a doubled grant: one per game week, counted for the day.
    public static func recordDouble(week: Int, now: Date, _ l: inout AdLedger) {
        l = l.rolled(now); l.lastRewardedGrantWeek = week; l.doublesToday += 1
    }

    /// The extra cash the rewarded ad pays: the grant again, capped at 2% of company cash or 5,000 local units, whichever is higher.
    public static func rewardedDoubleAmount(grantCash: Double, companyCash: Double, floorUnits: Double? = nil, currency: Currency? = nil) -> Double {
        let floor: Double = floorUnits ?? currency?.scaledPrice(5000) ?? 5000
        return max(0, min(grantCash, max(0.02 * max(0, companyCash), floor)))
    }

    /// The second chance after the books close: once per save, free players, never in the first four weeks, and only when the stake can really restart the game.
    public static func canOfferSecondChance(_ s: GameState, currency: Currency, entitlements e: EntitlementSnapshot, now: Date, _ ledger: AdLedger) -> Bool {
        guard !e.isAdFree(now: now), !ledger.secondChanceUsed, s.week > freeWeeksWithoutAds, !ledger.isQuiet(now: now) else { return false }
        return AdRewards.canSecondChance(s, currency: currency)
    }

    /// Placement 3: `Try Pro for a day` in the paywall, at most once per 7 real days, never to anyone who already has Pro, Plus or a running pass.
    public static func canOfferPass(entitlements e: EntitlementSnapshot, now: Date, _ l: AdLedger) -> Bool {
        if e.isAdFree(now: now) { return false }
        if let t = l.lastPassAt, now.timeIntervalSince(t) < passCooldown { return false }
        return true
    }
    /// Records a watched pass ad and returns the entitlement with the pass running for 24 real hours.
    public static func grantPass(_ e: EntitlementSnapshot, now: Date, _ l: inout AdLedger) -> EntitlementSnapshot {
        l.lastPassAt = now
        var out = e; out.passExpires = now.addingTimeInterval(passDuration)
        return out
    }

    /// Consent: refused or not asked means non-personalised ads. The app asks (UMP, then ATT) right before the first ad is shown.
    public static func requestNonPersonalised(consentGranted: Bool) -> Bool { !consentGranted }
}

/// What the rewarded ads pay. Every payout is one `Ledger.move` on the player's account with its own line on the statement, so the books balance.
public enum AdRewards {
    /// The statement lines of the ladder's cash grants (`PlayerGoals.ladderReward`); a test keeps this list equal to that code.
    static let grantLabels: Set<String> = [
        "Job centre: first hire", "Accountant: first month free", "Ad agency: first week refunded",
        "Start-up grant from the town", "Recruitment agency: fee waived", "Insurance: first premium free",
    ]
    public static let doubleLabel = "Ad reward: this week's grant doubled"
    public static let secondChanceLabel = "Second chance: a fresh stake"

    /// Grant cash paid this week or last that has not been doubled yet.
    public static func grantCash(_ s: GameState, doubledThrough: Int?) -> Double {
        let from: Int = max(s.week - 1, (doubledThrough ?? -1) + 1)
        return s.statement.reduce(0) { (sum: Double, l: StatementLine) -> Double in
            l.week >= from && l.amount > 0 && grantLabels.contains(l.label) ? sum + l.amount : sum
        }
    }

    /// The cash a doubled grant would add now, after the cap.
    public static func doubleExtra(_ s: GameState, currency: Currency, doubledThrough: Int?) -> Double {
        let live: Double = s.companies.filter { $0.status.isLive }.reduce(0) { $0 + $1.cash }
        return jsRound(AdPolicy.rewardedDoubleAmount(grantCash: grantCash(s, doubledThrough: doubledThrough), companyCash: live, currency: currency))
    }

    /// Pays the doubled grant. Returns the amount paid (0: nothing to double).
    @discardableResult
    public static func payDouble(_ s: inout GameState, currency: Currency, doubledThrough: Int?) -> Double {
        let amount: Double = doubleExtra(s, currency: currency, doubledThrough: doubledThrough)
        guard amount > 0 else { return 0 }
        Ledger.move(&s, .me, amount, why: doubleLabel)
        return amount
    }

    public static func secondChanceStake(_ currency: Currency) -> Double { currency.scaledPrice(10_000) }

    /// Offered only when the game is over and the stake alone lifts the account out of what ended it (the overdraft or an empty purse).
    public static func canSecondChance(_ s: GameState, currency: Currency) -> Bool {
        s.isGameOver && s.cash + secondChanceStake(currency) >= -s.overdraftLimit && Payments.liquid(s) >= 0
    }

    /// Reopens the game with a fresh stake and a cleared overdraft count. Returns false when it does not apply.
    @discardableResult
    public static func applySecondChance(_ s: inout GameState, currency: Currency) -> Bool {
        guard canSecondChance(s, currency: currency) else { return false }
        s.gameOver = .null
        var flags = s.rest["flags"] ?? .object([:])
        flags["od"] = .number(0)
        s.rest["flags"] = flags
        Ledger.move(&s, .me, secondChanceStake(currency), why: secondChanceLabel)
        return true
    }
}
