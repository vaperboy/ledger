import SwiftUI

// The three buttons of the game. Every older style below maps onto one of them.
//   Primary   : `PrimaryButtonStyle`, solid accent, accent ink. One per screen or popup (Next Day, Continue, Claim, Execute).
//   Secondary : `SecondaryButtonStyle`, a quiet outline with ink text; `tint` colours the text (accent = recommended, loss = irreversible).
//   Tertiary  : `TertiaryButtonStyle`, text only (Cancel, See all, links).
//   Sizes     : `.regular` is 44 pt high; `.compact` draws 32 pt but keeps a 44 pt hit area. Disabled buttons look disabled themselves.
//   Blocked   : `PrimaryAction` shows the reason under a disabled primary button instead of fading it silently.

/// Height of a button: regular (44 pt) or compact (32 pt drawn inside a 44 pt hit area).
enum LedgerButtonSize { case regular, compact }

/// The one body behind the three button styles.
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

    private var compact: Bool { size == .compact }

    private var textColor: Color {
        guard enabled else { return tier == .primary ? P.inkSoft : P.inkFaint }
        switch tier {
        case .primary: return P.accentInk
        case .secondary: return passive ? P.inkSoft : (tint ?? P.ink)
        case .tertiary: return tint ?? P.accent
        }
    }

    private var fillColor: Color {
        guard tier == .primary else { return Color.clear }
        return enabled ? (tint ?? P.accent) : P.inset
    }

    private var edgeColor: Color {
        guard tier == .secondary else { return Color.clear }
        if !enabled || passive { return P.line }
        if let t = tint, t == P.loss { return P.loss.opacity(0.6) }
        return P.lineStrong
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        let pressed: Bool = configuration.isPressed
        let step: TextStep = compact ? .body : .headline
        let weight: Font.Weight = tier == .primary ? .semibold : .medium
        configuration.label
            .textStyle(step, tint: textColor, weight: weight)
            .lineLimit(1).minimumScaleFactor(0.85)
            .padding(.horizontal, tier == .tertiary ? Theme.Space.s : (compact ? Theme.Space.m : Theme.Space.l))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 32 : 44)
            .background(shape.fill(fillColor))
            .overlay(shape.strokeBorder(edgeColor, lineWidth: 1))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(pressed ? 0.72 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.tap(reduceMotion), value: pressed)
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

/// The footer of a popup card: Cancel on the left, the action on the right, a hairline between them.
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

    /// Both buttons are the same neutral outline; a passive label such as Not now / Skip is grayed.
    var body: some View {
        HStack(spacing: 10) {
            PopupOptionButton(title: cancel, identifier: cancelID, action: onCancel)
                .disabled(!cancelEnabled)
            actionButton.disabled(!actionEnabled)
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var actionButton: some View {
        Group {
            switch tone {
            case .expensive:
                Button(action: { Haptics.play(.tap); onAction() }) { Text(action) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: P.accent)).accessibilityIdentifier(actionID)
            case .destructive:
                Button(action: { Haptics.play(.warning); onAction() }) { Text(action) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: P.loss)).accessibilityIdentifier(actionID)
            case .normal:
                PopupOptionButton(title: action, identifier: actionID, action: onAction)
            }
        }
    }
}

/// The pinned action row of a popup: a hairline, then the buttons on the card colour, full width. `.popupFooter { }` draws its content in this
/// bar under the scrolling body; build the content with `PopupFooter`, `PopupOptionButton` or a single highlighted button.
struct PopupActionBar<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            VStack(spacing: PopupSpace.row) { content() }
                .padding(.horizontal, PopupSpace.card)
                .padding(.top, PopupSpace.block).padding(.bottom, PopupSpace.block)
        }
        .frame(maxWidth: .infinity)
        .background(P.surfaceRaised)
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

