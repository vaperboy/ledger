import SwiftUI
import Simulation

/// The Store app: your gold, boxes with their odds, gold packs with value deals, box bundles and cosmetics. Only for players who confirmed they are
/// 18 or older (anyone else sees an explanation, never the offers). No timers, no limited offers, nothing that repeats.
struct StoreApp: View {
    @Environment(OnlineSession.self) private var online
    private let session = StoreSession.shared
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var showPacks = false
    /// Read so the page redraws when the age answer changes.
    @AppStorage(AgeConfirmation.key) private var adultFlag = false

    var body: some View {
        let access: StoreAccess.Access = adultFlag ? StoreGate.access(countryCode: online.profile?.countryCode) : .hidden
        Group {
            switch access {
            case .hidden:
                StoreAgeGate()
            case .open(let paid):
                PhonePageScroll(spacing: Theme.Space.l) {
                    walletCard
                    if paid { boxesGroup } else { regionNote }
                    stockGroup
                    if paid { bundlesGroup }
                    packsGroup
                    cosmeticsGroup
                    moreGroup
                    Text(StoreText.goldRule).textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
                }
                .confirmAction($pending)
                .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") { ShortOfGoldCard(onPacks: { shortOfGold = false; showPacks = true }) }
                .navigationDestination(isPresented: $showPacks) { GoldPacksView() }
            }
        }
        .appScreen(title: "Store", subtitle: "Gold, boxes and cosmetics")
        .task { await session.load() }
    }

