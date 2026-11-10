import SwiftUI
import Countries

struct ConfirmPopup: View {
    var action: PendingAction
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var variant: PopupVariant {
        if action.destructive { return .destructive }
        return action.amount != nil ? .expensive : .standard
    }

    private var effect: String { action.message.tidyMoney.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var riskText: String {
        if !action.risk.isEmpty { return action.risk }
        return action.destructive ? "This cannot be undone." : ""
    }

    private var actionLabel: String {
        guard let amount = action.amount, let currency = action.currency, amount > 0, !action.destructive else { return action.button }
        let money: String = currency.tidyShort(amount)
        return action.button.contains(money) ? action.button : action.button + " · " + money
    }

    private var tone: PopupTone {
        if let t = action.tone { return t == .danger && !action.destructive ? .warning : t }
        if action.destructive { return .danger }
        return action.amount != nil ? .investment : .info
    }

    var body: some View {
        GamePopup(title: action.title, showsClose: false, variant: variant, category: .compact, tone: tone, icon: action.icon, onClose: onCancel) {
            VStack(spacing: Theme.Space.s) {
                if let amount = action.amount, let currency = action.currency {
                    Text(currency.tidyShort(amount))
                        .textStyle(.display, tint: tone.color, numeric: true)
                }
                if !effect.isEmpty {
                    Text(effect)
                        .textStyle(.headline, tint: Color.primary.opacity(0.62), weight: .regular)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !riskText.isEmpty {
                    Text(riskText)
                        .textStyle(.body, tint: action.destructive ? PopupTone.danger.color : PopupTone.warning.color, weight: .medium)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PopupFooter(action: actionLabel, tone: variant.footerTone, onCancel: onCancel, onAction: onConfirm)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
