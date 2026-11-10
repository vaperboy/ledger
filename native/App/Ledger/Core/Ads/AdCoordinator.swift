import Foundation
import Observation
import GameCore
import Simulation

@MainActor @Observable
final class AdCoordinator {
    @ObservationIgnored private let provider: AdProvider
    @ObservationIgnored private let entitlements: Entitlements
    @ObservationIgnored private var ledger: AdLedger
    @ObservationIgnored private var readyTask: Task<Void, Never>?
    private static let ledgerKey = "ledger.adLedger"

    private(set) var isShowing = false

    init(entitlements: Entitlements, provider: AdProvider? = nil) {
        self.entitlements = entitlements
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        self.provider = provider ?? AdMobProvider()
        #else
        self.provider = provider ?? PlaceholderAdProvider()
        #endif
        if let d = UserDefaults.standard.data(forKey: Self.ledgerKey), let l = try? JSONDecoder().decode(AdLedger.self, from: d) { ledger = l } else { ledger = AdLedger() }
        ledger.beginSession(now: Date())
        store()
    }

    var available: Bool { provider.isAvailable }

    func resetForNewSave() { ledger.resetForNewSave(); store() }

    private func store() {
        if let d = try? JSONEncoder().encode(ledger) { UserDefaults.standard.set(d, forKey: Self.ledgerKey) }
    }

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

    private func rewardedFinished() async -> Bool {
        isShowing = true
        defer { isShowing = false }
        await ensureReady()
        let earned: Bool = await provider.showRewarded()
        if !earned { ledger.noteDeclined(now: Date()); store() }
        return earned
    }

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
        if !shown { ledger.refundInterstitial(); store() }
        return shown
    }

    func doubleOffer(_ game: GameStore) -> Double? {
        guard available, !isShowing, let e = game.engine else { return nil }
        let s: GameState = e.state
        let grant: Double = AdRewards.grantCash(s, doubledThrough: ledger.doubledGrantWeek)
        guard AdPolicy.canOfferRewardedDouble(week: s.week, grantCashThisWeek: grant, entitlements: entitlements.effective, now: Date(),
                                              decisionOpen: game.blockingMessageID != nil, ledger) else { return nil }
        let extra: Double = AdRewards.doubleExtra(s, currency: e.homeCurrency, doubledThrough: ledger.doubledGrantWeek)
        return extra > 0 ? extra : nil
    }

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

    func secondChanceOffer(_ game: GameStore) -> Double? {
        guard available, !isShowing, let e = game.engine else { return nil }
        guard AdPolicy.canOfferSecondChance(e.state, currency: e.homeCurrency, entitlements: entitlements.effective, now: Date(), ledger) else { return nil }
        return AdRewards.secondChanceStake(e.homeCurrency)
    }

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

    var canOfferSeasonBonus: Bool { available && !isShowing && !entitlements.effective.isAdFree(now: Date()) && SeasonModel.shared.adBonusAvailable }

    @discardableResult
    func watchForSeasonBonus() async -> Int {
        guard canOfferSeasonBonus, await rewardedFinished() else { return 0 }
        return SeasonModel.shared.grantAdBonus()
    }

    var canOfferPass: Bool { available && AdPolicy.canOfferPass(entitlements: entitlements.effective, now: Date(), ledger) }

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
