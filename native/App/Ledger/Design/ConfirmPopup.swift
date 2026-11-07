import SwiftUI
import Countries

/// The in-game "Are you sure", a compact popup: what it costs, what it does, what can go wrong, then the action and Cancel.
/// Shown for a spend above the player's "Ask before spending" size and for an irreversible action (see `ConfirmThreshold`); an
/// irreversible action is confirmed by pressing and holding, never by a tap.
struct ConfirmPopup: View {
    var action: PendingAction
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var variant: PopupVariant {
        if action.destructive { return .destructive }
        return action.amount != nil ? .expensive : .standard
    }

    private var effect: String { action.message.tidyMoney.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What can go wrong, shown as the inline message under the rows.
    private var riskText: String {
        if !action.risk.isEmpty { return action.risk }
        return action.destructive ? "This cannot be undone." : ""
    }

    /// An expensive action carries its amount in the label, unless the label already says it.
    private var actionLabel: String {
        guard let amount = action.amount, let currency = action.currency, amount > 0, !action.destructive else { return action.button }
        let money: String = currency.tidyShort(amount)
        return action.button.contains(money) ? action.button : action.button + " · " + money
    }

    /// The event's accent: the call site's tone, else red for an irreversible action, champagne for a spend, otherwise information.
    private var tone: PopupTone {
        if let t = action.tone { return t }
        if action.destructive { return .danger }
        return action.amount != nil ? .investment : .info
    }

    /// Compact: icon ring and title (drawn by the frame), the amount as the one figure, the effect and the risk in one or two lines,
    /// then the action capsule (a hold button when irreversible) and Cancel.
    var body: some View {
        GamePopup(title: action.title, showsClose: false, variant: variant, category: .compact, tone: tone, icon: action.icon, onClose: onCancel) {
            VStack(spacing: Theme.Space.s) {
                if let amount = action.amount, let currency = action.currency {
                    Text(currency.tidyShort(amount))
                        .font(.system(size: 30, weight: .semibold, design: .serif).monospacedDigit())
                        .foregroundStyle(tone.color)
                }
                if !effect.isEmpty {
                    Text(effect)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !riskText.isEmpty {
                    Text(riskText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(action.destructive ? PopupTone.danger.color : PopupTone.warning.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PopupFooter(action: actionLabel, tone: variant.footerTone, onCancel: onCancel, onAction: onConfirm)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
