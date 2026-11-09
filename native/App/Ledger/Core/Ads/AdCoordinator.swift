import Foundation
import Observation
import GameCore
import Simulation

/// Applies the ad rules of the engine (`AdPolicy`, `AdRewards`) to the provider. Views and the store call only this class.
/// Placements: interstitial after a week report, rewarded double of a grant, rewarded second chance after the books close, rewarded Pro pass in the paywall.
/// Free players only: every rule refuses Pro, Founder, Plus and a running pass. Skip-a-wait is not offered: the engine has no single timer to skip.
@MainActor @Observable
final class AdCoordinator {
    @ObservationIgnored private let provider: AdProvider
    @ObservationIgnored private let entitlements: Entitlements
    @ObservationIgnored private var ledger: AdLedger
    @ObservationIgnored private var readyTask: Task<Void, Never>?
    private static let ledgerKey = "ledger.adLedger"

    /// True while an ad (or its consent step) is on screen. Ad buttons disable while it is set, so two ads never overlap.
    private(set) var isShowing = false

    init(entitlements: Entitlements, provider: AdProvider? = nil) {
        self.entitlements = entitlements
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        self.provider = provider ?? AdMobProvider()
        #else
        self.provider = provider ?? PlaceholderAdProvider()
        #endif
        if let d = UserDefaults.standard.data(forKey: Self.ledgerKey), let l = try? JSONDecoder().decode(AdLedger.self, from: d) { ledger = l } else { ledger = AdLedger() }
        ledger.beginSession(now: Date())   // the first session of a real day shows no interstitial
        store()
    }

    /// False when no SDK is linked in a release build: ad buttons stay hidden.
    var available: Bool { provider.isAvailable }

    /// A new save starts its own week count; the real-time marks (pass, interstitial time, daily counts) stay.
    func resetForNewSave() { ledger.resetForNewSave(); store() }

    private func store() {
        if let d = try? JSONEncoder().encode(ledger) { UserDefaults.standard.set(d, forKey: Self.ledgerKey) }
    }

    /// Consent right before the first ad is shown: the UMP form first, then the tracking prompt, then the SDK. Safe to call again.
    private func ensureReady() async {
        if let t = readyTask { await t.value; return }
        let t: Task<Void, Never> = Task { @MainActor in
            let personalised: Bool = await provider.gatherConsent()
            await TrackingPermission.requestOnce()
            await provider.start(nonPersonalised: AdPolicy.requestNonPersonalised(consentGranted: personalised))
        }
        readyTask = t
        await t.value
    }

    /// Runs one rewarded ad. False when it did not finish; that counts as a declined offer (an hour without ads).
    private func rewardedFinished() async -> Bool {
        isShowing = true
        defer { isShowing = false }
        await ensureReady()
        let earned: Bool = await provider.showRewarded()
        if !earned { ledger.noteDeclined(now: Date()); store() }
        return earned
    }

    // MARK: Placement 1: interstitial

    /// Call when `Continue` is tapped on a week report. Returns true when an ad showed.
    @discardableResult
    func weekReportContinued(reportWeek: Int, m4Done: Bool, blockingInboxOpen: Bool) async -> Bool {
        let c = AdPolicy.Context(reportWeek: reportWeek, m4Done: m4Done, blockingInboxOpen: blockingInboxOpen, now: Date(), entitlements: entitlements.effective)
        var l = ledger
        let should: Bool = available && !isShowing && AdPolicy.reportContinued(c, &l)
        ledger = l; store()
        guard should else { return false }
        isShowing = true
        defer { isShowing = false }
        await ensureReady()
        let shown: Bool = await provider.showInterstitial()
        if !shown { ledger.refundInterstitial(); store() }   // nothing showed: do not spend the slot
        return shown
    }

    // MARK: Placement 2: double this week's grant

