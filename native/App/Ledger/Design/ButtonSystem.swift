import SwiftUI

enum LedgerButtonSize { case regular, compact }

enum LedgerButtonMetrics {
    static let radius: CGFloat = 12
    static let regularHeight: CGFloat = 48
    static let compactHeight: CGFloat = 32
}

private struct ButtonLoadingKey: EnvironmentKey { static let defaultValue = false }
private struct ButtonSuccessKey: EnvironmentKey { static let defaultValue: Int = 0 }
extension EnvironmentValues {
    var ledgerButtonLoading: Bool {
        get { self[ButtonLoadingKey.self] }
        set { self[ButtonLoadingKey.self] = newValue }
    }
    var ledgerButtonSuccess: Int {
        get { self[ButtonSuccessKey.self] }
        set { self[ButtonSuccessKey.self] = newValue }
    }
}

extension View {
}

private struct LedgerButtonBody: View {
    enum Tier { case primary, secondary, tertiary }
    let configuration: ButtonStyleConfiguration
    let tier: Tier
    let size: LedgerButtonSize
    let fullWidth: Bool
    let tint: Color?
    var passive: Bool = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ledgerButtonLoading) private var loading
    @Environment(\.ledgerButtonSuccess) private var successCount
    @State private var hovering = false
    @State private var flash = false

    private var compact: Bool { size == .compact }
    private var destructive: Bool { tint != nil && tint == P.loss }

    private var textColor: Color {
        guard enabled else { return tier == .primary ? P.inkSoft : P.inkFaint }
        switch tier {
        case .primary: return destructive ? Color.white : P.accentInk
        case .secondary: return passive ? P.inkSoft : (tint ?? P.ink)
        case .tertiary: return tint ?? P.accent
        }
    }

    private var fillColor: Color {
        if flash { return Theme.goldDeep }
        guard tier == .primary else { return Color.clear }
        return enabled ? (tint ?? P.accent) : P.inset
    }

    private var edgeColor: Color {
        guard tier == .secondary else { return Color.clear }
        if flash { return Theme.goldDeep }
        if !enabled || passive { return P.line }
        if destructive { return P.loss.opacity(0.6) }
        return P.lineStrong
    }

    private var lift: Double {
        guard enabled, !loading else { return 0 }
        if configuration.isPressed { return tier == .primary ? 0.18 : 0.10 }
        return hovering ? 0.08 : 0
    }

    var body: some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: LedgerButtonMetrics.radius, style: .continuous)
        let pressed: Bool = configuration.isPressed && enabled && !loading
        let step: TextStep = compact ? .body : .headline
        let weight: Font.Weight = tier == .primary ? .semibold : .medium
        let fillInk: Color? = tier == .primary ? textColor : nil
        configuration.label
            .textStyle(step, tint: textColor, weight: weight)
            .transformEnvironment(\.containerInk) { (ink: inout Color?) in if let fillInk { ink = fillInk } }
            .lineLimit(1).minimumScaleFactor(0.85)
            .opacity(loading ? 0 : 1)
            .overlay { if loading { ProgressView().tint(textColor) } }
            .padding(.horizontal, tier == .tertiary ? Theme.Space.s : (compact ? Theme.Space.m : Theme.Space.l))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? LedgerButtonMetrics.compactHeight : LedgerButtonMetrics.regularHeight)
            .background(shape.fill(fillColor))
            .overlay(shape.fill(Color.white.opacity(lift)))
            .overlay(shape.strokeBorder(edgeColor, lineWidth: 1))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6), value: pressed)
            .animation(Motion.tap(reduceMotion), value: lift)
            .animation(Motion.quick(reduceMotion), value: flash)
            .onHover { (h: Bool) in hovering = h }
            .onChange(of: successCount) { _, _ in
                flash = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    flash = false
                }
            }
            .accessibilityAddTraits(loading ? .updatesFrequently : [])
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var size: LedgerButtonSize = .regular
    var fullWidth = false
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        LedgerButtonBody(configuration: configuration, tier: .primary, size: size, fullWidth: fullWidth, tint: tint)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var size: LedgerButtonSize = .regular
    var fullWidth = false
    var tint: Color? = nil
    var passive = false
    func makeBody(configuration: Configuration) -> some View {
        LedgerButtonBody(configuration: configuration, tier: .secondary, size: size, fullWidth: fullWidth, tint: tint, passive: passive)
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    var size: LedgerButtonSize = .regular
    var fullWidth = false
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        LedgerButtonBody(configuration: configuration, tier: .tertiary, size: size, fullWidth: fullWidth, tint: tint)
    }
}

struct PrimaryAction: View {
    var title: String
    var blockedReason: String? = nil
    var fullWidth = true
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        let blocked: Bool = !(blockedReason ?? "").isEmpty
        VStack(spacing: Theme.Space.xs) {
            Button { Haptics.tap(); action() } label: { Text(title) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: fullWidth))
                .disabled(blocked)
                .accessibilityIdentifier(identifier.isEmpty ? title : identifier)
                .accessibilityHint(blockedReason ?? "")
            if blocked, let reason = blockedReason {
                Text(reason.tidyText).textStyle(.caption).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier((identifier.isEmpty ? title : identifier) + "-blocked")
            }
        }
    }
}

struct PlainTextButtonStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        TertiaryButtonStyle(tint: tint ?? P.inkSoft).makeBody(configuration: configuration)
    }
}

struct ImportantButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle().makeBody(configuration: configuration)
    }
}

struct PopupFooter: View {
    @Environment(\.outsidePalette) private var P
    var cancel = "Cancel"
    var action: String
    var tone: Tone = .normal
    var onCancel: () -> Void
    var onAction: () -> Void
    var cancelEnabled = true
    var actionEnabled = true
    var cancelID = "confirm-cancel"
    var actionID = "confirm-go"

    enum Tone { case normal, expensive, destructive }

    var body: some View {
        VStack(spacing: 4) {
            actionButton.disabled(!actionEnabled)
            Button(action: onCancel) { Text(cancel) }
                .buttonStyle(PopupTextActionStyle(tint: P.inkSoft))
                .accessibilityIdentifier(cancelID)
                .disabled(!cancelEnabled)
        }
        .padding(.top, 8)
    }

    @Environment(\.popupTone) private var popupTone

    @ViewBuilder private var actionButton: some View {
        switch tone {
        case .destructive:
            HoldToConfirmButton(title: action, identifier: actionID, action: onAction)
        case .expensive:
            Button(action: { Haptics.play(.tap); onAction() }) { Text(action).lineLimit(1).minimumScaleFactor(0.8) }
                .buttonStyle(PopupPrimaryCapsuleStyle(tone: .investment, light: P.isLight)).accessibilityIdentifier(actionID)
        case .normal:
            Button(action: { Haptics.play(.tap); onAction() }) { Text(action).lineLimit(1).minimumScaleFactor(0.8) }
                .buttonStyle(PopupPrimaryCapsuleStyle(tone: popupTone == .danger ? .neutral : popupTone, light: P.isLight)).accessibilityIdentifier(actionID)
        }
    }
}

struct PopupActionBar<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: PopupSpace.row) { content() }
            .padding(.horizontal, PopupLayout.inset)
            .padding(.top, PopupSpace.block).padding(.bottom, PopupLayout.inset)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
    }
}

struct InlineMessage: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var isError = true
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            GlyphView(glyph: Glyph.warning, size: 13, weight: 1.6, tint: isError ? P.loss : P.caution).padding(.top, 1)
            Text(text).popupText(.risk, variant: isError ? .destructive : .standard)
        }
    }
}
