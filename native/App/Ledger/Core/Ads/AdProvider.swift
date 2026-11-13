import Foundation
import UIKit

enum AdConfig {
    static let testAppID = "ca-app-pub-3940256099942544~1458002511"
    static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"
    static let testRewarded = "ca-app-pub-3940256099942544/1712485313"
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

@MainActor
protocol AdProvider: AnyObject {
    var isAvailable: Bool { get }
    func gatherConsent() async -> Bool
    func start(nonPersonalised: Bool) async
    func showInterstitial() async -> Bool
    func showRewarded() async -> Bool
}

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