    /// The extra cash the doubled grant would pay now (shown on the link), or nil when it is not offered.
    func doubleOffer(_ game: GameStore) -> Double? {
        guard available, !isShowing, let e = game.engine else { return nil }
        let s: GameState = e.state
        let grant: Double = AdRewards.grantCash(s, doubledThrough: ledger.doubledGrantWeek)
        guard AdPolicy.canOfferRewardedDouble(week: s.week, grantCashThisWeek: grant, entitlements: entitlements.effective, now: Date(),
                                              decisionOpen: game.blockingMessageID != nil, ledger) else { return nil }
        let extra: Double = AdRewards.doubleExtra(s, currency: e.homeCurrency, doubledThrough: ledger.doubledGrantWeek)
        return extra > 0 ? extra : nil
    }

    /// Watch the ad, then pay the extra grant through the ledger. Returns the cash paid (0 when the ad was not finished).
    @discardableResult
    func watchForDouble(_ game: GameStore) async -> Double {
        guard doubleOffer(game) != nil, await rewardedFinished(), let e = game.engine else { return 0 }
        let week: Int = e.state.week
        let cur = e.homeCurrency
        let through: Int? = ledger.doubledGrantWeek
        let paid: Double = game.act { (eng: inout GameEngine) -> Double in
            var amount: Double = 0
            eng.update { s, _, _ in amount = AdRewards.payDouble(&s, currency: cur, doubledThrough: through) }
            return amount
        } ?? 0
        if paid > 0 { AdPolicy.recordDouble(week: week, now: Date(), &ledger); ledger.doubledGrantWeek = week; store() }
        return paid
    }

    // MARK: Placement 3: second chance

    /// The stake a second chance would give (shown on the button), or nil when it is not offered.
    func secondChanceOffer(_ game: GameStore) -> Double? {
        guard available, !isShowing, let e = game.engine else { return nil }
        guard AdPolicy.canOfferSecondChance(e.state, currency: e.homeCurrency, entitlements: entitlements.effective, now: Date(), ledger) else { return nil }
        return AdRewards.secondChanceStake(e.homeCurrency)
    }

    /// Watch the ad, then reopen the game with the stake. True when the game reopened.
    @discardableResult
    func watchForSecondChance(_ game: GameStore) async -> Bool {
        guard secondChanceOffer(game) != nil, await rewardedFinished(), let cur = game.engine?.homeCurrency else { return false }
        let ok: Bool = game.act { (eng: inout GameEngine) -> Bool in
            var done: Bool = false
            eng.update { s, _, _ in done = AdRewards.applySecondChance(&s, currency: cur) }
            return done
        } ?? false
        if ok { ledger.secondChanceUsed = true; store() }
        return ok
    }

    // MARK: Placement 5: Season Pass bonus

    /// Is `Watch an ad for Season XP` offered on Home? Free players only, once per real day, and never while another ad is up.
    var canOfferSeasonBonus: Bool { available && !isShowing && !entitlements.effective.isAdFree(now: Date()) && SeasonModel.shared.adBonusAvailable }

    /// Watch the ad, then add the XP. Returns the XP granted (0 when the ad was not finished).
    @discardableResult
    func watchForSeasonBonus() async -> Int {
        guard canOfferSeasonBonus, await rewardedFinished() else { return 0 }
        return SeasonModel.shared.grantAdBonus()
    }

    // MARK: Placement 4: Pro for a day

    /// Is `Try Pro for a day: watch an ad` offered in the paywall? Never to anyone with Pro, Plus or a running pass.
    var canOfferPass: Bool { available && AdPolicy.canOfferPass(entitlements: entitlements.effective, now: Date(), ledger) }

    /// Watch the ad; on success Pro runs for 24 real hours.
    @discardableResult
    func watchForPass() async -> Bool {
        guard canOfferPass, !isShowing, await rewardedFinished() else { return false }
        var l = ledger
        let e = AdPolicy.grantPass(entitlements.effective, now: Date(), &l)
        ledger = l; store()
        if let end = e.passExpires { entitlements.grantPass(until: end) }
        return true
    }
}
