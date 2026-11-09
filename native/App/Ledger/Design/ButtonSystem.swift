import SwiftUI

// The three buttons of the game. Every older style below maps onto one of them.
//   Primary   : `PrimaryButtonStyle`, solid accent, accent ink. One per screen or popup (Next Day, Continue, Claim, Execute).
//   Secondary : `SecondaryButtonStyle`, a quiet outline with ink text; `tint` colours the text (accent = recommended, loss = irreversible).
//   Tertiary  : `TertiaryButtonStyle`, text only (Cancel, See all, links).
//   Sizes     : `.regular` is 44 pt high; `.compact` draws 32 pt but keeps a 44 pt hit area. Disabled buttons look disabled themselves.
//   Blocked   : `PrimaryAction` shows the reason under a disabled primary button instead of fading it silently.

/// Height of a button: regular (44 pt) or compact (32 pt drawn inside a 44 pt hit area).
enum LedgerButtonSize { case regular, compact }

/// Corner radius and heights of every button (radius inside the 10 to 14 pt range).
enum LedgerButtonMetrics {
    static let radius: CGFloat = 12
    static let regularHeight: CGFloat = 48
    static let compactHeight: CGFloat = 32
}

private struct ButtonLoadingKey: EnvironmentKey { static let defaultValue = false }
private struct ButtonSuccessKey: EnvironmentKey { static let defaultValue: Int = 0 }
extension EnvironmentValues {
    /// True while the button's action runs: the label gives way to a spinner and touches are ignored.
    var ledgerButtonLoading: Bool {
        get { self[ButtonLoadingKey.self] }
        set { self[ButtonLoadingKey.self] = newValue }
    }
    /// A counter: each change flashes the button bronze once (the action succeeded).
    var ledgerButtonSuccess: Int {
        get { self[ButtonSuccessKey.self] }
        set { self[ButtonSuccessKey.self] = newValue }
    }
}

extension View {
    /// Shows the shared button spinner in place of the label of the buttons inside, and blocks their touches.
    func buttonLoading(_ on: Bool) -> some View {
        environment(\.ledgerButtonLoading, on).allowsHitTesting(!on)
    }
    /// Flashes the buttons inside bronze each time `count` changes.
    func buttonSuccess(_ count: Int) -> some View { environment(\.ledgerButtonSuccess, count) }
}

/// The one body behind the three button styles. One press rule for all: scale 0.97 with a spring back, a lighter fill on touch, a hover
/// lift under a pointer, a flat disabled look, a spinner while loading, a bronze flash on success. A loss tint is a plain red.
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

    /// Light laid over the button while it is touched or hovered.
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
            // On the accent fill every Text of the label takes the fill's ink, even one styled inside the label.
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

/// The one filled button: solid accent, no gradient, no glow. Use once per screen or popup.
struct PrimaryButtonStyle: ButtonStyle {
    var size: LedgerButtonSize = .regular
    var fullWidth = false
    /// A fill other than the accent (rare: a palette's own brand colour).
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        LedgerButtonBody(configuration: configuration, tier: .primary, size: size, fullWidth: fullWidth, tint: tint)
    }
}

/// The quiet outline: every other action. `tint` colours the text; `passive` greys a Later / Skip answer.
struct SecondaryButtonStyle: ButtonStyle {
    var size: LedgerButtonSize = .regular
    var fullWidth = false
    var tint: Color? = nil
    var passive = false
    func makeBody(configuration: Configuration) -> some View {
        LedgerButtonBody(configuration: configuration, tier: .secondary, size: size, fullWidth: fullWidth, tint: tint, passive: passive)
    }
}

/// Text only: Cancel, links, See all. Accent unless tinted.
struct TertiaryButtonStyle: ButtonStyle {
    var size: LedgerButtonSize = .regular
    var fullWidth = false
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        LedgerButtonBody(configuration: configuration, tier: .tertiary, size: size, fullWidth: fullWidth, tint: tint)
    }
}

/// The primary action of a screen that may be blocked: when `blockedReason` is set the button is disabled and the reason shows under it.
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

/// Cancel, Decline: the tertiary button in soft ink.
struct PlainTextButtonStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        TertiaryButtonStyle(tint: tint ?? P.inkSoft).makeBody(configuration: configuration)
    }
}

/// An important action: the primary button, hugging its label.
struct ImportantButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle().makeBody(configuration: configuration)
    }
}

/// An expensive or irreversible action: the secondary button with the text in `tint` (accent by default). Put the amount in the label.
struct FoilButtonStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(tint: tint ?? P.accent).makeBody(configuration: configuration)
    }
}

/// The footer of a popup card: the action as one capsule, Cancel as quiet text under it.
struct PopupFooter: View {
    @Environment(\.outsidePalette) private var P
    var cancel = "Cancel"
    var action: String
    /// Red for an irreversible action, gold foil for a spend.
    var tone: Tone = .normal
    var onCancel: () -> Void
    var onAction: () -> Void
    /// Greys out and blocks the left or right button (a Clear with nothing to clear, a Send until the form is complete).
    var cancelEnabled = true
    var actionEnabled = true
    /// Accessibility ids of the two buttons (UI tests find them by id).
    var cancelID = "confirm-cancel"
    var actionID = "confirm-go"

    enum Tone { case normal, expensive, destructive }

    /// The action as one capsule (the popup's tone; white for a neutral event), Cancel as quiet text under it. An irreversible action is a
    /// red press-and-hold button instead, so it can never run from a slip of the finger.
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

/// The pinned action row of a popup: a hairline, then the buttons on the card colour, full width. `.popupFooter { }` draws its content in this
/// bar under the scrolling body; build the content with `PopupFooter`, `PopupOptionButton` or a single highlighted button.
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

/// An inline validation or risk message inside a popup or a page: a small mark and a line in the warning colour.
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

