import Foundation
import SwiftUI
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
enum AdProviders {
    /// The one place that picks the ad network. To connect a real network, return its provider here.
    static func make() -> AdProvider {
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        return AdMobProvider()
        #else
        return PlaceholderAdProvider()
        #endif
    }
}

/// Stands in until an ad network is connected. Debug builds show a plainly marked test ad; release builds show none.
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
        return await TestAdScreen.present()
        #else
        return false
        #endif
    }
}

#if DEBUG
/// A full-screen "TEST AD" card for debug builds: counts down, then closes and counts as watched.
private struct TestAdScreen: View {
    var done: () -> Void
    @State private var left = 3

    var body: some View {
        VStack(spacing: 16) {
            Text("TEST AD").font(.system(size: 34, weight: .black)).foregroundStyle(.white)
            Text("Debug build only. A real ad network is not connected.").font(.body).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
            Text(left > 0 ? "Closes in \(left)" : "Done").font(.headline.monospacedDigit()).foregroundStyle(.white)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.45, green: 0.18, blue: 0.75).ignoresSafeArea())
        .accessibilityIdentifier("test-ad")
        .task {
            while left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                left -= 1
            }
            done()
        }
    }

    static func present() async -> Bool {
        let root: UIViewController? = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        var top: UIViewController? = root
        while let p = top?.presentedViewController { top = p }
        guard let host = top else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var shown: UIViewController?
            let screen = TestAdScreen { shown?.dismiss(animated: true) { cont.resume(returning: true) } }
            let vc = UIHostingController(rootView: screen)
            vc.modalPresentationStyle = .fullScreen
            shown = vc
            host.present(vc, animated: true)
        }
    }
}
#endif
