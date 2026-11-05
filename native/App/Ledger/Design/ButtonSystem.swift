import SwiftUI

// The game's button and alert system (dark ledger look). Phone sizes: compact
// buttons that hug their label, never wide-format; the Cancel | Apply footer is the only place two actions share a row.
//   Basic / secondary : `PlainTextButtonStyle` (Cancel, Decline) and the existing `GreyOutlineButtonStyle` (Back, View documents).
//   Important         : `ImportantButtonStyle`, a gold-filled button (Verify, Authorize, Execute).
//   Expensive         : `FoilButtonStyle`, a gold-foil outline with the amount in the label ("Acquire asset - 12,500,000").
//   Popup footer      : `PopupFooter` (Cancel | Apply).

private let goldInk = Color(red: 0.09, green: 0.075, blue: 0.055)

/// Cancel, Decline: text only, no box.
struct PlainTextButtonStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint ?? P.inkSoft)
            .padding(.horizontal, 14).frame(minHeight: 40)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// An important action: a gold-filled button that hugs its label (compact, not wide).
struct ImportantButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(goldInk)
            .padding(.horizontal, 18).frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous)
                .fill(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .top, endPoint: .bottom)))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// An expensive action: a gold-foil outline with a faint gold wash. Put the amount in the label.
struct FoilButtonStyle: ButtonStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        let c: Color = tint ?? Theme.gold
        return configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle(c)
            .padding(.horizontal, 16).frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(c.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(c.opacity(0.85), lineWidth: 1.2))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1)
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

    enum Tone { case normal, expensive, destructive }

    /// Both buttons are the same neutral outline; a passive label such as Not now / Skip is grayed.
    var body: some View {
        HStack(spacing: 10) {
            PopupOptionButton(title: cancel, identifier: "confirm-cancel", action: onCancel)
            switch tone {
            case .expensive:
                Button(action: { Haptics.tap(); onAction() }) { Text(action) }
                    .buttonStyle(FoilButtonStyle()).accessibilityIdentifier("confirm-go")
            case .destructive:
                Button(action: { Haptics.tap(); onAction() }) { Text(action) }
                    .buttonStyle(FoilButtonStyle(tint: P.loss)).accessibilityIdentifier("confirm-go")
            case .normal:
                PopupOptionButton(title: action, identifier: "confirm-go", action: onAction)
            }
        }
        .padding(.top, 4)
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

