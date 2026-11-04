import SwiftUI
import Simulation

/// Brief 11.4: the one paywall. The item that triggered it on top, three option cards (yearly Plus preselected, monthly Plus, Pro once),
/// Founder's as a text link, then Restore and the legal links. No timers, no fake discounts. Shown in a `.centerSheet` by `PaywallHost`.
struct PaywallView: View {
    let request: PaywallRequest
    @Environment(Entitlements.self) private var ent
    @Environment(AdCoordinator.self) private var ads
    @State private var choice: LedgerProduct = .plusYearly

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header
            options
            buyButton
            if let note = ent.message { Text(note).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted) }
            passLink
            footer
        }
        .onChange(of: ent.isPro) { _, now in if now && request.feature != nil { ent.paywall = nil } }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !request.lead.isEmpty { Text(request.lead).font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            Text(request.title).font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            Text("No purchase changes a number in the game. Pro unlocks more of it and removes ads.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var options: some View {
        VStack(spacing: Theme.Space.s) {
            planCard(.plusYearly, title: "Ledger Plus, yearly", badge: ent.yearlySaving, detail: "Everything in Pro, plus Advisor, auto-week, cloud backup and early access.")
            planCard(.plusMonthly, title: "Ledger Plus, monthly", badge: "", detail: "Same as yearly, billed monthly.")
            if ent.ownsPro {
                ownedRow
            } else {
                planCard(.pro, title: "Ledger Pro, once", badge: "", detail: "Every locked item, for good. Removes ads. Family Sharing on.")
            }
        }
    }

    private var ownedRow: some View {
        HStack(spacing: 8) {
            GlyphView(glyph: Glyph.check, size: 14, weight: 1.8, tint: Theme.gain)
            Text("Ledger Pro: Owned").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).frame(minHeight: 36)
    }

    private func planCard(_ p: LedgerProduct, title: String, badge: String, detail: String) -> some View {
        let on: Bool = choice == p
        return Button { choice = p } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ivory)
                    if !badge.isEmpty { Text(badge).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.gain) }
                    Spacer(minLength: 8)
                    Text(priceLine(p)).font(.system(size: 14).monospacedDigit()).foregroundStyle(on ? Theme.gold : Theme.ivoryMuted)
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                if p.isPlus && ent.trialEligible { Text("7 days free, then \(ent.price(p))").font(.system(size: 12)).foregroundStyle(Theme.gold) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(on ? Theme.goldSelected : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(on ? Theme.gold : Theme.border, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("paywall-\(p.rawValue)")
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
        Button { Task { await ent.purchase(choice) } } label: {
            Text(buyLabel).frame(maxWidth: .infinity)
        }
        .buttonStyle(ImportantButtonStyle())
        .disabled(ent.isBusy || ent.price(choice).isEmpty)
        .accessibilityIdentifier("paywall-buy")
    }

    private var buyLabel: String {
        if ent.isBusy { return "Working..." }
        if choice.isPlus && ent.trialEligible { return "Start free trial" }
        return choice == .pro ? "Buy Ledger Pro" : "Subscribe"
    }

    /// Rewarded ad: Pro for 24 real hours, at most once per 7 days (brief 11.5.3). Hidden when no ad can run.
    @ViewBuilder private var passLink: some View {
        if ads.canOfferPass {
            Button { Task { if await ads.watchForPass() { ent.paywall = nil } } } label: {
                Text("Try Pro for a day: watch an ad")
            }
            .buttonStyle(PlainTextButtonStyle(tint: Theme.gold))
            .accessibilityIdentifier("paywall-pass")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !ent.ownsPro {
                Button { Task { await ent.purchase(.founder) } } label: {
                    Text("Founder's Edition: Pro, your name in the Rich List, a gold icon and future packs. \(ent.price(.founder))")
                        .font(.system(size: 12.5)).multilineTextAlignment(.leading)
                }
                .buttonStyle(PlainTextButtonStyle(tint: Theme.ivoryMuted))
                .disabled(ent.price(.founder).isEmpty)
            }
            HStack(spacing: 14) {
                Button { Task { await ent.restore() } } label: { Text("Restore purchases") }
                    .buttonStyle(PlainTextButtonStyle(tint: Theme.ivoryMuted))
                    .accessibilityIdentifier("paywall-restore")
                Link("Terms", destination: LedgerLinks.terms).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                Link("Privacy", destination: LedgerLinks.privacy).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            }
            Text("Plus renews until cancelled. Manage it in your App Store account settings.").font(.system(size: 11)).foregroundStyle(Theme.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Legal links the App Store requires next to a subscription. Owner: replace `privacy` with your own policy URL before submission.
enum LedgerLinks {
    static let terms: URL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") ?? URL(fileURLWithPath: "/")
    static let privacy: URL = URL(string: "https://example.com/ledger/privacy") ?? URL(fileURLWithPath: "/")
}

/// Shows the paywall as a centred popup whenever `Entitlements.paywall` is set. Apply once, at the app root.
struct PaywallHost: ViewModifier {
    @Environment(Entitlements.self) private var ent

    func body(content: Content) -> some View {
        let binding: Binding<PaywallRequest?> = Binding(get: { ent.paywall }, set: { ent.paywall = $0 })
        return content.centerSheet(item: binding, title: "Ledger Pro") { (request: PaywallRequest) in
            PaywallView(request: request)
        }
    }
}
