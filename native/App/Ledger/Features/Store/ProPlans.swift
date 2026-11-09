import SwiftUI
import Simulation

struct ProPlansView: View {
    @Environment(Entitlements.self) private var ent
    @State private var choice: LedgerProduct = .plusYearly

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            options
            buyButton
            if choice.isPlus { disclosure }
            if let note = ent.message { Text(note).textStyle(.caption) }
            footer
        }
    }

    @ViewBuilder private var options: some View {
        VStack(spacing: 0) {
            planCard(.plusYearly, title: "Ledger Plus, yearly", badge: ent.yearlySaving, detail: "Everything in Pro, ads removed, with the premium Season Pass track.")
            Hairline().padding(.leading, 22 + Theme.Space.m)
            planCard(.plusMonthly, title: "Ledger Plus, monthly", badge: "", detail: "")
            Hairline().padding(.leading, 22 + Theme.Space.m)
            if ent.ownsPro {
                ownedRow
            } else {
                planCard(.pro, title: "Ledger Pro, once", badge: "", detail: "Every locked item and three save slots, for good. Removes ads. Family Sharing on.")
                Hairline().padding(.leading, 22 + Theme.Space.m)
                planCard(.founder, title: "Founder's Edition, once", badge: "", detail: "Everything in Pro, with a Founder mark in Settings.")
            }
        }
    }

    private var ownedRow: some View {
        HStack(spacing: 8) {
            GlyphView(glyph: Glyph.check, size: 14, weight: 1.8, tint: Theme.gain)
            Text("Ledger Pro: Owned").textStyle(.body, weight: .medium)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.xs).frame(minHeight: 44)
    }

    private func planCard(_ p: LedgerProduct, title: String, badge: String, detail: String) -> some View {
        let on: Bool = choice == p
        return Button { Haptics.choose(); choice = p } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ZStack {
                    Circle().strokeBorder(on ? PopupTone.prestige.color : Theme.lineStrong, lineWidth: 1.5)
                    if on { Circle().fill(PopupTone.prestige.color).padding(5) }
                }
                .frame(width: 22, height: 22)
                .padding(.top, 1)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(title).textStyle(.headline)
                        Spacer(minLength: Theme.Space.s)
                        Text(priceLine(p)).textStyle(.body, tint: on ? Theme.ink : Theme.inkSoft, numeric: true, weight: on ? .semibold : nil)
                    }
                    if !badge.isEmpty { Text(badge).textStyle(.caption, tint: Theme.gain, weight: .semibold) }
                    if !detail.isEmpty { Text(detail).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
                    if p.isPlus, ent.trialEligible, let trial = ent.trialLength(p) { Text("\(trial) free, then \(priceLine(p))").textStyle(.caption, tint: Theme.inkSoft) }
                }
            }
            .padding(.vertical, Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("plan-\(p.rawValue)")
    }

    private var disclosure: some View {
        let price: String = ent.price(choice)
        let period: String = choice == .plusYearly ? "year" : "month"
        var lines: [String] = []
        if ent.trialEligible, let trial = ent.trialLength(choice) { lines.append("\(trial) free, then \(price) per \(period).") }
        else if !price.isEmpty { lines.append("\(price) per \(period).") }
        lines.append("Payment is charged to your Apple ID. The subscription renews automatically unless it is cancelled at least 24 hours before the period ends, and your account is charged for the renewal within 24 hours before it ends. Manage or cancel it in your App Store account settings.")
        return Text(lines.joined(separator: " ")).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("plans-disclosure")
    }

    private func priceLine(_ p: LedgerProduct) -> String {
        let price: String = ent.price(p)
        if price.isEmpty { return "" }
        switch p {
        case .plusYearly: return price + " / year"
        case .plusMonthly: return price + " / month"
        default: return price
        }
    }

    private var buyButton: some View {
        Button { Haptics.tap(); Task { await ent.purchase(choice) } } label: {
            Text(buyLabel)
        }
        .buttonStyle(PopupPrimaryCapsuleStyle(tone: .prestige))
        .disabled(ent.isBusy || ent.price(choice).isEmpty || (choice != .plusYearly && choice != .plusMonthly && ent.ownsPro))
        .accessibilityIdentifier("plans-buy")
    }

    private var buyLabel: String {
        if ent.isBusy { return "Working..." }
        if choice.isPlus && ent.trialEligible { return "Start free trial" }
        switch choice {
        case .pro: return "Buy Ledger Pro"
        case .founder: return "Buy Founder's Edition"
        default: return "Subscribe"
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Button { Task { await ent.restore() } } label: { Text("Restore purchases") }
                    .buttonStyle(PlainTextButtonStyle(tint: Theme.ivoryMuted))
                    .disabled(ent.isBusy)
                    .accessibilityIdentifier("plans-restore")
                Link("Terms", destination: LedgerLinks.terms).textStyle(.caption)
                Link("Privacy", destination: LedgerLinks.privacy).textStyle(.caption)
            }
            Text("Ledger Pro and Founder's Edition are one-time purchases. Ledger Plus is a subscription.").textStyle(.caption, tint: Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
