import Foundation
import Observation
import Simulation

/// Applies the ad rules of the engine (`AdPolicy`) to the provider (brief 11.5). Views and the store call only this class.
/// Three placements, no others: interstitial after a week report, rewarded double on the report, rewarded Pro pass in the paywall.
@MainActor @Observable
final class AdCoordinator {
    @ObservationIgnored private let provider: AdProvider
    @ObservationIgnored private let entitlements: Entitlements
    @ObservationIgnored private var ledger: AdLedger
    @ObservationIgnored private var started = false
    private static let ledgerKey = "ledger.adLedger"

    init(entitlements: Entitlements, provider: AdProvider? = nil) {
        self.entitlements = entitlements
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        self.provider = provider ?? AdMobProvider()
        #else
        self.provider = provider ?? PlaceholderAdProvider()
        #endif
        if let d = UserDefaults.standard.data(forKey: Self.ledgerKey), let l = try? JSONDecoder().decode(AdLedger.self, from: d) { ledger = l } else { ledger = AdLedger() }
    }

    /// False when no SDK is linked in a release build: ad buttons stay hidden.
    var available: Bool { provider.isAvailable }

    /// A new save starts its own week count, so the old marks must not block it.
    func resetForNewSave() { ledger = AdLedger(); store() }

    private func store() {
        if let d = try? JSONEncoder().encode(ledger) { UserDefaults.standard.set(d, forKey: Self.ledgerKey) }
    }

    /// Consent first, then the SDK. Not for paid players. Safe to call again.
    func prepareIfNeeded() async {
        guard !started, available, !entitlements.effective.isAdFree(now: Date()) else { return }
        started = true
        let personalised = await provider.gatherConsent()
        await provider.start(nonPersonalised: AdPolicy.requestNonPersonalised(consentGranted: personalised))
    }

    /// Placement 1. Call when `Continue` is tapped on a week report. Asks for tracking once after the first report. Returns true when an ad showed.
    @discardableResult
    func weekReportContinued(reportWeek: Int, m4Done: Bool, blockingInboxOpen: Bool) async -> Bool {
        let e = entitlements.effective
        if !e.isAdFree(now: Date()), available, AdPolicy.shouldAskTracking(reportWeek: reportWeek, alreadyAsked: TrackingPermission.asked) {
            await TrackingPermission.requestOnce()
        }
        await prepareIfNeeded()
        let c = AdPolicy.Context(reportWeek: reportWeek, m4Done: m4Done, blockingInboxOpen: blockingInboxOpen, now: Date(), entitlements: e)
        var l = ledger
        let should = available && AdPolicy.reportContinued(c, &l)
        ledger = l; store()
        guard should else { return false }
        let shown = await provider.showInterstitial()
        if !shown { ledger.lastInterstitialWeek = nil; ledger.lastInterstitialAt = nil; store() }   // nothing showed: do not spend the slot
        return shown
    }

    /// Placement 2: is the `Watch an ad: double this week's grant` link offered?
    func canOfferDouble(week: Int, grantCashThisWeek: Double) -> Bool {
        available && AdPolicy.canOfferRewardedDouble(week: week, grantCashThisWeek: grantCashThisWeek, entitlements: entitlements.effective, now: Date(), ledger)
    }

    /// Placement 2: watch the ad. Returns the extra cash to pay (0 when the ad was not finished).
    func watchForDouble(week: Int, grantCash: Double, companyCash: Double) async -> Double {
        guard await provider.showRewarded() else { return 0 }
        ledger.lastRewardedGrantWeek = week; store()
        return AdPolicy.rewardedDoubleAmount(grantCash: grantCash, companyCash: companyCash)
    }

    /// Placement 3: is `Try Pro for a day: watch an ad` offered in the paywall?
    var canOfferPass: Bool { available && AdPolicy.canOfferPass(entitlements: entitlements.effective, now: Date(), ledger) }

    /// Placement 3: watch the ad; on success Pro runs for 24 real hours.
    @discardableResult
    func watchForPass() async -> Bool {
        guard canOfferPass, await provider.showRewarded() else { return false }
        var l = ledger
        let e = AdPolicy.grantPass(entitlements.effective, now: Date(), &l)
        ledger = l; store()
        if let end = e.passExpires { entitlements.grantPass(until: end) }
        return true
    }
}
