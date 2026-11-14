import SwiftUI
import Simulation

/// A big section header: a bright slanted band with a white title and a small picture at the right.
struct StoreBand: View {
    var title: String
    var glyph: String
    var tint: Color = StoreColors.purple
    var trailing: Date? = nil

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ZStack(alignment: .leading) {
                StoreSlant().fill(StoreColors.gradient(tint))
                HStack(spacing: Theme.Space.s) {
                    Text(title.uppercased()).font(.title2.weight(.black)).italic().foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    LedgerGlyph(glyph: glyph, size: 24, tint: Color.white.opacity(0.9))
                }
                .padding(.leading, Theme.Space.l).padding(.trailing, Theme.Space.xl)
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            if let trailing { StoreTimer(ends: trailing).padding(.trailing, Theme.Space.m) }
        }
        .frame(height: 50)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct StoreSlant: Shape {
    func path(in rect: CGRect) -> Path {
        let cut: CGFloat = 22
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The yellow gold price bar used on gold goods.
struct StorePriceBar: View {
    var gold: Int

    var body: some View {
        StorePriceLabel(text: gold.formatted(), gold: true, minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Buy for " + StoreText.gold(gold))
    }
}

/// An App Store purchase as a big yellow price button.
struct StoreAppStoreButton: View {
    @Environment(PurchaseManager.self) private var purchases
    var item: PurchaseItem
    var title: String = ""
    var identifier: String = ""

    var body: some View {
        let manager: PurchaseManager = purchases
        let price: String? = manager.price(item)
        let busy: Bool = manager.inFlight == item
        Button { Haptics.tap(); manager.request(item) } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small).tint(StoreColors.priceInk) }
                StorePriceLabel(text: label(price, busy: busy))
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(manager.isBusy || price == nil)
        .opacity(price == nil ? 0.6 : 1)
        .accessibilityIdentifier(identifier)
    }

    private func label(_ price: String?, busy: Bool) -> String {
        if busy { return "Working..." }
        guard let price else { return purchases.catalogLoaded ? "Unavailable" : "..." }
        return title.isEmpty ? price : title + "  " + price
    }
}

/// OFFERS: the season pass, the plans and the best box bundle.
struct StoreOffersSection: View {
    var ask: (GoldGood) -> Void
    @ObservedObject private var season = SeasonModel.shared
    @Environment(Entitlements.self) private var ent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Offers", glyph: Glyph.shopBag, tint: StoreColors.purple)
            if season.premiumOpen(plus: ent.isPlus, founder: ent.isFounder) { StoreSeasonCard() } else { passOffer }
            if let b = StorePurchase.bestBundle { bundleOffer(b) }
            ProPlansView(part: .offers)
        }
    }

    private var passOffer: some View {
        let bundle: SeasonBundle = GoldStore.seasonBundle
        let left: Int = season.pass.daysLeft(today: season.today)
        var rewards: [StoreReward] = [StoreReward(kind: .premium, amount: "Premium", caption: "rewards track")]
        for b in bundle.boxes { rewards.append(.boxes(b.count, b.kind)) }
        if bundle.gold > 0 { rewards.append(.gold(bundle.gold)) }
        return StoreOfferCard(title: "Season \(season.pass.seasonNumber) Battle Pass", line: "Unlock the premium rewards of this season.",
                              tint: StoreColors.pink, ends: Calendar.current.date(byAdding: .day, value: max(1, left), to: Calendar.current.startOfDay(for: Date())),
                              rewards: rewards) {
            VStack(spacing: Theme.Space.s) {
                StoreAppStoreButton(item: .seasonBundle, identifier: "plan-season-bundle")
                StoreAppStoreButton(item: .seasonLevels, title: "+\(GoldStore.seasonLevels.tiers) tiers", identifier: "plan-season-levels")
                Text("Lasts until this season ends. Nothing renews.").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                NavigationLink {
                    SeasonView().appScreen(title: "Season Pass", subtitle: "Tiers and rewards")
                } label: {
                    Text("See every reward").font(.subheadline.weight(.bold)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("store-open-pass")
            }
        }
    }

    private func bundleOffer(_ b: BoxBundle) -> some View {
        StoreOfferCard(title: "\(b.count) \(b.kind.title)es", line: "\(b.savingPercent)% less than buying them one by one.", tint: StoreColors.orange,
                       tag: "BEST SAVING", rewards: [.boxes(b.count, b.kind)]) {
            Button { Haptics.tap(); ask(.boxBundle(b)) } label: { StorePriceBar(gold: b.price) }
                .buttonStyle(PressableStyle())
                .adminPrice(kind: "bundle", id: b.id, current: b.price)
                .accessibilityIdentifier("store-featured-bundle")
        }
    }
}

/// BUNDLES: every box bundle as a card with what it holds and its price.
struct StoreBundlesSection: View {
    var ask: (GoldGood) -> Void

    var body: some View {
        let columns: [GridItem] = [GridItem(.flexible(), spacing: Theme.Space.s), GridItem(.flexible())]
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Bundles", glyph: Glyph.luxury, tint: StoreColors.green)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(GoldStore.boxBundles) { (b: BoxBundle) in card(b) }
            }
            .padding(.horizontal, Theme.Space.m)
            Text("You open a bundle's boxes one by one right after buying it; any you leave wait in your stock.").textStyle(.caption)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
        }
    }

