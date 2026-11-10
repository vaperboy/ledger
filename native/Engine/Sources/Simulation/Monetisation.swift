import Foundation
import GameCore
import Countries
import Finance

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

public struct EntitlementSnapshot: Equatable, Sendable {
    public var owned: Set<LedgerProduct>
    public var plusExpires: Date?
    public var plusGraceUntil: Date?
    public var passExpires: Date?

    public init(owned: Set<LedgerProduct> = [], plusExpires: Date? = nil, plusGraceUntil: Date? = nil, passExpires: Date? = nil) {
        self.owned = owned; self.plusExpires = plusExpires; self.plusGraceUntil = plusGraceUntil; self.passExpires = passExpires
    }

    public static let free = EntitlementSnapshot()

    public func isFounder() -> Bool { owned.contains(.founder) }
    public func ownsPro() -> Bool { owned.contains(.pro) || owned.contains(.founder) }
    public func isPlus(now: Date) -> Bool { (plusExpires.map { $0 > now } ?? false) || (plusGraceUntil.map { $0 > now } ?? false) }
    public func hasPass(now: Date) -> Bool { passExpires.map { $0 > now } ?? false }
    public func isPro(now: Date) -> Bool { ownsPro() || isPlus(now: now) || hasPass(now: now) }
    public func isAdFree(now: Date) -> Bool { isPro(now: now) }

    public func isUnlocked(_ f: LockedFeature, now: Date) -> Bool { f.plusOnly ? isPlus(now: now) : isPro(now: now) }

    public func saveSlots(now: Date) -> Int { isPro(now: now) ? 3 : 1 }
}

public struct StoredEntitlements: Codable, Equatable, Sendable {
    public var owned: [String]
    public var plusExpires: Date?
    public var plusGraceUntil: Date?
    public var verifiedAt: Date

    public init(_ s: EntitlementSnapshot, verifiedAt: Date) {
        owned = s.owned.map { $0.rawValue }.sorted(); plusExpires = s.plusExpires; plusGraceUntil = s.plusGraceUntil; self.verifiedAt = verifiedAt
    }
    public var snapshot: EntitlementSnapshot {
        EntitlementSnapshot(owned: Set(owned.compactMap { LedgerProduct(rawValue: $0) }), plusExpires: plusExpires, plusGraceUntil: plusGraceUntil)
    }
}

public enum EntitlementCache {
    public struct Outcome: Equatable, Sendable {
        public var snapshot: EntitlementSnapshot
        public var stored: StoredEntitlements?
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

public struct AdLedger: Equatable, Sendable, Codable {
    public var lastInterstitialWeek: Int?
    public var lastReportWeek: Int?
    public var lastRewardedGrantWeek: Int?
    public var doubledGrantWeek: Int?
    public var secondChanceUsed: Bool = false
    public var lastInterstitialAt: Date?
    public var lastPassAt: Date?
    public var lastDeclinedAt: Date?
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

    public func rolled(_ now: Date) -> AdLedger {
        var l = self
        let d = Self.dayIndex(now)
        if l.dayIndex != d { l.dayIndex = d; l.sessionsToday = 0; l.interstitialsToday = 0; l.doublesToday = 0 }
        return l
    }

    public mutating func beginSession(now: Date) { self = rolled(now); sessionsToday += 1 }

    public mutating func resetForNewSave() {
        lastInterstitialWeek = nil; lastReportWeek = nil; lastRewardedGrantWeek = nil; doubledGrantWeek = nil; secondChanceUsed = false
    }

    public mutating func refundInterstitial() {
        lastInterstitialWeek = nil; lastInterstitialAt = nil; interstitialsToday = max(0, interstitialsToday - 1)
    }

    public mutating func noteDeclined(now: Date) { lastDeclinedAt = now }

    public func isQuiet(now: Date) -> Bool { lastDeclinedAt.map { now.timeIntervalSince($0) < AdPolicy.declineQuiet } ?? false }
}

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
        public var reportWeek: Int
        public var m4Done: Bool
        public var blockingInboxOpen: Bool
        public var now: Date
        public var entitlements: EntitlementSnapshot
        public init(reportWeek: Int, m4Done: Bool, blockingInboxOpen: Bool = false, now: Date, entitlements: EntitlementSnapshot = .free) {
            self.reportWeek = reportWeek; self.m4Done = m4Done; self.blockingInboxOpen = blockingInboxOpen; self.now = now; self.entitlements = entitlements
        }
    }

