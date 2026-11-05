import SwiftUI

/// The five size classes of every centred popup. One place defines them (here); `CenterSheetFrame` (and so `GamePopup`) measures its
/// content and asks `PopupSizing.sizeClass` which one applies, so a card warps to its content instead of every popup sharing one width.
///   toast    one line and one button (a notice, a short confirmation).
///   compact  a title, two to four rows and a footer.
///   standard the ordinary card: a form, a list of options, a few paragraphs.
///   tall     content that scrolls: grows up to 80% of the screen height, then scrolls.
///   full     sheet-like: a fixed 92% of the screen height, for popups with their own pages (`PopupStack`, `size: .tall` at the call site).
enum PopupSizeClass: Int, CaseIterable, Comparable {
    case toast, compact, standard, tall, full

    static func < (a: PopupSizeClass, b: PopupSizeClass) -> Bool { a.rawValue < b.rawValue }

    /// Tall and full cards can be swiped down to close.
    var isSwipeable: Bool { self >= .tall }
}

/// The pure rules behind the size classes: thresholds, widths, heights, motion numbers. No view state, so they are unit-tested
/// (`PopupSizingTests`).
enum PopupSizing {
    /// A card (header and content) up to this high is a toast.
    static let toastMaxHeight: CGFloat = 156
    /// A card up to this high is compact.
    static let compactMaxHeight: CGFloat = 330
    /// A card up to this share of the screen height is standard; taller is `tall`.
    static let standardFraction: CGFloat = 0.55
    /// How far past a class bound the card must go before the class changes back (stops flicker when a width change re-wraps text).
    static let hysteresis: CGFloat = 24
    /// The share of the screen height a scrolling card may use.
    static let tallFraction: CGFloat = 0.8
    /// The share of the screen height of a full card.
    static let fullFraction: CGFloat = 0.92
    /// Below this screen height (landscape phone, keyboard open) cards may use almost all of it.
    static let shortScreen: CGFloat = 520
    static let shortFraction: CGFloat = 0.94

    /// The largest height a scrolling card may have.
    static func room(screenHeight: CGFloat) -> CGFloat {
        screenHeight < shortScreen ? screenHeight * shortFraction : screenHeight * tallFraction
    }

    /// The fixed height of a full card.
    static func fullHeight(screenHeight: CGFloat) -> CGFloat {
        let share: CGFloat = screenHeight < shortScreen ? shortFraction : fullFraction
        return max(260, screenHeight * share)
    }

    /// The highest card height (header included) the class holds.
    static func upperBound(of cls: PopupSizeClass, screenHeight: CGFloat) -> CGFloat {
        switch cls {
        case .toast: return toastMaxHeight
        case .compact: return compactMaxHeight
        case .standard: return max(compactMaxHeight, screenHeight * standardFraction)
        case .tall, .full: return CGFloat.greatestFiniteMagnitude
        }
    }

    /// The lowest card height the class holds.
    static func lowerBound(of cls: PopupSizeClass, screenHeight: CGFloat) -> CGFloat {
        switch cls {
        case .toast: return 0
        case .compact: return toastMaxHeight
        case .standard: return compactMaxHeight
        case .tall, .full: return max(compactMaxHeight, screenHeight * standardFraction)
        }
    }

    /// The class for a card of `cardHeight` (header and content, before any maximum). `requested == .tall` is the full class. An
    /// unmeasured card (height 0 or less) is standard. `previous` adds hysteresis: the card keeps its class while it is within
    /// `hysteresis` points of that class's bounds.
    static func sizeClass(requested: CenterSheetSize, cardHeight: CGFloat, screenHeight: CGFloat, previous: PopupSizeClass? = nil) -> PopupSizeClass {
        if requested == .tall { return .full }
        if cardHeight <= 0 { return previous ?? .standard }
        if let prev = previous, prev != .full {
            let low: CGFloat = lowerBound(of: prev, screenHeight: screenHeight) - hysteresis
            let high: CGFloat = upperBound(of: prev, screenHeight: screenHeight) + hysteresis
            if cardHeight > low && cardHeight <= high { return prev }
        }
        if cardHeight <= toastMaxHeight { return .toast }
        if cardHeight <= compactMaxHeight { return .compact }
        if cardHeight <= max(compactMaxHeight, screenHeight * standardFraction) { return .standard }
        return .tall
    }

    /// The widest the class gets (phone width is smaller anyway; iPad and landscape stop here).
    static func maxWidth(of cls: PopupSizeClass) -> CGFloat {
        switch cls {
        case .toast: return 340
        case .compact: return 400
        case .standard: return 480
        case .tall: return 560
        case .full: return 600
        }
    }

    /// How dark the backdrop is: lighter for a toast, darker for a sheet-like card.
    static func dim(of cls: PopupSizeClass) -> Double {
        switch cls {
        case .toast: return 0.4
        case .compact: return 0.5
        case .standard: return 0.55
        case .tall: return 0.58
        case .full: return 0.62
        }
    }

    /// The scale a card arrives from (1 under Reduce Motion).
    static func entryScale(of cls: PopupSizeClass, reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        switch cls {
        case .toast: return 0.9
        case .compact: return 0.94
        case .standard: return 0.95
        case .tall: return 0.97
        case .full: return 0.98
        }
    }

    /// How far below its place a card arrives from (0 under Reduce Motion): bigger cards rise further.
    static func entryRise(of cls: PopupSizeClass, reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 0 }
        switch cls {
        case .toast, .compact: return 8
        case .standard: return 12
        case .tall: return 18
        case .full: return 28
        }
    }

    // MARK: Swipe down

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