    private func card(_ b: BoxBundle) -> some View {
        Button { Haptics.tap(); ask(.boxBundle(b)) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("\(b.count) \(b.kind.title)es").font(.headline.weight(.heavy)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
                HStack { RewardIcon(reward: .boxes(b.count, b.kind), size: 42); Spacer(minLength: 0); StoreTag(text: "-\(b.savingPercent)%", tint: StoreColors.yellow) }
                StorePriceBar(gold: b.price)
            }
            .padding(Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(StoreColors.green)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .adminPrice(kind: "bundle", id: b.id, current: b.price)
        .accessibilityIdentifier("store-bundle-\(b.id)")
    }
}

/// TODAY'S SHELF: a daily pick of cosmetics, the same for every player, until midnight UTC.
struct StoreShelfSection: View {
    var ask: (GoldGood) -> Void
    private let session = StoreSession.shared

    var body: some View {
        let picks: [ShelfPick] = session.shelf
        let owned: Set<String> = SeasonModel.shared.pass.owned
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Today's shelf", glyph: Glyph.person, tint: StoreColors.blue, trailing: StoreTimer.nextServerDay)
            if picks.isEmpty {
                Text("Today's shelf appears once the Store is online.").textStyle(.body, tint: Theme.inkSoft).padding(.horizontal, Theme.Space.m)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3), spacing: Theme.Space.s) {
                    ForEach(picks) { (p: ShelfPick) in
                        ShelfTile(pick: p, owned: owned.contains(p.id)) { ask(.cosmetic(p.item)) }
                            .adminPrice(kind: "item", id: p.id, current: p.price)
                    }
                }
                .padding(.horizontal, Theme.Space.m)
            }
            Text("A new shelf every day. Battle Pass items are never sold here; the pass is the only way to get them.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
            NavigationLink { StoreShelfView() } label: {
                Text("Save slots").textStyle(.body, tint: Theme.accent, weight: .semibold).frame(minHeight: 44)
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, Theme.Space.m)
            .accessibilityIdentifier("store-shelf")
        }
    }
}

struct ShelfTile: View {
    var pick: ShelfPick
    var owned: Bool
    var buy: () -> Void

    var body: some View {
        let c: GoldCosmetic = pick.item
        Button { Haptics.tap(); buy() } label: {
            VStack(spacing: Theme.Space.xs) {
                Text(c.rarity.title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.9))
                ItemArt(cosmetic: c, size: 44).frame(height: 60).frame(maxWidth: .infinity)
                Text(c.item.title).font(.caption.weight(.bold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center).frame(minHeight: 30)
                if owned {
                    Text("Owned").font(.headline.weight(.heavy)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.25)))
                } else {
                    StorePriceBar(gold: pick.price)
                }
            }
            .padding(Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(c.rarity.storeTint)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(owned)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shelf-" + c.id)
    }
}

/// MONEY: game money bought with gold, a three-column grid. The first tile is the free pack.
struct StoreMoneySection: View {
    var ask: (GoldGood) -> Void
    private let session = StoreSession.shared

