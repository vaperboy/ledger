import SwiftUI
import Simulation

struct PaywallView: View {
    let request: PaywallRequest
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AdCoordinator.self) private var ads

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                if !request.lead.isEmpty { Text(request.lead).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
                Text(request.title).textStyle(.title).fixedSize(horizontal: false, vertical: true)
            }
            Text("This extra is part of Ledger Pro and Ledger Plus. It adds comfort and looks, never game progress. Every plan and price is in the Store.").textStyle(.body, tint: Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                ent.paywall = nil
                StorePurchase.afterPopup { store.openApp(.store) }
            } label: { Text("Open the Store") }
                .buttonStyle(PopupPrimaryCapsuleStyle(tone: .prestige))
                .accessibilityIdentifier("paywall-store")
            passLink
        }
        .onChange(of: ent.isPro) { _, now in if now && request.feature != nil { ent.paywall = nil } }
    }

    @ViewBuilder private var passLink: some View {
        if ads.canOfferPass {
            Button { Task { if await ads.watchForPass() { ent.paywall = nil } } } label: {
                Text("Try Pro for a day: watch an ad")
            }
            .buttonStyle(PopupTextActionStyle(tint: PopupTone.prestige.color))
            .disabled(ads.isShowing || purchases.isBusy)
            .accessibilityIdentifier("paywall-pass")
        }
    }
}

enum LedgerLinks {
    static let terms: URL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") ?? URL(fileURLWithPath: "/")
    static let privacy: URL = URL(string: "https://example.com/ledger/privacy") ?? URL(fileURLWithPath: "/")
}

struct PaywallHost: ViewModifier {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent

    func body(content: Content) -> some View {
        let binding: Binding<PaywallRequest?> = Binding(get: { ent.paywall }, set: { ent.paywall = $0 })
        return content.centerSheet(item: binding, title: "Ledger Pro", category: .detail, tone: .prestige) { (request: PaywallRequest) in
            PaywallView(request: request).environmentObject(store)
        }
    }
}

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
        ent.paywall = PaywallRequest(title: "Ledger Pro", lead: "Your first profitable month. Pro adds save slots, cloud backup, Insights and themes, and removes ads. The whole game stays free.")
    }
}
