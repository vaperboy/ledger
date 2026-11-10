import SwiftUI

enum PopupSizing {
    static func shouldDismiss(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation > 110 || predictedEnd > 260
    }

    static func dragOffset(translation: CGFloat) -> CGFloat {
        translation <= 0 ? 0 : translation * 0.9
    }

    static func dragDimFactor(offset: CGFloat) -> Double {
        let p: Double = min(1, max(0, Double(offset) / 400))
        return 1 - 0.6 * p
    }
}

extension PopupVariant {
    var appearCue: PopupCue {
        switch self {
        case .reward: return .success
        case .alert, .destructive: return .warning
        default: return .tap
        }
    }
}