    var body: some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Money", glyph: Glyph.bank, tint: StoreColors.green)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                FreeMoneyTile()
                ForEach(MoneyPacks.packs, id: \.id) { (pack: MoneyPack) in
                    MoneyPackTile(pack: pack) { ask(.moneyPack(pack)) }
                }
            }
            .padding(.horizontal, Theme.Space.m)
            Text(session.canSellForCash ? "Money is paid into your account in the open game. Bigger packs add a bonus." : "Open a game to buy money.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A coloured tile for the money grids: the amount on top, a big icon, the price button below.
private struct MoneyTileFrame<Price: View>: View {
    var title: String
    var amount: String
    var tag: String?
    var tint: Color
    @ViewBuilder var price: () -> Price

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(title).font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            RewardIcon(reward: StoreReward(kind: .money, amount: amount), size: 40)
            if let tag { StoreTag(text: tag, tint: StoreColors.yellow) } else { Color.clear.frame(height: 18) }
            price()
        }
        .padding(Theme.Space.xs)
        .frame(maxWidth: .infinity, minHeight: 168)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(tint)))
    }
}

struct MoneyPackTile: View {
    var pack: MoneyPack
    var buy: () -> Void
    private let session = StoreSession.shared

    var body: some View {
        let open: Bool = session.canSellForCash
        Button { Haptics.tap(); buy() } label: {
            MoneyTileFrame(title: pack.name, amount: open ? StorePurchase.moneyText(pack) : "Open a game",
                           tag: pack.bonusPercent > 0 ? "+\(pack.bonusPercent)%" : nil, tint: StoreColors.green) {
                StorePriceBar(gold: pack.gold)
            }
            .opacity(open ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!open)
        .accessibilityIdentifier("money-" + pack.id)
    }
}

struct FreeMoneyTile: View {
    @Environment(AdCoordinator.self) private var ads
    @State private var busy = false
    private let session = StoreSession.shared

    var body: some View {
        let pack: MoneyPack = MoneyPacks.free
        let used: Int = ads.freeMoneyUsed
        let left: Int = ads.freeMoneyLeft
        let ready: Bool = used >= 0 && ads.canOfferFreeMoney && session.canSellForCash && !busy
        Button { Haptics.tap(); claim() } label: {
            MoneyTileFrame(title: "Free pack", amount: session.canSellForCash ? StorePurchase.moneyText(pack) : "Open a game",
                           tag: left == 1 ? "1 left today" : "\(left) left today", tint: StoreColors.cyan) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.caption.weight(.black))
                    Text("FREE").font(.headline.weight(.heavy))
                }
                .foregroundStyle(StoreColors.priceInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StoreColors.yellow))
            }
            .opacity(ready ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!ready)
        .accessibilityLabel("Free money pack, watch an ad. \(left) left today.")
        .accessibilityIdentifier("money-free")
    }

    private func claim() {
        busy = true
        Task {
            if await ads.watchForFreeMoney(), await session.claimFreeMoney() { Haptics.success() }
            busy = false
        }
    }
}

/// FREE GOLD: the ad button's terms and the supporter perks, written out in full.
struct StoreFreeGoldSection: View {
    private let session = StoreSession.shared

    var body: some View {
        let t: ServerStoreInfo.AdTerms? = session.adTerms
        let base: Int = t?.baseGold ?? 1
        let plus: Int = t?.supporterGold ?? 2
        let wait: Int = (t?.baseCooldown ?? 300) / 60
        let shortWait: Int = (t?.supporterCooldown ?? 180) / 60
        let perDay: Int = t?.perDay ?? 10
        let ads: Int = t?.supporterAds ?? 50
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Free gold", glyph: Glyph.bank, tint: StoreColors.pink)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    RewardIcon(reward: .gold(base), size: 42)
                    Text("Tap the round ad button on Home or here: one ad pays \(StoreText.gold(base)), up to \(perDay) ads a day, with \(wait) minutes between ads.")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1)
                HStack(spacing: Theme.Space.s) {
                    SupporterMark()
                    if session.isSupporter { Text("You are a Supporter. Thank you!").font(.subheadline.weight(.heavy)).foregroundStyle(.white) }
                }
                Text("Buy anything with real money, or watch \(ads) ads, and you become a Supporter for good: a Supporter badge on your player card, \(StoreText.gold(plus)) per ad instead of \(base), and \(shortWait) minutes between ads instead of \(wait). That is all: no edge in the game.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("store-supporter-rules")
                if let t, !session.isSupporter {
                    Text("Ads watched: \(min(t.watched, ads)) of \(ads)").font(.caption.weight(.heavy)).monospacedDigit().foregroundStyle(.white)
                }
            }
            .padding(Theme.Space.m)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(StoreColors.violet)))
            .padding(.horizontal, Theme.Space.m)
        }
    }
}
