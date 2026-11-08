import SwiftUI
import UIKit

// The popup rules in one place. Every popup is exactly one category and carries one event tone; the frame
// (`CenterSheetFrame`) draws all three categories with the same glass surface and only their size differs.
// Sizing is content-driven: there is no minimum height anywhere, and nothing stretches a card to a fixed share of the screen
// except a detail panel whose content scrolls by itself.

/// The three popup sizes.
enum PopupCategory: Equatable, CaseIterable {
    /// A confirmation, short warning, quick decision or small purchase: exactly as high as its content.
    case compact
    /// Several options, a person, a negotiation or a moderate breakdown: as high as its content, scrolling past 70% of the screen.
    case medium
    /// An acquisition, company decision, report or multi-step task: as high as its content up to 92% of the screen, footer pinned.
    case detail
}

/// The accent of a popup's event: ambient light, icon ring, primary button, selected states. Never the whole card.
enum PopupTone: Equatable, CaseIterable {
    /// No particular event (a plain choice).
    case neutral
    /// Success, profit.
    case success
    /// Danger, loss, destructive actions.
    case danger
    /// Warnings, financial pressure, deadlines.
    case warning
    /// Information, administration.
    case info
    /// Acquisitions, investments, milestones.
    case investment
    /// Prestige, rare opportunities.
    case prestige

    var color: Color {
        switch self {
        case .neutral: return Color(white: 0.82)
        case .success: return Theme.gain
        case .danger: return Color(red: 0.93, green: 0.36, blue: 0.40)
        case .warning: return Theme.warn
        case .info: return Color(red: 0.45, green: 0.64, blue: 0.98)
        case .investment: return Theme.accent
        case .prestige: return Color(red: 0.70, green: 0.55, blue: 0.98)
        }
    }

    /// How strong the ambient light at the top of the card is.
    var glow: Double { self == .neutral ? 0.10 : 0.30 }

    /// The tone an older variant stands for (call sites that only set a variant still get a fitting accent).
    init(variant: PopupVariant) {
        switch variant {
        case .alert, .destructive: self = .danger
        case .expensive, .reward: self = .investment
        case .report: self = .info
        case .standard: self = .neutral
        }
    }
}

/// The pure size and shape rules (no view state).
enum PopupLayout {
    /// Corner radius of every card.
    static let radius: CGFloat = 28
    /// Inner padding of the card body.
    static let inset: CGFloat = 20
    /// The smallest gap between a card and the screen edges.
    static let screenMargin: CGFloat = 16

    /// The tallest a card of the category may be; compact gets a safety cap only so text can never be cut off.
    static func maxHeight(_ c: PopupCategory, screenHeight: CGFloat) -> CGFloat {
        switch c {
        case .compact: return screenHeight * 0.6
        case .medium: return screenHeight * 0.7
        case .detail: return screenHeight * 0.92
        }
    }

    /// The widest a card of the category gets: a compact card stays narrow, a detail panel uses the room it is given.
    static func maxCardWidth(_ c: PopupCategory) -> CGFloat {
        switch c {
        case .compact: return 340
        case .medium: return 440
        case .detail: return 600
        }
    }

    /// The card's width on a screen: the category's width, never closer than the margin to the screen edges.
    static func cardWidth(_ c: PopupCategory, screenWidth: CGFloat) -> CGFloat {
        min(maxCardWidth(c), screenWidth - 2 * screenMargin)
    }

    /// The category a size request stands for when a call site has not chosen one.
    static func category(for size: CenterSheetSize) -> PopupCategory {
        size == .tall ? .detail : .medium
    }
}

private struct PopupToneKey: EnvironmentKey { static let defaultValue: PopupTone = .neutral }
private struct PopupCategoryKey: EnvironmentKey { static let defaultValue: PopupCategory? = nil }

extension EnvironmentValues {
    /// The tone of the popup this view sits in (buttons and selected states read it).
    var popupTone: PopupTone {
        get { self[PopupToneKey.self] }
        set { self[PopupToneKey.self] = newValue }
    }
    /// The category of the popup this view sits in (nil outside a popup).
    var popupCategory: PopupCategory? {
        get { self[PopupCategoryKey.self] }
        set { self[PopupCategoryKey.self] = newValue }
    }
}

