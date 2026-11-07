import Foundation
import Countries

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

/// What a free player sees locked, with a key glyph and the words `Ledger Pro`.
public enum LockedFeature: String, CaseIterable, Sendable {
    case tradeAboveCostLine, expansionAbroad, groupLayer, ventures, luxuryGivingFootball, saveSlots, cloudBackup, playToEndOfWeek

    /// Needs a Plus subscription itself, not just Pro. Nothing in the 11.1 locked list is Plus-only.
    public var plusOnly: Bool { false }

    /// The line the paywall shows on top, when no specific item is named.
    public var paywallTitle: String {
        switch self {
        case .tradeAboveCostLine: return "Open any trade"
        case .expansionAbroad: return "Open a company abroad"
        case .groupLayer: return "Build a group"
        case .ventures: return "Ventures, private equity and funds"
        case .luxuryGivingFootball: return "Luxury, giving and football"
        case .saveSlots: return "More save slots"
        case .cloudBackup: return "Cloud backup"
        case .playToEndOfWeek: return "Play to end of week"
        }
    }
}

/// What the player owns right now. `isPro` is true for Pro, Founder, an active Plus, or a running one-day ad pass.
public struct EntitlementSnapshot: Equatable, Sendable {
    public var owned: Set<LedgerProduct>
    /// When the Plus period the store reported ends (nil: no Plus).
    public var plusExpires: Date?
    /// When the 24-hour Pro pass from a rewarded ad ends (nil: none).
    public var passExpires: Date?
    /// When a redeemed gift code stops opening the full game (nil: none).
    public var giftExpires: Date?

    public init(owned: Set<LedgerProduct> = [], plusExpires: Date? = nil, passExpires: Date? = nil, giftExpires: Date? = nil) {
        self.owned = owned; self.plusExpires = plusExpires; self.passExpires = passExpires; self.giftExpires = giftExpires
    }

    public static let free = EntitlementSnapshot()

    public func isFounder() -> Bool { owned.contains(.founder) }
    public func ownsPro() -> Bool { owned.contains(.pro) || owned.contains(.founder) }
    public func isPlus(now: Date) -> Bool { plusExpires.map { $0 > now } ?? false }
    public func hasPass(now: Date) -> Bool { passExpires.map { $0 > now } ?? false }
    /// Everything Pro unlocks: bought Pro or Founder, Plus while active, or the one-day pass.
    public func hasGift(now: Date) -> Bool { giftExpires.map { $0 > now } ?? false }
    public func isPro(now: Date) -> Bool { ownsPro() || isPlus(now: now) || hasPass(now: now) || hasGift(now: now) }
    /// Ads never show to Pro, Founder or Plus (a pass counts as Pro).
    public func isAdFree(now: Date) -> Bool { isPro(now: now) }

    public func isUnlocked(_ f: LockedFeature, now: Date) -> Bool { f.plusOnly ? isPlus(now: now) : isPro(now: now) }

    /// Free save slots: one; Pro and above three.
    public func saveSlots(now: Date) -> Int { isPro(now: now) ? 3 : 1 }

    /// `Play to end of week` is free for the first 12 weeks, Pro after. `week` is the game week now.
    public func canPlayToEndOfWeek(week: Int, now: Date) -> Bool { week <= 12 || isPro(now: now) }
}

/// Which trades a free player may start.
public enum TradeAccess {
    /// The twelve starter trades, or any trade whose start-up cost is below 2 x the country's median wage.
    public static func isFree(tradeID: String, startUpCost: Double?, medianWage: Double) -> Bool {
        if GameEngine.starterTradeIDs.contains(tradeID) { return true }
        guard let cost = startUpCost, medianWage > 0 else { return false }
        return cost < 2 * medianWage
    }
    public static func isUnlocked(tradeID: String, startUpCost: Double?, medianWage: Double, entitlements e: EntitlementSnapshot, now: Date) -> Bool {
        isFree(tradeID: tradeID, startUpCost: startUpCost, medianWage: medianWage) || e.isUnlocked(.tradeAboveCostLine, now: now)
    }
}

