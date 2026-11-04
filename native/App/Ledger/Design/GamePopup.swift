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
    /// False: only the popup's own button closes it (the daily report, so a player cannot tap through it).
    var dismissOnBackdrop = true
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var shown = false

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if dismissOnBackdrop { onClose() } }
                    .accessibilityIdentifier("popup-backdrop")
                card(room: geo.size.height * PopupMetrics.roomFraction)
                    .frame(maxWidth: PopupMetrics.maxWidth)
                    .padding(.horizontal, PopupMetrics.margin)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.95)
                    .opacity(shown ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { Motion.animate(Motion.arrive(reduceMotion)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Same card as `CenterSheetFrame`: 44pt header row (title, optional x), content hugging its height, at most 80% of the screen,
    /// scrolling only when taller.
    private func card(room: CGFloat) -> some View {
        let bodyRoom: CGFloat = max(120, room - PopupMetrics.header - 1)
        return VStack(spacing: 0) {
            PopupHeaderRow(title: title, showsClose: showsClose, onClose: onClose)
            FitScroll(maxHeight: bodyRoom) {
                VStack(alignment: .leading, spacing: 12) { content() }.padding(16)
            }
        }
        .foregroundStyle(P.ink)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
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
        return out
    }

    /// What can go wrong, shown as the inline message under the rows.
    private var riskText: String {
        if !action.risk.isEmpty { return action.risk }
        return action.destructive ? "This cannot be undone." : ""
    }

    private var tone: PopupFooter.Tone {
        if action.destructive { return .destructive }
        return action.amount != nil ? .expensive : .normal
    }

    /// An expensive action carries its amount in the label, unless the label already says it.
    private var actionLabel: String {
        guard let amount = action.amount, let currency = action.currency, amount > 0, !action.destructive else { return action.button }
        let money: String = currency.tidyShort(amount)
        return action.button.contains(money) ? action.button : action.button + " · " + money
    }

    var body: some View {
        GamePopup(title: action.title, showsClose: false, onClose: onCancel) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.label).capsLabel()
                        Text(line.text)
                            .font(.system(size: 14)).foregroundStyle(P.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !riskText.isEmpty { InlineMessage(text: riskText, isError: action.destructive) }
                PopupFooter(action: actionLabel, tone: tone, onCancel: onCancel, onAction: onConfirm)
            }
        }
    }
}
