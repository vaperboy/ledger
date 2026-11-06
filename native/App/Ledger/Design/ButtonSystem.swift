import SwiftUI

// The three buttons of the game. Every older style below maps onto one of them.
//   Primary   : `PrimaryButtonStyle`, a solid accent capsule, accent ink. One per screen or popup (Next Day, Continue, Claim, Execute).
//   Secondary : `SecondaryButtonStyle`, a quiet capsule on a soft ink fill; `tint` colours text and fill (accent = recommended, loss = irreversible).
//   Tertiary  : `TertiaryButtonStyle`, text only (Cancel, See all, links).
//   Sizes     : `.regular` is 48 pt high; `.compact` draws 32 pt but keeps a 44 pt hit area. Disabled buttons look disabled themselves.
//   Blocked   : `PrimaryAction` shows the reason under a disabled primary button instead of fading it silently.

/// Height of a button: regular (48 pt) or compact (32 pt drawn inside a 44 pt hit area).
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
        switch tier {
        case .primary: return enabled ? (tint ?? P.accent) : P.inset
        case .secondary:
            guard enabled && !passive else { return P.inset }
            if let t = tint { return t.inPalette(P).opacity(0.14) }
            return P.ink.opacity(P.isLight ? 0.07 : 0.09)
        case .tertiary: return Color.clear
        }
    }

    var body: some View {
        let shape = Capsule(style: .continuous)
        let pressed: Bool = configuration.isPressed
        let step: TextStep = compact ? .body : .headline
        let weight: Font.Weight = tier == .primary ? .semibold : .medium
        let fillInk: Color? = tier == .primary ? textColor : nil
        configuration.label
            .textStyle(step, tint: textColor, weight: weight)
            // On the accent fill every Text of the label takes the fill's ink, even one styled inside the label.
            .transformEnvironment(\.containerInk) { (ink: inout Color?) in if let fillInk { ink = fillInk } }
            .lineLimit(1).minimumScaleFactor(0.85)
            .padding(.horizontal, tier == .tertiary ? Theme.Space.s : (compact ? Theme.Space.m : Theme.Space.l))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 32 : 48)
            .background(shape.fill(fillColor))
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

/// The footer of a popup card: Cancel on the left as the quiet capsule, the action on the right as the one filled capsule.
struct PopupFooter: View {
    @Environment(\.outsidePalette) private var P
    var cancel = "Cancel"
    var action: String
    /// Red for an irreversible action, gold for a spend.
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

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            PopupOptionButton(title: cancel, identifier: cancelID, action: onCancel)
                .disabled(!cancelEnabled)
            Button(action: { Haptics.play(tone == .destructive ? PopupCue.warning : PopupCue.tap); onAction() }) { Text(action) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true, tint: tone == .destructive ? P.loss : nil))
                .accessibilityIdentifier(actionID)
                .disabled(!actionEnabled)
        }
        .padding(.top, Theme.Space.xs)
    }
}

/// The pinned action row of a popup: the buttons on the card colour, full width, clear of the card's rounded bottom. `.popupFooter { }`
/// draws its content in this bar under the scrolling body; build the content with `PopupFooter`, `PopupOptionButton` or a single highlighted button.
struct PopupActionBar<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: PopupSpace.row) { content() }
            .padding(.horizontal, PopupMetrics.inset)
            .padding(.top, PopupSpace.block).padding(.bottom, PopupMetrics.inset)
            .frame(maxWidth: .infinity)
            .background(P.surfaceRaised)
            // Scrolling content fades out above the buttons instead of running into them.
            .background(alignment: .top) {
                LinearGradient(colors: [P.surfaceRaised.opacity(0), P.surfaceRaised], startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.Space.l).offset(y: -Theme.Space.l).allowsHitTesting(false)
            }
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

