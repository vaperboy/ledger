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

    /// A quiet tap for ordinary buttons and tab changes.
    static func tap() { guard enabled else { return }; light.impactOccurred() }
    /// The day moved on.
    static func advanceDay() { guard enabled else { return }; soft.impactOccurred(intensity: 0.7) }
    /// A week was completed.
    static func weekDone() { guard enabled else { return }; medium.impactOccurred() }
    static func choose() { guard enabled else { return }; select.selectionChanged() }
    static func success() { guard enabled else { return }; notify.notificationOccurred(.success) }
    static func warning() { guard enabled else { return }; notify.notificationOccurred(.warning) }
    static func failure() { guard enabled else { return }; notify.notificationOccurred(.error) }
}
