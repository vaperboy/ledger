import Foundation
import QuartzCore
import os

/// Debug-only timing for main tab switches: a signpost interval for Instruments plus one log line in milliseconds.
@MainActor
enum TabSwitchTimer {
    #if DEBUG
    private static let signposter = OSSignposter(subsystem: "Ledger", category: "Navigation")
    private static let logger = Logger(subsystem: "Ledger", category: "Navigation")
    private static var started: (tab: AppTab, at: CFTimeInterval, state: OSSignpostIntervalState)?
    #endif

    static func begin(_ tab: AppTab) {
        #if DEBUG
        let state: OSSignpostIntervalState = signposter.beginInterval("TabSwitch", id: signposter.makeSignpostID())
        started = (tab: tab, at: CACurrentMediaTime(), state: state)
        #endif
    }

    /// Called when the new tab appears; the end is taken on the next main-actor turn, after the frame is committed.
    static func end(_ tab: AppTab) {
        #if DEBUG
        guard let s = started, s.tab == tab else { return }
        started = nil
        Task { @MainActor in
            signposter.endInterval("TabSwitch", s.state)
            let ms: Double = (CACurrentMediaTime() - s.at) * 1000
            let text: String = String(format: "%.1f", ms)
            logger.debug("Tab switch to \(tab.rawValue, privacy: .public): \(text, privacy: .public) ms")
        }
        #endif
    }
}
