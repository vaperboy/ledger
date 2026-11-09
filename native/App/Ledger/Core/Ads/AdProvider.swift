import Foundation
import UIKit
import AppTrackingTransparency

/// Test ad units published in Google's AdMob documentation. They serve test ads only and need no account.
/// Release IDs are config: fill `releaseInterstitial` and `releaseRewarded` (and the app id in the Info.plist) once there is an AdMob account.
enum AdConfig {
    static let testAppID = "ca-app-pub-3940256099942544~1458002511"
    static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"
    static let testRewarded = "ca-app-pub-3940256099942544/1712485313"
    /// Your own unit ids from the AdMob console. Empty keeps the test units, so a release build never shows a real ad by accident.
    static let releaseInterstitial = ""
    static let releaseRewarded = ""

    static var interstitialUnit: String {
        #if DEBUG
        return testInterstitial
        #else
        return releaseInterstitial.isEmpty ? testInterstitial : releaseInterstitial
        #endif
    }
    static var rewardedUnit: String {
        #if DEBUG
        return testRewarded
        #else
        return releaseRewarded.isEmpty ? testRewarded : releaseRewarded
        #endif
    }
}

/// The only door to an ad SDK. The app compiles and runs with `PlaceholderAdProvider` when the SDK is not linked.
@MainActor
protocol AdProvider: AnyObject {
    /// False when no SDK is linked: the app then hides every ad button and shows no ad.
    var isAvailable: Bool { get }
    /// UMP consent form when required; returns true when personalised ads are allowed. Refused or unknown: false (non-personalised).
    func gatherConsent() async -> Bool
    /// Starts the SDK after consent. `nonPersonalised` sets the request flag.
    func start(nonPersonalised: Bool) async
    /// Shows an interstitial; true when it was shown.
    func showInterstitial() async -> Bool
    /// Shows a rewarded ad; true only when the player earned the reward.
    func showRewarded() async -> Bool
}

/// Used when the SDK is not linked. In DEBUG it grants rewards at once so the paywall and the buttons can be exercised in the simulator.
@MainActor
final class PlaceholderAdProvider: AdProvider {
    var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    func gatherConsent() async -> Bool { false }
    func start(nonPersonalised: Bool) async {}
    func showInterstitial() async -> Bool { false }
    func showRewarded() async -> Bool {
        #if DEBUG
        try? await Task.sleep(nanoseconds: 600_000_000)
        return true
        #else
        return false
        #endif
    }
}

/// App Tracking Transparency: the system prompt only, asked once, right after the consent form and before the first ad is shown.
enum TrackingPermission {
    private static let key = "ledger.attAsked"
    static var asked: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Off until real ads are on: the Info.plist key NSUserTrackingUsageDescription is not set (AltStore refuses an app whose source does not declare it),
    /// and asking without that key crashes the app. Turn on together with the key in project.yml.
    static let enabled = false

    static func requestOnce() async {
        guard enabled, !asked else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }
}