/// The shared glass surface: blurred material, a dark (or light, in light outside apps) tint, the tone's ambient light from the top,
/// a hairline edge that is brighter at the top, and one soft shadow.
struct PopupGlass: ViewModifier {
    var tone: PopupTone
    var light: Bool
    var radius: CGFloat = PopupLayout.radius

    func body(content: Content) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let tint: Color = light ? Color.white.opacity(0.62) : Color(red: 0.075, green: 0.08, blue: 0.09).opacity(0.66)
        let edgeTop: Color = Color.white.opacity(light ? 0.7 : 0.18)
        let edgeBottom: Color = Color.white.opacity(light ? 0.3 : 0.05)
        return content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tint)
                    shape.fill(RadialGradient(colors: [tone.color.opacity(light ? tone.glow * 0.6 : tone.glow), Color.clear],
                                              center: .top, startRadius: 0, endRadius: 340))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [edgeTop, edgeBottom], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 12)
    }
}

/// The ringed icon at the top of a compact popup, in the event's tone.
struct PopupIconRing: View {
    var systemName: String
    var tone: PopupTone

    var body: some View {
        ZStack {
            Circle().fill(tone.color.opacity(0.12))
            Circle().strokeBorder(tone.color.opacity(0.35), lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tone.color)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

extension PopupTone {
    /// The icon a compact popup of this tone shows when the call site names none.
    var defaultSymbol: String {
        switch self {
        case .neutral: return "questionmark"
        case .success: return "checkmark"
        case .danger: return "exclamationmark.triangle"
        case .warning: return "exclamationmark"
        case .info: return "info"
        case .investment: return "sparkles"
        case .prestige: return "crown"
        }
    }
}

/// The primary capsule of a popup: white on dark glass for a neutral event, the tone's colour otherwise.
struct PopupPrimaryCapsuleStyle: ButtonStyle {
    var tone: PopupTone
    var light = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = tone == .neutral ? (light ? Color.black.opacity(0.88) : Color.white) : tone.color
        let ink: Color = tone == .neutral ? (light ? Color.white : Color.black) : Color.black.opacity(0.88)
        return configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(fill))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// The quiet second action under a primary capsule: a text button with a full 44pt target.
struct PopupTextActionStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Press and hold to confirm a genuinely destructive or irreversible decision. The fill grows while the finger stays down,
/// letting go early cancels at once, it runs at most once, and VoiceOver users confirm with the button's default action.
struct HoldToConfirmButton: View {
    var title: String
    var tint: Color = PopupTone.danger.color
    var duration: Double = 1.1
    var identifier = "confirm-go"
    var action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Capsule().fill(tint.opacity(0.14))
            GeometryReader { (g: GeometryProxy) in
                Capsule().fill(tint.opacity(0.5)).frame(width: max(0, g.size.width * progress))
            }
            .clipShape(Capsule())
            Text(done ? "Done" : "Hold to \(title)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        .overlay(Capsule().strokeBorder(tint.opacity(holding ? 0.9 : 0.55), lineWidth: 1))
        .shadow(color: tint.opacity(holding ? 0.55 : 0.25), radius: holding ? 18 : 10, x: 0, y: 0)
        .scaleEffect(holding && !reduceMotion ? 0.985 : 1)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40, perform: complete, onPressingChanged: pressing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Press and hold to confirm. This cannot be undone.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
        .accessibilityIdentifier(identifier)
    }

    private func pressing(_ down: Bool) {
        guard !done else { return }
        if down {
            holding = true
            Haptics.play(.tap)
            withAnimation(.linear(duration: duration)) { progress = 1 }
        } else {
            holding = false
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
        }
    }

    private func complete() {
        guard !done else { return }
        done = true
        holding = false
        progress = 1
        Haptics.play(.warning)
        action()
    }
}
