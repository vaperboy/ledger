import SwiftUI
import Countries

/// The one in-game popup frame: a dimmed backdrop (tap outside to close) and a themed card with a title and, optionally, the small x.
/// The "Are you sure" question and the Perks list both use it, so every popup in the game looks and closes the same way. It takes the
/// palette of the screen that opened it (an outside app keeps its own colours).
struct GamePopup<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var title: String
    var showsClose = true
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .accessibilityIdentifier("popup-backdrop")
            card
                .padding(.horizontal, 22)
                .scaleEffect(shown || reduceMotion ? 1 : 0.95)
                .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(Motion.arrive(reduceMotion)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content()
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.serifTitle(20)).foregroundStyle(P.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if showsClose {
                Button { onClose() } label: {
                    GlyphView(glyph: Glyph.close, size: 14, weight: 1.8, tint: P.ink)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(P.lineStrong, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle()).accessibilityLabel("Close").accessibilityIdentifier("popup-close")
            }
        }
    }
}

/// One line of the "Are you sure" card: a small label (Cost, Effect, Risk) and the text under it.
private struct ConfirmLine: Identifiable {
    let id: Int
    var label: String
    var text: String
    var risky: Bool
}

/// The in-game "Are you sure": what the action does (effect), what it costs and what can go wrong (risk), then "Cancel" and the action.
/// Shown only for a spend above the player's "Ask before spending" size and for an irreversible action (see `ConfirmThreshold`).
struct ConfirmPopup: View {
    @Environment(\.outsidePalette) private var P
    var action: PendingAction
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var lines: [ConfirmLine] {
        var out: [ConfirmLine] = []
        if let amount = action.amount, let currency = action.currency {
            out.append(ConfirmLine(id: out.count, label: "Cost", text: currency.tidyShort(amount), risky: false))
        }
        let effect: String = action.message.tidyMoney.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effect.isEmpty {
            out.append(ConfirmLine(id: out.count, label: "Effect", text: effect, risky: false))
        }
        let risk: String = action.risk.isEmpty ? (action.destructive ? "This cannot be undone." : "") : action.risk
        if !risk.isEmpty {
            out.append(ConfirmLine(id: out.count, label: "Risk", text: risk, risky: true))
        }
        return out
    }

    var body: some View {
        GamePopup(title: action.title, showsClose: false, onClose: onCancel) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.label).capsLabel(line.risky ? P.loss : nil)
                        Text(line.text)
                            .font(.system(size: 14)).foregroundStyle(P.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                buttons
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Cancel") { Haptics.tap(); onCancel() }
                .buttonStyle(GreyOutlineButtonStyle())
                .accessibilityIdentifier("confirm-cancel")
            Button(action.button) { Haptics.tap(); onConfirm() }
                .buttonStyle(QuietButtonStyle(tint: action.destructive ? P.loss : nil))
                .accessibilityIdentifier("confirm-go")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
    }
}
