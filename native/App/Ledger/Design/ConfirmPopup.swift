import SwiftUI
import Countries

/// The in-game "Are you sure": what the action does (effect), what it costs and what can go wrong (risk), then "Cancel" and the action.
/// Shown only for a spend above the player's "Ask before spending" size and for an irreversible action (see `ConfirmThreshold`).
/// Text uses the popup roles; an expensive or irreversible action takes its declared variant (foil footer, red risk).
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

    var body: some View {
        GamePopup(title: action.title, showsClose: false, onClose: onCancel) {
            PopupBody {
                if let amount = action.amount, let currency = action.currency {
                    PopupRow(label: "Cost", value: currency.tidyShort(amount), variant: variant)
                }
                if !effect.isEmpty {
                    VStack(alignment: .leading, spacing: PopupSpace.tight) {
                        Text("Effect").popupText(.rowLabel)
                        Text(effect).popupText(.body)
                    }
                }
                if !riskText.isEmpty { InlineMessage(text: riskText, isError: action.destructive) }
                PopupFooter(action: actionLabel, tone: variant.footerTone, onCancel: onCancel, onAction: onConfirm)
            }
        }
    }
}
