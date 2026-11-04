#if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
import Foundation
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

// Compiled only when the owner adds the two Swift packages (see the commented block in project.yml): Google Mobile Ads 11.x and the
// User Messaging Platform 2.x. Until then `PlaceholderAdProvider` is used and the app has no ad dependency.
// Not compiled by the author (no Mac): check the symbols against the pinned SDK versions on the first CI build with the packages.

@MainActor
final class AdMobProvider: NSObject, AdProvider, GADFullScreenContentDelegate {
    var isAvailable: Bool { true }
    private var nonPersonalised = true
    private var interstitial: GADInterstitialAd?
    private var rewarded: GADRewardedAd?

    private var top: UIViewController? {
        let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        var v = root
        while let p = v?.presentedViewController { v = p }
        return v
    }

    func gatherConsent() async -> Bool {
        let params = UMPRequestParameters()
        params.tagForUnderAgeOfConsent = false
        do {
            try await UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: params)
            if let vc = top { try await UMPConsentForm.loadAndPresentIfRequired(from: vc) }
        } catch { return false }
        let s = UMPConsentInformation.sharedInstance.consentStatus
        return UMPConsentInformation.sharedInstance.canRequestAds && (s == .obtained || s == .notRequired)
    }

    func start(nonPersonalised: Bool) async {
        self.nonPersonalised = nonPersonalised
        guard UMPConsentInformation.sharedInstance.canRequestAds else { return }
        await GADMobileAds.sharedInstance().start()
        await load()
    }

    private func request() -> GADRequest {
        let r = GADRequest()
        if nonPersonalised { let e = GADExtras(); e.additionalParameters = ["npa": "1"]; r.register(e) }
        return r
    }

    private func load() async {
        interstitial = try? await GADInterstitialAd.load(withAdUnitID: AdConfig.interstitialUnit, request: request())
        interstitial?.fullScreenContentDelegate = self
        rewarded = try? await GADRewardedAd.load(withAdUnitID: AdConfig.rewardedUnit, request: request())
        rewarded?.fullScreenContentDelegate = self
    }

    func showInterstitial() async -> Bool {
        guard let ad = interstitial, let vc = top else { await load(); return false }
        interstitial = nil
        ad.present(fromRootViewController: vc)
        Task { await load() }
        return true
    }

    func showRewarded() async -> Bool {
        if rewarded == nil { await load() }
        guard let ad = rewarded, let vc = top else { return false }
        rewarded = nil
        var earned = false
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            finish = { done.resume() }
            ad.present(fromRootViewController: vc) { earned = true }
        }
        Task { await load() }
        return earned
    }

    private var finish: (() -> Void)?
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) { finish?(); finish = nil }
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { finish?(); finish = nil }
}
#endif
