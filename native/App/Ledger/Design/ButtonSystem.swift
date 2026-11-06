import SwiftUI

// The game's button and alert system (dark ledger look). Phone sizes: compact
// buttons that hug their label, never wide-format; the Cancel | Apply footer is the only place two actions share a row.
//   Basic / secondary : `PlainTextButtonStyle` (Cancel, Decline) and the existing `GreyOutlineButtonStyle` (Back, View documents).
//   Important         : `ImportantButtonStyle`, a gold-filled button (Verify, Authorize, Execute).
//   Expensive         : `FoilButtonStyle`, a gold-foil outline with the amount in the label ("Acquire asset - 12,500,000").
//   Popup footer      : `PopupFooter` (Cancel | Apply).
//   Sole action       : `PopupPrimaryButtonStyle` / `PopupOptionButton(highlighted: true)`; on a celebration card `ClaimButton` (Celebration.swift), the same button with a pulse.
//   Haptics           : every popup button plays a soft tap, a destructive footer a warning, a claim a success (`Haptics.play`).

private let goldInk = PopupInk.onGold

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
            .background(RoundedRectangle(cornerRadius: PopupRadius.control, style: .continuous)
                .fill(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .top, endPoint: .bottom)))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .modifier(PopupPressFeedback(pressed: configuration.isPressed))
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
            .background(RoundedRectangle(cornerRadius: PopupRadius.control, style: .continuous).fill(c.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: PopupRadius.control, style: .continuous).strokeBorder(c.opacity(0.85), lineWidth: 1.2))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .modifier(PopupPressFeedback(pressed: configuration.isPressed))
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
                .disabled(!cancelEnabled).opacity(cancelEnabled ? 1 : 0.4)
            actionButton.disabled(!actionEnabled).opacity(actionEnabled ? 1 : 0.4)
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var actionButton: some View {
        Group {
            switch tone {
            case .expensive:
                Button(action: { Haptics.play(.tap); onAction() }) { Text(action) }
                    .buttonStyle(FoilButtonStyle()).accessibilityIdentifier(actionID)
            case .destructive:
                Button(action: { Haptics.play(.warning); onAction() }) { Text(action) }
                    .buttonStyle(FoilButtonStyle(tint: P.loss)).accessibilityIdentifier(actionID)
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
            Rectangle().fill(P.line).frame(height: 1)
            VStack(spacing: PopupSpace.row) { content() }
                .padding(.horizontal, PopupSpace.card)
                .padding(.top, PopupSpace.block).padding(.bottom, PopupSpace.block)
        }
        .frame(maxWidth: .infinity)
        .background(P.card)
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

