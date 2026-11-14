import SwiftUI
import Simulation

struct ProPlansView: View {
    @Environment(Entitlements.self) private var ent
    @Environment(PurchaseManager.self) private var purchases
    @ObservedObject private var season = SeasonModel.shared
    private let session = StoreSession.shared
    @State private var proOpen = false

    /// The plan cards, the gold packs and the small print are shown in separate parts of the Store.
    enum Part { case offers, packs, legal }
    private let part: Part

    init(part: Part = .offers) { self.part = part }

    var body: some View {
        Group {
            switch part {
            case .offers: offers
            case .packs: packs
            case .legal: legal
            }
        }
        .task { await session.load(); await purchases.loadProducts() }
    }

    private var offers: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            plusCard
            proCard
            founderCard
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            footer
        }
    }

    private var footer: some View {
        HStack {
            Button { Task { await purchases.restore() } } label: { Text("Restore purchases") }
                .buttonStyle(PlainTextButtonStyle(tint: Theme.ivoryMuted))
                .disabled(purchases.isBusy)
                .accessibilityIdentifier("plans-restore")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
    }

    private func card<Actions: View>(title: String, line: String, owned: String?, tint: Color = StoreColors.violet, glow: Bool = false, id: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text(title.uppercased()).font(.title2.weight(.black)).italic().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let owned { StoreTag(text: owned, tint: StoreColors.yellow) }
            }
            Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(tint)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.white.opacity(glow ? 0.5 : 0.2), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
        .padding(.horizontal, Theme.Space.m)
    }

    /// Renewal terms and the legal links, shown directly under each subscription option.
    private var subscriptionTerms: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("Renews automatically at the price shown unless cancelled at least 24 hours before the period ends. Your Apple ID is charged within 24 hours before renewal. Manage or cancel in your App Store account settings.")
                .textStyle(.caption, tint: Color.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.l) {
                Link("Terms", destination: LedgerLinks.terms).textStyle(.caption, tint: StoreColors.yellow).frame(minHeight: 44)
                Link("Privacy", destination: LedgerLinks.privacy).textStyle(.caption, tint: StoreColors.yellow).frame(minHeight: 44)
            }
        }
        .accessibilityIdentifier("plans-disclosure")
    }

    private func optionRow<Action: View>(_ title: String, _ note: String, @ViewBuilder button: () -> Action) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.headline)
                if !note.isEmpty { Text(note).textStyle(.caption, tint: StoreColors.yellow).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: Theme.Space.s)
            button()
        }
    }

    private var plusCard: some View {
        let owned: String? = ent.isPlus ? "Active" : nil
        let monthly: String = purchases.price(.plan(.plusMonthly)) ?? ""
        return card(title: "Ledger Plus", line: "The Battle Pass premium track every season, a small profile flair and a profile icon.",
                    owned: owned, tint: StoreColors.blue, glow: owned == nil, id: "plan-plus") {
            if owned == nil && ent.snapshot.owned.contains(.proYearly) {
                Text("Included with your Pro subscription.").textStyle(.caption, tint: Color.white.opacity(0.85))
            } else if owned == nil {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    optionRow("Yearly", plusYearlyNote) {
                        PurchaseButton(item: .plan(.plusYearly), title: purchases.trialEligible ? "Try free" : "Subscribe", showsPrice: !purchases.trialEligible, minHeight: 44, identifier: "plan-" + LedgerProduct.plusYearly.rawValue)
                    }
                    optionRow("Monthly", monthly.isEmpty ? "" : monthly + " a month") {
                        PurchaseButton(item: .plan(.plusMonthly), title: "Subscribe", minHeight: 44, identifier: "plan-" + LedgerProduct.plusMonthly.rawValue)
                    }
                    subscriptionTerms
                }
            } else {
                plusManage
            }
        }
    }

    @ViewBuilder private var plusManage: some View {
        if ent.isPlus {
            Button { Haptics.tap(); Task { await ent.manageSubscription() } } label: {
                Text(ent.plusRenews.map { "Renews \($0.formatted(date: .abbreviated, time: .omitted)). Manage or cancel" } ?? "Manage or cancel")
                    .textStyle(.caption, tint: Theme.accent, weight: .semibold).frame(minHeight: 32, alignment: .leading)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("plans-manage")
        }
    }

    private var plusYearlyNote: String {
        let price: String = purchases.price(.plan(.plusYearly)) ?? ""
        if price.isEmpty { return "" }
        if purchases.trialEligible, let trial = purchases.trialLength(.plusYearly) { return "\(trial) free, then \(price) a year" }
        let saving: String = purchases.yearlySaving
        return price + " a year" + (saving.isEmpty ? "" : ", " + saving.lowercased() + " against monthly")
    }

    private var proCard: some View {
        let owned: String? = ent.ownsPro ? "Owned" : nil
        return card(title: "Ledger Pro", line: "A big gold bundle, \(StoreText.gold(GoldPrices.proBundleGold)), worth about 10 loot boxes, and an exclusive profile icon that cannot be traded.",
                    owned: owned, tint: StoreColors.purple, id: "plan-pro") {
            if owned == nil {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Spacer(minLength: 0)
                    Button { Haptics.tap(); withAnimation(.easeInOut(duration: 0.2)) { proOpen.toggle() } } label: {
                        Text(proOpen ? "Hide" : "Choose").textStyle(.headline, tint: Theme.accentInk)
                            .padding(.horizontal, Theme.Space.l).frame(minHeight: 44).background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("plan-pro-choose")
                }
                if proOpen {
                    Hairline()
                    optionRow("One-time purchase", "Pay once, yours for good") {
                        PurchaseButton(item: .plan(.pro), title: "Buy", minHeight: 40, identifier: "plan-" + LedgerProduct.pro.rawValue)
                    }
                    if !ent.isPlus {
                        optionRow("Subscription", "Renews every year until you cancel") {
                            PurchaseButton(item: .plan(.proYearly), title: "Subscribe", minHeight: 44, identifier: "plan-" + LedgerProduct.proYearly.rawValue)
                        }
                        subscriptionTerms
                    }
                }
            }
            }
        }
    }

    private var founderCard: some View {
        let onSale: Bool = PlanPerks.founderOnSale(season: season.pass.seasonNumber)
        let owned: String? = ent.isFounder ? "Owned" : nil
        return card(title: "Founder's Edition", line: "The top tier: \(StoreText.gold(GoldPrices.founderBundleGold)), a Founder flair, an exclusive pack of profile pictures and company logos, and the Season 1 Battle Pass with \(GoldPrices.founderPassTiers) tiers unlocked. Season 1 only, bought once.",
                    owned: owned, tint: StoreColors.orange, glow: onSale, id: "plan-founder") {
            if owned == nil && onSale {
                HStack {
                    Spacer(minLength: 0)
                    PurchaseButton(item: .plan(.founder), title: "Buy", minHeight: 44, identifier: "plan-" + LedgerProduct.founder.rawValue)
                }
            } else if owned == nil {
                Text("No longer on sale. It was only sold during Season 1.").textStyle(.caption, tint: Color.white.opacity(0.85))
            }
        }
    }

    private var packs: some View {
        let first: Bool = !session.state.firstPurchaseDone
        let best: String? = StorePurchase.bestPack?.id
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Gold packs").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(GoldStore.packs) { (pack: GoldPack) in
                    PackTile(pack: pack, first: first, best: pack.id == best)
                }
            }
            .padding(.horizontal, Theme.Space.m)
            if let problem = purchases.catalogError {
                Text(problem).textStyle(.caption, tint: Theme.warn).padding(.horizontal, Theme.Space.m)
            }
            Text(first ? "Your first pack carries a one-time bonus. Bigger packs give more gold for the same money." : "Bigger packs give more gold for the same money.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }
}
