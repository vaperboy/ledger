import SwiftUI
import Simulation

/// The Store app: your gold, featured offers, boxes with their odds, gold packs, box bundles and cosmetics. Only for players who confirmed they are
/// 18 or older (anyone else sees an explanation, never the offers). Prices are always written out; the only countdown is the real end of the season.
struct StoreApp: View {
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var season = SeasonModel.shared
    private let session = StoreSession.shared
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0
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
                PhonePageScroll(spacing: Theme.Space.xl) {
                    walletCard.storeAppear(0)
                    FeaturedCarousel(features: features(paid: paid), onAsk: ask).storeAppear(1)
                    SeasonBanner().storeAppear(2)
                    if paid { boxesGroup.storeAppear(3) } else { regionNote }
                    stockGroup
                    if paid { bundlesGroup }
                    packsGroup
                    cosmeticsGroup
                    moreGroup
                    Text(StoreText.goldRule).textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
                }
                .confirmAction($pending)
                .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") {
                    ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true }, onPick: { (p: GoldPack) in
                        shortOfGold = false
                        StorePurchase.afterPopup { pending = StorePurchase.pack(p) }
                    })
                }
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
            GoldCounter(amount: session.gold)
            if session.state.wallet.held > 0 {
                Text("\(StoreText.gold(session.state.wallet.held)) held for leading bids. \(StoreText.gold(session.available)) available.").textStyle(.caption)
            }
            if session.isVisualOnly {
                Text("Preview store: nothing is charged and no real purchase happens in this build.").textStyle(.caption)
            }
            NavigationLink { GoldPacksView() } label: { Text("Get gold").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("store-get-gold")
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoreSurface(tint: Theme.gold, glow: true))
    }

    // MARK: Featured

    /// Real offers only: the season bundle (with the true days left in the season), the pack with the most gold per unit of money, the box with the best odds
    /// and the biggest box saving.
    private func features(paid: Bool) -> [StoreFeature] {
        var out: [StoreFeature] = []
        let b: SeasonBundle = GoldStore.seasonBundle
        let left: Int = season.pass.daysLeft(today: season.today)
        let ends: String = left == 1 ? "Season \(season.pass.seasonNumber) ends tomorrow." : "Season \(season.pass.seasonNumber) ends in \(left) days."
        out.append(StoreFeature(id: "season", tag: "Season bundle", title: b.name,
                                gets: [StoreText.gold(b.gold), StorePurchase.boxText(b), "Ledger Plus for this season"],
                                price: GoldStore.priceText(cents: b.priceCents),
                                footnote: ends + (session.isVisualOnly ? " Preview build: Ledger Plus is not added." : ""),
                                action: .seasonBundle))
        if let p = StorePurchase.bestPack {
            let first: Bool = !session.state.firstPurchaseDone
            var gets: [String] = [StoreText.gold(GoldStore.totalGold(p, firstPurchase: first))]
            if first { gets.append("Includes \(GoldStore.firstPurchaseBonus(p).formatted()) one-time bonus gold") }
            gets.append("\(GoldStore.extraPercent(p))% more gold per \(GoldStore.priceText(cents: 100)) than the \(GoldStore.packs[0].name)")
            out.append(StoreFeature(id: "pack", tag: "Best value", title: "The \(p.name)", gets: gets, price: GoldStore.priceText(cents: p.priceCents), highlight: true, action: .pack(p)))
        }
        if paid {
            let rarePlus: Double = BoxOdds.rarityPercent(.grand).filter { $0.rarity >= .rare }.reduce(0) { $0 + $1.percent }
            out.append(StoreFeature(id: "grand", tag: "Best odds", title: BoxKind.grand.title,
                                    gets: ["One opening of the Grand box", "\(String(format: "%.2f", rarePlus))% chance of a rare or better item", "A rare or better item guaranteed at least once in \(BoxPity.threshold) paid boxes"],
                                    price: StoreText.gold(BoxKind.grand.price), tint: BoxRarity.epic.tint, action: .box(.grand)))
            if let bb = StorePurchase.bestBundle {
                out.append(StoreFeature(id: "bundle", tag: "Best saving", title: "\(bb.count) \(bb.kind.title)es",
                                        gets: ["\(bb.count) \(bb.kind.title)es in your stock", "\(bb.savingPercent)% less than \(StoreText.gold(bb.singlesPrice)) for single boxes", "Nothing is opened until you choose"],
                                        price: StoreText.gold(bb.price), action: .boxBundle(bb)))
            }
        }
        return out
    }

    private func ask(_ a: StoreFeature.Action) {
        switch a {
        case .seasonBundle: pending = StorePurchase.seasonBundle()
        case .pack(let p): pending = StorePurchase.pack(p)
        case .boxBundle(let b): askBundle(b)
        case .box: break
        }
    }

    // MARK: Boxes

    private var boxesGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Boxes").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            ForEach(Array(BoxKind.allCases.filter { $0.isPaid }.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                NavigationLink { BoxView(kind: kind, paidBoxesAllowed: true) } label: { BoxShowcaseCard(kind: kind, index: i) }
                    .buttonStyle(PressableStyle())
            }
            Text("Every box shows its exact odds here and on its page. \(session.state.pity.text)")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
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

    // MARK: Bundles

    private var bundlesGroup: some View {
        let best: String? = StorePurchase.bestBundle?.id
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Box bundles").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            ForEach(GoldStore.boxBundles) { (b: BoxBundle) in
                Button { askBundle(b) } label: {
                    HStack(spacing: Theme.Space.m) {
                        BoxArt(kind: b.kind, size: 40).padding(.trailing, Theme.Space.xs)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Theme.Space.s) {
                                Text("\(b.count) \(b.kind.title)es").textStyle(.headline)
                                if b.id == best { StoreTag(text: "Best saving") }
                            }
                            Text("\(b.savingPercent)% less than \(b.count) single boxes (\(StoreText.gold(b.singlesPrice)))").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Theme.Space.s)
                        GoldAmount(amount: b.price)
                    }
                    .padding(Theme.Space.m).frame(minHeight: 64)
                    .background(StoreSurface(tint: Theme.gold, glow: b.id == best, radius: Theme.Radius.card))
                    .storeSheen(radius: Theme.Radius.card, enabled: b.id == best, offset: 2)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(PressableStyle())
            }
            Text("Bought with gold. The boxes wait in your stock; each one shows its odds when you open it.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func askBundle(_ b: BoxBundle) {
        if session.available < b.price { shortNeed = b.price; shortOfGold = true; return }
        pending = StorePurchase.boxBundle(b)
    }

    // MARK: Packs

    private var packsGroup: some View {
        let first: Bool = !session.state.firstPurchaseDone
        let best: String? = StorePurchase.bestPack?.id
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Gold packs").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            ForEach(GoldStore.packs) { (pack: GoldPack) in
                PackCard(pack: pack, first: first, best: pack.id == best) { pending = StorePurchase.pack(pack) }
            }
            Text(first ? "Your first pack carries a one-time bonus. Bigger packs give more gold for the same money." : "Bigger packs give more gold for the same money.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Cosmetics

    private var cosmeticsGroup: some View {
        let owned: Set<String> = SeasonModel.shared.pass.owned
        let items: [GoldCosmetic] = GoldCosmetics.storeItems
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Cosmetics and comfort").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible())], spacing: Theme.Space.m) {
                ForEach(Array(items.enumerated()), id: \.element.id) { (i: Int, c: GoldCosmetic) in
                    cosmeticTile(c, owned: owned.contains(c.id), blocked: isLockedSlot(c, owned: owned), index: i)
                }
            }
            Text("Wear what you own in the Cabinet. These change how things look and how many saves you can keep, never how the game plays.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Extra slots are bought in order.
    private func isLockedSlot(_ c: GoldCosmetic, owned: Set<String>) -> Bool {
        let slots: [GoldCosmetic] = GoldCosmetics.storeItems.filter { $0.item.kind == .saveSlot }
        guard c.item.kind == .saveSlot, let i = slots.firstIndex(where: { $0.id == c.id }), i > 0 else { return false }
        return !owned.contains(slots[i - 1].id)
    }

    private func cosmeticTile(_ c: GoldCosmetic, owned: Bool, blocked: Bool, index: Int) -> some View {
        let shiny: Bool = c.rarity >= .epic
        return Button { askCosmetic(c) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                swatch(c).frame(height: 56).frame(maxWidth: .infinity)
                Text(c.item.title).textStyle(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.xs) {
                    RarityTag(rarity: c.rarity)
                    Text(c.item.kind.label).textStyle(.caption).lineLimit(1)
                }
                Spacer(minLength: 0)
                if owned { Text("Owned").textStyle(.caption, tint: Theme.gain) }
                else if blocked { Text("Buy the one before").textStyle(.caption) }
                else if let p = c.price { GoldAmount(amount: p) }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .background(StoreSurface(tint: c.rarity.tint, radius: Theme.Radius.card))
            .storeSheen(radius: Theme.Radius.card, enabled: shiny && !owned, offset: Double(index) * 0.7, strength: 0.22)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableStyle())
        .disabled(owned || blocked)
    }

    @ViewBuilder private func swatch(_ c: GoldCosmetic) -> some View {
        ItemArt(cosmetic: c, size: 36)
    }

    private func askCosmetic(_ c: GoldCosmetic) {
        guard let price = c.price else { return }
        if session.available < price { shortNeed = price; shortOfGold = true; return }
        pending = StorePurchase.cosmetic(c, price: price)
    }

    // MARK: More

    private var moreGroup: some View {
        OnlineGroup(title: "Collect and trade", footer: "") {
            NavigationLink { CollectionView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Collection", note: "Artifacts, trophies and auctions", chevron: true) }
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
