import SwiftUI
import UIKit

enum PopupCategory: Equatable, CaseIterable {
    case compact
    case medium
    case detail
}

enum PopupTone: Equatable, CaseIterable {
    case neutral
    case success
    case danger
    case warning
    case info
    case investment
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

    var glow: Double { self == .neutral ? 0.10 : 0.30 }

    init(variant: PopupVariant) {
        switch variant {
        case .alert, .destructive: self = .danger
        case .expensive, .reward: self = .investment
        case .report: self = .info
        case .standard: self = .neutral
        }
    }
}

enum PopupLayout {
    static let radius: CGFloat = 28
    static let inset: CGFloat = 20
    static let screenMargin: CGFloat = 16

    static func maxHeight(_ c: PopupCategory, screenHeight: CGFloat) -> CGFloat {
        switch c {
        case .compact: return screenHeight * 0.6
        case .medium: return screenHeight * 0.7
        case .detail: return screenHeight * 0.92
        }
    }

    static func maxCardWidth(_ c: PopupCategory) -> CGFloat {
        switch c {
        case .compact: return 340
        case .medium: return 440
        case .detail: return 600
        }
    }

    static func cardWidth(_ c: PopupCategory, screenWidth: CGFloat) -> CGFloat {
        min(maxCardWidth(c), screenWidth - 2 * screenMargin)
    }

    static func category(for size: CenterSheetSize) -> PopupCategory {
        size == .tall ? .detail : .medium
    }
}

private struct PopupToneKey: EnvironmentKey { static let defaultValue: PopupTone = .neutral }
private struct PopupCategoryKey: EnvironmentKey { static let defaultValue: PopupCategory? = nil }

extension EnvironmentValues {
    var popupTone: PopupTone {
        get { self[PopupToneKey.self] }
        set { self[PopupToneKey.self] = newValue }
    }
    var popupCategory: PopupCategory? {
        get { self[PopupCategoryKey.self] }
        set { self[PopupCategoryKey.self] = newValue }
    }
}

struct PopupGlass: ViewModifier {
    var tone: PopupTone
    var light: Bool
    var radius: CGFloat = PopupLayout.radius

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            solid(content)
        } else {
            glass(content)
        }
    }

    private func solid(_ content: Content) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let base: Color = light ? Color(white: 0.97) : Color(red: 0.11, green: 0.115, blue: 0.125)
        return content
            .background {
                ZStack {
                    shape.fill(base)
                    shape.fill(RadialGradient(colors: [tone.color.opacity(light ? tone.glow * 0.5 : tone.glow * 0.8), Color.clear],
                                              center: .top, startRadius: 0, endRadius: 340))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 12)
    }

    @ViewBuilder private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            real(content)
        } else {
            drawn(content)
        }
        #else
        drawn(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func real(_ content: Content) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let tint: Color = light ? Color.white : Color(red: 0.075, green: 0.08, blue: 0.09)
        return content
            .modifier(LiquidGlass(shape: shape, tint: tint))
            .background {
                shape.fill(RadialGradient(colors: [tone.color.opacity(light ? tone.glow * 0.6 : tone.glow), Color.clear],
                                          center: .top, startRadius: 0, endRadius: 340))
            }
            .overlay {
                shape.fill(RadialGradient(colors: [tone.color.opacity(light ? 0.0 : tone.glow * 0.5), Color.clear],
                                          center: .top, startRadius: 0, endRadius: 300))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 12)
    }
    #endif

    private func drawn(_ content: Content) -> some View {
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

struct PopupPrimaryCapsuleStyle: ButtonStyle {
    var tone: PopupTone
    var light = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: LedgerButtonMetrics.radius, style: .continuous)
        let pressed: Bool = configuration.isPressed && isEnabled
        let fill: Color = tone == .neutral ? (light ? Color.black.opacity(0.88) : Color.white) : tone.color
        let ink: Color = tone == .neutral ? (light ? Color.white : Color.black) : Color.black.opacity(0.88)
        return configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: LedgerButtonMetrics.regularHeight)
            .background(shape.fill(fill))
            .overlay(shape.fill(Color.white.opacity(pressed ? 0.18 : 0)))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .contentShape(shape)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6), value: pressed)
    }
}

struct PopupTextActionStyle: ButtonStyle {
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

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
            RoundedRectangle(cornerRadius: LedgerButtonMetrics.radius, style: .continuous).fill(tint.opacity(0.14))
            GeometryReader { (g: GeometryProxy) in
                Rectangle().fill(tint.opacity(0.5)).frame(width: max(0, g.size.width * progress))
            }
            .clipShape(RoundedRectangle(cornerRadius: LedgerButtonMetrics.radius, style: .continuous))
            Text(done ? "Done" : "Hold to \(title)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, minHeight: LedgerButtonMetrics.regularHeight, maxHeight: LedgerButtonMetrics.regularHeight)
        .overlay(RoundedRectangle(cornerRadius: LedgerButtonMetrics.radius, style: .continuous).strokeBorder(tint.opacity(holding ? 0.9 : 0.55), lineWidth: 1))
        .shadow(color: tint.opacity(holding ? 0.55 : 0.25), radius: holding ? 18 : 10, x: 0, y: 0)
        .scaleEffect(holding && !reduceMotion ? 0.97 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6), value: holding)
        .contentShape(Rectangle())
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
