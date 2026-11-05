import UIKit

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

    // Exactly six haptics. The older helpers below keep their names so call sites compile, but they are silent.
    /// Next day pressed.
    static func nextDay() { guard enabled else { return }; light.impactOccurred() }
    /// The week report number finished counting.
    static func countDone() { guard enabled else { return }; medium.impactOccurred() }
    /// A ladder goal completed, or a record line.
    static func goalDone() { guard enabled else { return }; notify.notificationOccurred(.success) }
    /// An option chosen in the Inbox.
    static func option() { guard enabled else { return }; select.selectionChanged() }
    /// The cash-below-zero banner appeared.
    static func cashWarning() { guard enabled else { return }; notify.notificationOccurred(.warning) }

    static func tap() {}
    static func advanceDay() {}
    static func weekDone() {}
    static func choose() {}
    static func success() {}
    static func warning() {}
    static func failure() {}
}
