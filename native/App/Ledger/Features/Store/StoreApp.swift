import SwiftUI
import StoreKit
import Simulation

struct StoreApp: View {
    @Environment(OnlineSession.self) private var online
    @Environment(PurchaseManager.self) private var purchases
    private let session = StoreSession.shared
    @State private var showRedeem = false
    @State private var redeemStart = ""
    @State private var gift: ServerGiftReward?
    @State private var showGift = false
    @State private var showAppleCode = false
    @State private var showInfo = false
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0

    var body: some View {
        let paid: Bool = paidBoxesAllowed
        PhonePageScroll(spacing: Theme.Space.xl) {
            RedeemGiftRow { (start: String) in redeemStart = start; showRedeem = true }
            StoreOffersSection(ask: ask).storeAppear(0)
            StoreShelfSection(ask: ask).storeAppear(1)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                StoreBand(title: "Boxes", glyph: Glyph.luxury, tint: StoreColors.orange)
                lootBoxes(paid: paid)
            }
            .storeAppear(2)
            stockGroup(paid: paid)
            StoreBundlesSection(ask: ask)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                StoreBand(title: "Gold", glyph: Glyph.bank, tint: StoreColors.red)
                ProPlansView(part: .packs)
            }
            StoreMoneySection(ask: ask)
            StoreFreeGoldSection()
            collectionGroup
            ProPlansView(part: .legal)
            footer
        }
        .overlay(alignment: .bottomTrailing) {
            AdGoldBubble().padding(.trailing, Theme.Space.m).padding(.bottom, Theme.Space.m)
        }
        .appScreen(title: "Store", subtitle: "") { StoreGoldChip(amount: session.gold) }
        .confirmAction($pending)
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") {
            ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false })
        }
        .centerSheet(isPresented: $showInfo, title: "Odds and rules", size: .tall) { LootBoxInfoSheet(kind: .cabinet, others: [.grand] + BoxKind.cardPacks) }
        .centerSheet(isPresented: $showRedeem, title: "Redeem a code") {
            RedeemCodeCard(startCode: redeemStart,
                           onGift: { (reward: ServerGiftReward) in showRedeem = false; StorePurchase.afterPopup { gift = reward; showGift = true } },
                           onAppleCode: purchases.offerCodesAvailable ? { showRedeem = false; StorePurchase.afterPopup { showAppleCode = true } } : nil)
        }
        .centerSheet(isPresented: $showGift, title: "Gift received") {
            if let gift { GiftReceivedCard(reward: gift, onDone: { showGift = false }) }
        }
        .offerCodeRedemption(isPresented: $showAppleCode) { _ in Task { await purchases.codeRedeemed() } }
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
                Text("Open now or keep in stock").capsLabel(Theme.inkFaint)
                Spacer()
                LootInfoButton { showInfo = true }
            }
            .padding(.horizontal, Theme.Space.m)
            if paid {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    ForEach(Array(BoxKind.standard.filter { $0.isPaid }.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                        NavigationLink { BoxView(kind: kind, paidBoxesAllowed: true) } label: { BoxTile(kind: kind, index: i) }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("store-box-" + kind.rawValue)
                    }
                }
                .padding(.horizontal, Theme.Space.m)
                Text("Card packs").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m).padding(.top, Theme.Space.s)
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    ForEach(Array(BoxKind.cardPacks.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                        NavigationLink { BoxView(kind: kind, paidBoxesAllowed: true) } label: { BoxTile(kind: kind, index: i + 2) }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("store-box-" + kind.rawValue)
                    }
                }
                .padding(.horizontal, Theme.Space.m)
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
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.l) {
                Link("Terms", destination: LedgerLinks.terms).textStyle(.caption)
                Link("Privacy", destination: LedgerLinks.privacy).textStyle(.caption)
            }
            Text(StoreText.goldRule).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.m)
    }
}
