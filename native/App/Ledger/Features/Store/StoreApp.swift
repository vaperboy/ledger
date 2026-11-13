import SwiftUI
import StoreKit
import Simulation

struct StoreApp: View {
    @Environment(OnlineSession.self) private var online
    @Environment(PurchaseManager.self) private var purchases
    private let session = StoreSession.shared
    @State private var showRedeem = false
    @State private var showInfo = false
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0

    var body: some View {
        let paid: Bool = paidBoxesAllowed
        PhonePageScroll(spacing: Theme.Space.xl) {
            StoreOffersSection(ask: ask).storeAppear(0)
            StoreBundlesSection(ask: ask).storeAppear(1)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                StoreBand(title: "Boxes", glyph: Glyph.luxury)
                lootBoxes(paid: paid)
            }
            .storeAppear(2)
            stockGroup(paid: paid)
            StoreCosmeticsSection(ask: ask).storeAppear(3)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                StoreBand(title: "Gold", glyph: Glyph.bank)
                ProPlansView(part: .packs)
            }
            StoreMoneySection(ask: ask).storeAppear(4)
            collectionGroup
            ProPlansView(part: .legal)
            footer
        }
        .appScreen(title: "Store", subtitle: "") { StoreGoldChip(amount: session.gold) }
        .confirmAction($pending)
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") {
            ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false })
        }
        .centerSheet(isPresented: $showInfo, title: "Odds and rules", size: .tall) { LootBoxInfoSheet(kind: .cabinet, others: [.grand] + BoxKind.cardPacks) }
        .offerCodeRedemption(isPresented: $showRedeem) { _ in Task { await purchases.codeRedeemed() } }
        .task { await session.load(); await purchases.loadProducts() }
    }

    private func ask(_ good: GoldGood) {
        StorePurchase.ask(good, pending: $pending, onShort: { (price: Int) in shortNeed = price; shortOfGold = true })
    }

    private var paidBoxesAllowed: Bool {
        if case .open(let paid) = StoreGate.access(countryCode: online.profile?.countryCode) { return paid }
        return false
    }

    private func lootBoxes(paid: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Loot boxes").capsLabel(Theme.inkFaint)
                Spacer()
                LootInfoButton { showInfo = true }
            }
            .padding(.horizontal, Theme.Space.m)
            if paid {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(Array(BoxKind.standard.filter { $0.isPaid }.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                        NavigationLink { BoxView(kind: kind, paidBoxesAllowed: true) } label: { BoxTile(kind: kind, index: i) }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("store-box-" + kind.rawValue)
                    }
                }
                Text("Card packs").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m).padding(.top, Theme.Space.s)
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    ForEach(Array(BoxKind.cardPacks.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                        NavigationLink { BoxView(kind: kind, paidBoxesAllowed: true) } label: { BoxTile(kind: kind, index: i + 2) }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("store-box-" + kind.rawValue)
                    }
                }
                Text("Profile and company cards to customise with. A pricier pack has better odds of rare and animated cards, and the odds are shown before you open one.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
            } else {
                Text("Paid boxes are not offered where you are. Season boxes can still be opened.")
                    .textStyle(.body, tint: Theme.inkSoft).padding(.horizontal, Theme.Space.m)
            }
        }
    }

    @ViewBuilder private func stockGroup(paid: Bool) -> some View {
        let kinds: [BoxKind] = BoxKind.allCases.filter { session.state.count($0) > 0 && (!$0.isPaid || paid) }
        if !kinds.isEmpty {
            OnlineGroup(title: "Boxes you have", footer: "") {
                ForEach(Array(kinds.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                    if i > 0 { Hairline() }
                    NavigationLink { BoxView(kind: kind, paidBoxesAllowed: paid) } label: {
                        OnlineLine(glyph: Glyph.luxury, title: kind.title, note: "Open it", value: "\(session.state.count(kind))", chevron: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var collectionGroup: some View {
        OnlineGroup(title: "Collection", footer: "") {
            NavigationLink { CabinetView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Artifacts and cards", note: "Your pieces, collections and sales", chevron: true) }
                .buttonStyle(PressableStyle())
            Hairline()
            NavigationLink { StoreShelfView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Cosmetics and bundles", note: "Bought with gold", chevron: true) }
                .buttonStyle(PressableStyle())
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.l) {
                if purchases.offerCodesAvailable {
                    Button { Haptics.tap(); showRedeem = true } label: { Text("Redeem a code").textStyle(.caption, tint: Theme.accent, weight: .semibold).frame(minHeight: 32) }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("store-redeem")
                }
                Link("Terms", destination: LedgerLinks.terms).textStyle(.caption)
                Link("Privacy", destination: LedgerLinks.privacy).textStyle(.caption)
            }
            Text(StoreText.goldRule).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.m)
    }
}
