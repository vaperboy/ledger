import UIKit

/// The three cues a popup plays on appearing or confirming.
enum PopupCue { case tap, success, warning }

/// Restrained haptics. One place, so they can be switched off in Settings and tuned together.
@MainActor
enum Haptics {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hapticsEnabled") }
    }
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    // The named helpers below are the call-site vocabulary; every one respects `enabled`.
    /// Next day pressed.
    static func nextDay() { guard enabled else { return }; light.impactOccurred() }
    /// The week report number finished counting.
    static func countDone() { guard enabled else { return }; medium.impactOccurred() }
    /// A ladder goal completed, or a record line.
    static func goalDone() { guard enabled else { return }; notify.notificationOccurred(.success) }
    /// An option chosen in the Inbox.
    static func option() { guard enabled else { return }; select.selectionChanged() }
    /// Cash went below zero.
    static func cashWarning() { guard enabled else { return }; notify.notificationOccurred(.warning) }

    /// A popup appeared or a popup action was confirmed: a soft tap, a success, or a warning. Silent when haptics are off.
    static func play(_ cue: PopupCue) {
        guard enabled else { return }
        switch cue {
        case .tap: soft.impactOccurred(intensity: 0.6)
        case .success: notify.notificationOccurred(.success)
        case .warning: notify.notificationOccurred(.warning)
        }
    }

    /// A generic press. Generators are prepared the first time they are used, so the first tap is not late.
    static func tap() { fire { soft.impactOccurred(intensity: 0.6) } }
    /// Next day pressed.
    static func advanceDay() { fire { light.impactOccurred() } }
    /// A week report is ready.
    static func weekDone() { fire { notify.notificationOccurred(.success) } }
    /// An option or segment chosen.
    static func choose() { fire { select.selectionChanged() } }
    static func success() { fire { notify.notificationOccurred(.success) } }
    static func warning() { fire { notify.notificationOccurred(.warning) } }
    static func failure() { fire { notify.notificationOccurred(.error) } }

    private static var prepared = false
    private static func fire(_ play: () -> Void) {
        guard enabled else { return }
        if !prepared {
            prepared = true
            soft.prepare(); light.prepare(); notify.prepare(); select.prepare()
        }
        play()
    }
}
