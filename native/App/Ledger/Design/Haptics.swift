import UIKit

enum PopupCue { case tap, success, warning }

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

    static func nextDay() { guard enabled else { return }; light.impactOccurred() }
    static func countDone() { guard enabled else { return }; medium.impactOccurred() }
    static func goalDone() { guard enabled else { return }; notify.notificationOccurred(.success) }
    static func option() { guard enabled else { return }; select.selectionChanged() }
    static func cashWarning() { guard enabled else { return }; notify.notificationOccurred(.warning) }

    static func play(_ cue: PopupCue) {
        guard enabled else { return }
        switch cue {
        case .tap: soft.impactOccurred(intensity: 0.6)
        case .success: notify.notificationOccurred(.success)
        case .warning: notify.notificationOccurred(.warning)
        }
    }

    static func tap() { fire { soft.impactOccurred(intensity: 0.6) } }
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