    // MARK: Wallet

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Your gold").capsLabel()
            GoldAmount(amount: session.gold, style: .display)
            if session.state.wallet.held > 0 {
                Text("\(StoreText.gold(session.state.wallet.held)) held for leading bids. \(StoreText.gold(session.available)) available.").textStyle(.caption)
            }
            if session.isVisualOnly {
                Text("Preview store: nothing is charged and no real purchase happens in this build.").textStyle(.caption)
            }
            NavigationLink { GoldPacksView() } label: { Text("Get gold").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("store-get-gold")
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: Theme.Radius.hero)
    }

    // MARK: Boxes

    private var boxesGroup: some View {
        OnlineGroup(title: "Boxes", footer: "Every box shows its exact odds here and on its page. \(session.state.pity.text)") {
            ForEach(Array(BoxKind.allCases.filter { $0.isPaid }.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                if i > 0 { Hairline() }
                NavigationLink { BoxView(kind: kind, paidBoxesAllowed: true) } label: { boxRow(kind) }
                    .buttonStyle(PressableStyle())
            }
        }
    }

    private func boxRow(_ kind: BoxKind) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                ItemArt(box: kind, size: 36)
                Text(kind.title).textStyle(.headline)
                Spacer()
                GoldAmount(amount: kind.price)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            Text(oddsLine(kind)).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Space.s).frame(minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func oddsLine(_ kind: BoxKind) -> String {
        BoxOdds.rarityPercent(kind).map { "\($0.rarity.title) \(String(format: "%.2f", $0.percent))%" }.joined(separator: "  ·  ")
    }

    private var regionNote: some View {
        OnlineGroup(title: "Boxes", footer: "") {
            Text("Paid boxes are not offered where you are. Season boxes can still be opened.").textStyle(.body, tint: Theme.inkSoft).padding(.vertical, Theme.Space.m)
        }
    }

    /// Free boxes and boxes from bundles waiting to be opened.
    @ViewBuilder private var stockGroup: some View {
        let kinds: [BoxKind] = BoxKind.allCases.filter { session.state.count($0) > 0 }
        if !kinds.isEmpty {
            OnlineGroup(title: "Boxes you have", footer: "") {
                ForEach(Array(kinds.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                    if i > 0 { Hairline() }
                    NavigationLink { BoxView(kind: kind, paidBoxesAllowed: StoreGate.access(countryCode: online.profile?.countryCode) == .open(paidBoxes: true)) } label: {
                        OnlineLine(glyph: Glyph.luxury, title: kind.title, note: "Open it, odds shown first", value: "\(session.state.count(kind))", chevron: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var bundlesGroup: some View {
        OnlineGroup(title: "Box bundles", footer: "Bought with gold. The boxes wait in your stock; each one shows its odds when you open it.") {
            ForEach(Array(GoldStore.boxBundles.enumerated()), id: \.element.id) { (i: Int, b: BoxBundle) in
                if i > 0 { Hairline() }
                Button { askBundle(b) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(b.count) \(b.kind.title)es").textStyle(.headline)
                            Text("\(b.savingPercent)% less than \(b.count) single boxes (\(StoreText.gold(b.singlesPrice)))").textStyle(.caption)
                        }
                        Spacer()
                        GoldAmount(amount: b.price)
                    }
                    .padding(.vertical, Theme.Space.s).frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func askBundle(_ b: BoxBundle) {
        if session.available < b.price { shortOfGold = true; return }
        pending = PendingAction(title: "Buy \(b.count) \(b.kind.title)es?", message: "Costs \(StoreText.gold(b.price)). The boxes go into your stock; nothing is opened yet.", button: "Buy",
                                alwaysAsk: true, tone: .investment, icon: "shippingbox") {
            Task { if await session.buyBoxBundle(b, paidBoxesAllowed: true) { Haptics.success() } }
        }
    }

    // MARK: Packs

    private var packsGroup: some View {
        let first: Bool = !session.state.firstPurchaseDone
        return OnlineGroup(title: "Gold packs", footer: first ? "Your first pack carries a one-time bonus. Bigger packs give more gold for the same money." : "Bigger packs give more gold for the same money.") {
            ForEach(Array(GoldStore.packs.enumerated()), id: \.element.id) { (i: Int, pack: GoldPack) in
                if i > 0 { Hairline() }
                NavigationLink { GoldPacksView() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.name).textStyle(.headline)
                            Text(GoldStore.extraPercent(pack) == 0 ? "The base rate" : "\(GoldStore.extraPercent(pack))% more gold per unit than the \(GoldStore.packs[0].name)").textStyle(.caption)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            GoldAmount(amount: GoldStore.totalGold(pack, firstPurchase: first))
                            Text(GoldStore.priceText(cents: pack.priceCents)).textStyle(.caption, tint: Theme.accent, numeric: true)
                        }
                    }
                    .padding(.vertical, Theme.Space.s).frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Cosmetics

    private var cosmeticsGroup: some View {
        let owned: Set<String> = SeasonModel.shared.pass.owned
        let items: [GoldCosmetic] = GoldCosmetics.storeItems
        return OnlineGroup(title: "Cosmetics and comfort", footer: "Wear what you own in the Cabinet. These change how things look and how many saves you can keep, never how the game plays.") {
            ForEach(Array(items.enumerated()), id: \.element.id) { (i: Int, c: GoldCosmetic) in
                if i > 0 { Hairline() }
                cosmeticRow(c, owned: owned.contains(c.id), blocked: isLockedSlot(c, owned: owned))
            }
        }
    }

    /// Extra slots are bought in order.
    private func isLockedSlot(_ c: GoldCosmetic, owned: Set<String>) -> Bool {
        let slots: [GoldCosmetic] = GoldCosmetics.storeItems.filter { $0.item.kind == .saveSlot }
        guard c.item.kind == .saveSlot, let i = slots.firstIndex(where: { $0.id == c.id }), i > 0 else { return false }
        return !owned.contains(slots[i - 1].id)
    }

    private func cosmeticRow(_ c: GoldCosmetic, owned: Bool, blocked: Bool) -> some View {
        Button { askCosmetic(c) } label: {
            HStack(spacing: Theme.Space.m) {
                swatch(c)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.item.title).textStyle(.headline)
                    HStack(spacing: Theme.Space.xs) {
                        RarityTag(rarity: c.rarity)
                        Text(c.item.kind.label).textStyle(.caption)
                    }
                }
                Spacer()
                if owned { Text("Owned").textStyle(.caption, tint: Theme.gain) }
                else if blocked { Text("Buy the one before").textStyle(.caption) }
                else if let p = c.price { GoldAmount(amount: p) }
            }
            .padding(.vertical, Theme.Space.s).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(owned || blocked)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func swatch(_ c: GoldCosmetic) -> some View {
        ItemArt(cosmetic: c, size: 36)
    }

    private func askCosmetic(_ c: GoldCosmetic) {
        guard let price = c.price else { return }
        if session.available < price { shortOfGold = true; return }
        pending = PendingAction(title: "Buy \(c.item.title)?", message: "Costs \(StoreText.gold(price)). \(c.item.detail)", button: "Buy",
                                alwaysAsk: true, tone: .investment, icon: "paintpalette") {
            Task { if await session.buyCosmetic(c) { Haptics.success() } }
        }
    }

    // MARK: More

    private var moreGroup: some View {
        OnlineGroup(title: "Collect and trade", footer: "") {
            NavigationLink { CabinetView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Cabinet", note: "Artifacts, collections and what you wear", chevron: true) }
                .buttonStyle(PressableStyle())
            Hairline()
            NavigationLink { AuctionsApp() } label: { OnlineLine(glyph: Glyph.market, title: "Auctions", note: "Bid on artifacts or sell your own, in gold", chevron: true) }
                .buttonStyle(PressableStyle())
        }
    }
}

/// Shown instead of the store to anyone who has not confirmed they are 18 or older (unknown counts as under 18).
struct StoreAgeGate: View {
    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            OnlineGroup(title: "Store", footer: "You can change this answer at any time in Settings, under Account.") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("The store, paid boxes and auctions are for players aged 18 or older.").textStyle(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("Everything in the game itself works without it.").textStyle(.body, tint: Theme.inkSoft)
                }
                .padding(.vertical, Theme.Space.m)
            }
            AgeConfirmationGroup()
        }
    }
}

/// The age confirmation switch of the account screen: "I am 18 or older". Off or never answered counts as under 18.
struct AgeConfirmationGroup: View {
    @AppStorage(AgeConfirmation.key) private var adult = false

    var body: some View {
        OnlineGroup(title: "Age", footer: "The store, paid boxes and auctions appear only for players aged 18 or older.") {
            Toggle(isOn: $adult) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I am 18 or older").textStyle(.headline)
                    Text(adult ? "Confirmed" : "Not confirmed").textStyle(.caption)
                }
            }
            .frame(minHeight: 52)
            .accessibilityIdentifier("age-confirmed")
        }
    }
}
