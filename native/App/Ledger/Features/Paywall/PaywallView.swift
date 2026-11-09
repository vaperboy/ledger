import SwiftUI
import Simulation

/// The one paywall. The item that triggered it as the title, three plans as a radio list (yearly Plus preselected, monthly Plus, Pro
/// once), one primary buy button, Founder's as a text link, then Restore and the legal links. No timers, no fake discounts. Shown in a `.centerSheet` by `PaywallHost`.
struct PaywallView: View {
    let request: PaywallRequest
    @Environment(Entitlements.self) private var ent
    @Environment(AdCoordinator.self) private var ads
    @State private var choice: LedgerProduct = .plusYearly

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            header
            options
            buyButton
            if choice.isPlus { disclosure }
            if let note = ent.message { Text(note).textStyle(.caption) }
            passLink
            footer
        }
        .onChange(of: ent.isPro) { _, now in if now && request.feature != nil { ent.paywall = nil } }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !request.lead.isEmpty { Text(request.lead).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
            Text(request.title).textStyle(.title).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var options: some View {
        VStack(spacing: 0) {
            planCard(.plusYearly, title: "Ledger Plus, yearly", badge: ent.yearlySaving, detail: "Everything in Pro, ads removed. Season pass included: coming with the first season.")
            Hairline().padding(.leading, 22 + Theme.Space.m)
            planCard(.plusMonthly, title: "Ledger Plus, monthly", badge: "", detail: "")
            Hairline().padding(.leading, 22 + Theme.Space.m)
            if ent.ownsPro {
                ownedRow
            } else {
                planCard(.pro, title: "Ledger Pro, once", badge: "", detail: "Every locked item and three save slots, for good. Removes ads. Family Sharing on.")
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
        .accessibilityIdentifier("paywall-\(p.rawValue)")
    }

    /// The auto-renew terms of the selected Plus plan: price, period, trial, and the App Store's renewal rules.
    private var disclosure: some View {
        let price: String = ent.price(choice)
        let period: String = choice == .plusYearly ? "year" : "month"
        var lines: [String] = []
        if ent.trialEligible, let trial = ent.trialLength(choice) { lines.append("\(trial) free, then \(price) per \(period).") }
        else if !price.isEmpty { lines.append("\(price) per \(period).") }
        lines.append("Payment is charged to your Apple ID. The subscription renews automatically unless it is cancelled at least 24 hours before the period ends, and your account is charged for the renewal within 24 hours before it ends. Manage or cancel it in your App Store account settings.")
        return Text(lines.joined(separator: " ")).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("paywall-disclosure")
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
        .disabled(ent.isBusy || ent.price(choice).isEmpty)
        .accessibilityIdentifier("paywall-buy")
    }

    private var buyLabel: String {
        if ent.isBusy { return "Working..." }
        if choice.isPlus && ent.trialEligible { return "Start free trial" }
        return choice == .pro ? "Buy Ledger Pro" : "Subscribe"
    }

    /// Rewarded ad: Pro for 24 real hours, at most once per 7 days. Hidden when no ad can run.
    @ViewBuilder private var passLink: some View {
        if ads.canOfferPass {
            Button { Task { if await ads.watchForPass() { ent.paywall = nil } } } label: {
                Text("Try Pro for a day: watch an ad")
            }
            .buttonStyle(PopupTextActionStyle(tint: PopupTone.prestige.color))
            .disabled(ads.isShowing || ent.isBusy)
            .accessibilityIdentifier("paywall-pass")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Founder adds only a mark on top of Pro, so a Pro owner is not offered it.
            if !ent.ownsPro {
                Button { Task { await ent.purchase(.founder) } } label: {
                    Text("Founder's Edition: everything in Pro, once, with a Founder mark in Settings. \(ent.price(.founder))")
                        .textStyle(.caption).multilineTextAlignment(.leading).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(PlainTextButtonStyle(tint: Theme.ivoryMuted))
                .disabled(ent.isBusy || ent.price(.founder).isEmpty)
                .accessibilityIdentifier("paywall-founder")
            }
            HStack(spacing: 14) {
                Button { Task { await ent.restore() } } label: { Text("Restore purchases") }
                    .buttonStyle(PlainTextButtonStyle(tint: Theme.ivoryMuted))
                    .disabled(ent.isBusy)
                    .accessibilityIdentifier("paywall-restore")
                Link("Terms", destination: LedgerLinks.terms).textStyle(.caption)
                Link("Privacy", destination: LedgerLinks.privacy).textStyle(.caption)
            }
            Text("Ledger Pro and Founder's Edition are one-time purchases. Ledger Plus is a subscription.").textStyle(.caption, tint: Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Legal links the App Store requires next to a subscription. Replace `privacy` with your own policy URL before submission.
enum LedgerLinks {
    static let terms: URL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") ?? URL(fileURLWithPath: "/")
    static let privacy: URL = URL(string: "https://example.com/ledger/privacy") ?? URL(fileURLWithPath: "/")
}

/// Shows the paywall as a centred popup whenever `Entitlements.paywall` is set. Apply once, at the app root.
struct PaywallHost: ViewModifier {
    @Environment(Entitlements.self) private var ent

    func body(content: Content) -> some View {
        let binding: Binding<PaywallRequest?> = Binding(get: { ent.paywall }, set: { ent.paywall = $0 })
        return content.centerSheet(item: binding, title: "Ledger Pro", category: .detail, tone: .prestige) { (request: PaywallRequest) in
            PaywallView(request: request)
        }
    }
}

/// Once, when the first profitable month is done, the paywall rises with a line above it. Waits for the popups on screen
/// (report, celebration, unlocks) to finish, never shows to a paying player, and never twice (the mark is kept on the device).
struct PostM7Paywall: ViewModifier {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @State private var armed = false
    private static let shownKey = "ledger.paywallAfterM7Shown"

    private var m7Done: Bool {
        guard let e = store.engine else { return false }
        return PlayerGoals.ladder(e.state)?.first(where: { (g: PlayerGoals.LadderGoal) -> Bool in g.id == "M7" })?.done ?? false
    }

    private var shownBefore: Bool { UserDefaults.standard.bool(forKey: Self.shownKey) }

    /// The moment to show it: armed by the first profitable month being reached, nothing else on screen.
    private var ready: Bool { armed && !store.holdsHomeFigures && !store.popupOpen && ent.paywall == nil }

    func body(content: Content) -> some View {
        content
            .onChange(of: m7Done) { old, now in if now && !old && !shownBefore && !ent.isPro { armed = true } }
            .onChange(of: ready) { _, now in if now { show() } }
    }

    private func show() {
        armed = false
        guard !shownBefore, !ent.isPro else { return }
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        ent.paywall = PaywallRequest(title: "Ledger Pro", lead: "Your first profitable month. Pro opens the rest of the game and removes ads.")
    }
}