    public static func canShowInterstitial(_ c: Context, _ ledger: AdLedger) -> Bool {
        if c.entitlements.isAdFree(now: c.now) { return false }
        if c.reportWeek <= freeWeeksWithoutAds || !c.m4Done || c.blockingInboxOpen { return false }
        let l = ledger.rolled(c.now)
        if l.sessionsToday < 2 || l.interstitialsToday >= interstitialsPerDay || l.isQuiet(now: c.now) { return false }
        if let last = l.lastReportWeek, c.reportWeek - last <= 1, l.lastInterstitialWeek == last { return false }
        if let w = l.lastInterstitialWeek, c.reportWeek - w < minGameWeeksBetween { return false }
        if let t = l.lastInterstitialAt, c.now.timeIntervalSince(t) < minRealSecondsBetween { return false }
        return true
    }

    @discardableResult
    public static func reportContinued(_ c: Context, _ l: inout AdLedger) -> Bool {
        let show = canShowInterstitial(c, l)
        l = l.rolled(c.now)
        l.lastReportWeek = c.reportWeek
        if show { l.lastInterstitialWeek = c.reportWeek; l.lastInterstitialAt = c.now; l.interstitialsToday += 1 }
        return show
    }

    public static func canOfferRewardedDouble(week: Int, grantCashThisWeek: Double, entitlements e: EntitlementSnapshot, now: Date, decisionOpen: Bool = false, _ ledger: AdLedger) -> Bool {
        guard !e.isAdFree(now: now), grantCashThisWeek > 0, week > freeWeeksWithoutAds, !decisionOpen else { return false }
        let l = ledger.rolled(now)
        return l.lastRewardedGrantWeek != week && l.doublesToday < doublesPerDay && !l.isQuiet(now: now)
    }

    public static func recordDouble(week: Int, now: Date, _ l: inout AdLedger) {
        l = l.rolled(now); l.lastRewardedGrantWeek = week; l.doublesToday += 1
    }

    public static func rewardedDoubleAmount(grantCash: Double, companyCash: Double, floorUnits: Double? = nil, currency: Currency? = nil) -> Double {
        let floor: Double = floorUnits ?? currency?.scaledPrice(5000) ?? 5000
        return max(0, min(grantCash, max(0.02 * max(0, companyCash), floor)))
    }

    public static func canOfferSecondChance(_ s: GameState, currency: Currency, entitlements e: EntitlementSnapshot, now: Date, _ ledger: AdLedger) -> Bool {
        guard !e.isAdFree(now: now), !ledger.secondChanceUsed, s.week > freeWeeksWithoutAds, !ledger.isQuiet(now: now) else { return false }
        return AdRewards.canSecondChance(s, currency: currency)
    }

    public static func canOfferPass(entitlements e: EntitlementSnapshot, now: Date, _ l: AdLedger) -> Bool {
        if e.isAdFree(now: now) { return false }
        if let t = l.lastPassAt, now.timeIntervalSince(t) < passCooldown { return false }
        return true
    }
    public static func grantPass(_ e: EntitlementSnapshot, now: Date, _ l: inout AdLedger) -> EntitlementSnapshot {
        l.lastPassAt = now
        var out = e; out.passExpires = now.addingTimeInterval(passDuration)
        return out
    }

    public static func requestNonPersonalised(consentGranted: Bool) -> Bool { !consentGranted }
}

public enum AdRewards {
    static let grantLabels: Set<String> = [
        "Job centre: first hire", "Accountant: first month free", "Ad agency: first week refunded",
        "Start-up grant from the town", "Recruitment agency: fee waived", "Insurance: first premium free",
    ]
    public static let doubleLabel = "Ad reward: this week's grant doubled"
    public static let secondChanceLabel = "Second chance: a fresh stake"

    public static func grantCash(_ s: GameState, doubledThrough: Int?) -> Double {
        let from: Int = max(s.week - 1, (doubledThrough ?? -1) + 1)
        return s.statement.reduce(0) { (sum: Double, l: StatementLine) -> Double in
            l.week >= from && l.amount > 0 && grantLabels.contains(l.label) ? sum + l.amount : sum
        }
    }

    public static func doubleExtra(_ s: GameState, currency: Currency, doubledThrough: Int?) -> Double {
        let live: Double = s.companies.filter { $0.status.isLive }.reduce(0) { $0 + $1.cash }
        return jsRound(AdPolicy.rewardedDoubleAmount(grantCash: grantCash(s, doubledThrough: doubledThrough), companyCash: live, currency: currency))
    }

    @discardableResult
    public static func payDouble(_ s: inout GameState, currency: Currency, doubledThrough: Int?) -> Double {
        let amount: Double = doubleExtra(s, currency: currency, doubledThrough: doubledThrough)
        guard amount > 0 else { return 0 }
        Ledger.move(&s, .me, amount, why: doubleLabel)
        return amount
    }

    public static func secondChanceStake(_ currency: Currency) -> Double { currency.scaledPrice(10_000) }

    public static func canSecondChance(_ s: GameState, currency: Currency) -> Bool {
        s.isGameOver && s.cash + secondChanceStake(currency) >= -s.overdraftLimit && Payments.liquid(s) >= 0
    }

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
