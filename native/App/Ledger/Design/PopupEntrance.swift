import SwiftUI

/// How a popup card arrives, by its size and kind. The card starts at `scale`, shifted by (`dx`, `dy`), transparent, and settles with
/// `animation`. Under Reduce Motion every kind is a plain fade.
enum PopupEntrance: Equatable {
    /// A small question or notice: a short scale up.
    case compact
    /// A list or form: rises a little from below.
    case medium
    /// A detail panel: slides in from the right.
    case detail
    /// A large decision (a queued choice with weight): a slower, larger scale with a soft settle.
    case decision
    /// A confirmation of something done (a reward, a success): a lively spring.
    case confirmation
    /// An irreversible action: no spring and no bounce, a short plain fade.
    case destructive

    var scale: CGFloat {
        switch self {
        case .compact: return 0.92
        case .medium: return 0.97
        case .detail: return 1
        case .decision: return 0.88
        case .confirmation: return 0.8
        case .destructive: return 0.99
        }
    }
    var dx: CGFloat { self == .detail ? 90 : 0 }
    var dy: CGFloat {
        switch self {
        case .medium: return 28
        case .decision: return 12
        default: return 0
        }
    }
    var animation: Animation {
        switch self {
        case .compact: return .spring(response: 0.34, dampingFraction: 0.82)
        case .medium: return .spring(response: 0.36, dampingFraction: 0.88)
        case .detail: return .spring(response: 0.38, dampingFraction: 0.9)
        case .decision: return .spring(response: 0.46, dampingFraction: 0.78)
        case .confirmation: return .spring(response: 0.4, dampingFraction: 0.58)
        case .destructive: return .easeOut(duration: 0.2)
        }
    }

    /// The entrance of a card: an irreversible one never bounces, a reward confirms, a queued decision is large, otherwise by size.
    static func of(category: PopupCategory, variant: PopupVariant, tone: PopupTone, priority: PopupPriority?) -> PopupEntrance {
        if variant == .destructive || tone == .danger { return .destructive }
        if variant == .reward || tone == .success { return .confirmation }
        if priority == .decision { return .decision }
        switch category {
        case .compact: return .compact
        case .medium: return .medium
        case .detail: return .detail
        }
    }
}

private struct PopupPriorityKey: EnvironmentKey { static let defaultValue: PopupPriority? = nil }
extension EnvironmentValues {
    /// The queue priority of the popup being drawn (set by the host), so the frame can tell a decision from a plain panel.
    var popupPriority: PopupPriority? {
        get { self[PopupPriorityKey.self] }
        set { self[PopupPriorityKey.self] = newValue }
    }
}
