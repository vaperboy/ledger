import SwiftUI

/// The swipe-to-close rules of a popup card (pure, unit-tested in `PopupSizingTests`). Sizes are not here: they are the three
/// categories in `PopupSystem.swift` (`PopupCategory`, `PopupLayout`), measured from the content with no minimum height.
enum PopupSizing {
    /// A swipe down closes the card when it went far enough or was flicked.
    static func shouldDismiss(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation > 110 || predictedEnd > 260
    }

    /// The drag follows the finger down with resistance and never up.
    static func dragOffset(translation: CGFloat) -> CGFloat {
        translation <= 0 ? 0 : translation * 0.9
    }

    /// The backdrop lightens as the card is dragged away (1 at rest, 0.4 at 400pt or more).
    static func dragDimFactor(offset: CGFloat) -> Double {
        let p: Double = min(1, max(0, Double(offset) / 400))
        return 1 - 0.6 * p
    }
}

extension PopupVariant {
    /// The haptic a card of this variant plays when it appears.
    var appearCue: PopupCue {
        switch self {
        case .reward: return .success
        case .alert, .destructive: return .warning
        default: return .tap
        }
    }
}