/// Where the ad rules stand. One value per save plus the real-time marks; the app stores it beside the save.
public struct AdLedger: Equatable, Sendable, Codable {
    public var lastInterstitialWeek: Int?
    public var lastInterstitialAt: Date?
    /// The report week of the last report that was continued (to refuse two reports in a row).
    public var lastReportWeek: Int?
    public var lastRewardedGrantWeek: Int?
    public var lastPassAt: Date?
    public init() {}
}

public enum AdPolicy {
    public static let minGameWeeksBetween = 2
    public static let minRealSecondsBetween: TimeInterval = 6 * 60
    public static let freeWeeksWithoutAds = 4
    public static let firstLadderGoalWithAds = 4
    public static let passDuration: TimeInterval = 24 * 3600
    public static let passCooldown: TimeInterval = 7 * 24 * 3600

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
    public static func canShowInterstitial(_ c: Context, _ l: AdLedger) -> Bool {
        if c.entitlements.isAdFree(now: c.now) { return false }
        if c.reportWeek <= freeWeeksWithoutAds || !c.m4Done || c.blockingInboxOpen { return false }
        if let last = l.lastReportWeek, c.reportWeek - last <= 1, l.lastInterstitialWeek == last { return false }   // never two reports in a row
        if let w = l.lastInterstitialWeek, c.reportWeek - w < minGameWeeksBetween { return false }
        if let t = l.lastInterstitialAt, c.now.timeIntervalSince(t) < minRealSecondsBetween { return false }
        return true
    }

    /// Call when a week report is continued. Returns true when an interstitial should show now (and records it).
    @discardableResult
    public static func reportContinued(_ c: Context, _ l: inout AdLedger) -> Bool {
        let show = canShowInterstitial(c, l)
        l.lastReportWeek = c.reportWeek
        if show { l.lastInterstitialWeek = c.reportWeek; l.lastInterstitialAt = c.now }
        return show
    }

    /// Placement 2: the optional `double this week's grant` button. Needs cash paid by a ladder reward or grant this week, once per game week, no purchase.
    public static func canOfferRewardedDouble(week: Int, grantCashThisWeek: Double, entitlements e: EntitlementSnapshot, now: Date, _ l: AdLedger) -> Bool {
        guard !e.isAdFree(now: now), grantCashThisWeek > 0 else { return false }
        return l.lastRewardedGrantWeek != week
    }

    /// The extra cash the rewarded ad pays: the grant again, capped at 2% of company cash or 5,000 local units, whichever is higher.
    public static func rewardedDoubleAmount(grantCash: Double, companyCash: Double, floorUnits: Double? = nil, currency: Currency? = nil) -> Double {
        let floor: Double = floorUnits ?? currency?.scaledPrice(5000) ?? 5000
        return max(0, min(grantCash, max(0.02 * max(0, companyCash), floor)))
    }

    /// Placement 3: `Try Pro for a day` in the paywall, at most once per 7 real days, never to someone who already has Pro.
    public static func canOfferPass(entitlements e: EntitlementSnapshot, now: Date, _ l: AdLedger) -> Bool {
        if e.ownsPro() || e.isPlus(now: now) || e.hasPass(now: now) { return false }
        if let t = l.lastPassAt, now.timeIntervalSince(t) < passCooldown { return false }
        return true
    }
    /// Records a watched pass ad and returns the entitlement with the pass running for 24 real hours.
    public static func grantPass(_ e: EntitlementSnapshot, now: Date, _ l: inout AdLedger) -> EntitlementSnapshot {
        l.lastPassAt = now
        var out = e; out.passExpires = now.addingTimeInterval(passDuration)
        return out
    }

    /// Consent: refused or not asked means non-personalised ads. ATT is asked once, after the first week report.
    public static func requestNonPersonalised(consentGranted: Bool) -> Bool { !consentGranted }
    public static func shouldAskTracking(reportWeek: Int, alreadyAsked: Bool) -> Bool { !alreadyAsked && reportWeek >= 1 }
}
