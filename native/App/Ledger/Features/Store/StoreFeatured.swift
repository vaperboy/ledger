import SwiftUI
import Simulation

/// A big section header: a bright slanted band with a white title and a small picture at the right,
/// or the section's banner picture (store.band.<name>) with the title over its left half when that picture exists.
struct StoreBand: View {
    var title: String
    var glyph: String
    var tint: Color = StoreColors.purple
    var trailing: Date? = nil
    var art: String = ""

    var body: some View {
        if let picture = StoreArt.image(art) {
            banner(picture)
        } else {
            band
        }
    }

    private func banner(_ picture: Image) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return Color.clear
            .aspectRatio(1170.0 / 420.0, contentMode: .fit)
            .overlay { picture.resizable().scaledToFill() }
            .overlay(LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .leading) {
                HStack(spacing: Theme.Space.s) {
                    Text(title.uppercased()).font(.title2.weight(.black)).italic().foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    LedgerGlyph(glyph: glyph, size: 22, tint: Color.white.opacity(0.9))
                }
                .padding(.leading, Theme.Space.l)
            }
            .overlay(alignment: .topTrailing) {
                if let trailing { StoreTimer(ends: trailing).padding(Theme.Space.s) }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(tint.opacity(0.6), lineWidth: 1))
            .padding(.horizontal, Theme.Space.m)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
    }

    private var band: some View {
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

extension BoxBundle {
    /// Offer picture of a box bundle, for example offer.boxbundle.cabinetx5.
    var offerArt: String { "offer.boxbundle." + kind.rawValue + "x" + String(count) }
}

extension GoldPack {
    /// Pack picture, for example goldpack.pouch for gold.pouch.
    var art: String { "goldpack." + (id.split(separator: ".").last.map(String.init) ?? id) }
}

/// Store pictures: banners, offer art, gold and money packs. Nil until the picture exists, so the drawn look stays.
enum StoreArt {
    static func image(_ name: String) -> Image? {
        #if canImport(UIKit)
        if let ui = ArtAsset.uiImage(name) { return Image(uiImage: ui) }
        #endif
        return nil
    }
}

extension StoreSession {
    /// The server's purchase limit on an offer; nil when it has none or the Store is offline.
    func offerLimit(_ kind: String, _ id: String) -> ServerStoreInfo.OfferLimit? {
        server?.limits?.first { $0.kind == kind && $0.id == id }
    }

    /// The bundle on the Offers card: the one the server features, else the biggest saving.
    var featuredBundle: BoxBundle? {
        if let id = server?.limits?.first(where: { $0.kind == "bundle" && $0.featured })?.id,
           let b = GoldStore.boxBundles.first(where: { $0.id == id }) { return b }
        return StorePurchase.bestBundle
    }
}

extension ServerStoreInfo.OfferLimit {
    var soldOut: Bool { left <= 0 }
    var resets: Date { Date(timeIntervalSince1970: resetsAt) }
    /// "Remaining 2/3", or "Available 1/1" for a one-off offer.
    var counter: String { (cap == 1 ? "Available " : "Remaining ") + "\(max(0, left))/\(cap)" }
}

/// A limited offer's counter: "Remaining 2/3", or "Sold out" with the time until it comes back.
struct StoreLimitPill: View {
    var limit: ServerStoreInfo.OfferLimit

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            Text(limit.soldOut ? "Sold out · back in " + StoreTimer.text(limit.resets.timeIntervalSince(tl.date)) : limit.counter)
                .font(.caption2.weight(.heavy)).monospacedDigit().foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.3)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limit.soldOut ? "Sold out" : limit.counter)
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
    private let session = StoreSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Offers", glyph: Glyph.shopBag, tint: StoreColors.purple, art: "store.band.battlepass")
            if season.premiumOpen(plus: ent.isPlus, founder: ent.isFounder) { StoreSeasonCard() } else { passOffer }
            if let b = session.featuredBundle { bundleOffer(b, limit: session.offerLimit("bundle", b.id)) }
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
                              rewards: rewards, art: "offer.battlepass") {
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

    private func bundleOffer(_ b: BoxBundle, limit: ServerStoreInfo.OfferLimit?) -> some View {
        let saving: String = "\(b.savingPercent)% less than buying them one by one."
        let line: String = limit.map { (l: ServerStoreInfo.OfferLimit) -> String in l.counter + " · " + saving } ?? saving
        return StoreOfferCard(title: "\(b.count) \(b.kind.title)es", line: line, tint: StoreColors.orange,
                              tag: "BEST SAVING", ends: limit?.resets, rewards: [.boxes(b.count, b.kind)], art: b.offerArt) {
            if let limit, limit.soldOut {
                StoreLimitPill(limit: limit).frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Button { Haptics.tap(); ask(.boxBundle(b)) } label: { StorePriceBar(gold: b.price) }
                    .buttonStyle(PressableStyle())
                    .adminPrice(kind: "bundle", id: b.id, current: b.price)
                    .accessibilityIdentifier("store-featured-bundle")
            }
        }
    }
}

/// BUNDLES: every box bundle as a card with what it holds and its price.
struct StoreBundlesSection: View {
    var ask: (GoldGood) -> Void
    private let session = StoreSession.shared

    var body: some View {
        let columns: [GridItem] = [GridItem(.flexible(), spacing: Theme.Space.s), GridItem(.flexible())]
        let featured: String? = session.featuredBundle?.id
        let bundles: [BoxBundle] = GoldStore.boxBundles.filter { (b: BoxBundle) -> Bool in b.id != featured }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Bundles", glyph: Glyph.luxury, tint: StoreColors.green)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(bundles) { (b: BoxBundle) in card(b, limit: session.offerLimit("bundle", b.id)) }
            }
            .padding(.horizontal, Theme.Space.m)
            Text("You open a bundle's boxes one by one right after buying it; any you leave wait in your stock.").textStyle(.caption)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
        }
    }

    private func card(_ b: BoxBundle, limit: ServerStoreInfo.OfferLimit?) -> some View {
        let closed: Bool = limit?.soldOut ?? false
        return Button { Haptics.tap(); ask(.boxBundle(b)) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("\(b.count) \(b.kind.title)es").font(.headline.weight(.heavy)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
                OfferPicture(name: b.offerArt)
                HStack { RewardIcon(reward: .boxes(b.count, b.kind), size: 42); Spacer(minLength: 0); StoreTag(text: "-\(b.savingPercent)%", tint: StoreColors.yellow) }
                if let limit { StoreLimitPill(limit: limit) }
                StorePriceBar(gold: b.price).opacity(closed ? 0.5 : 1)
            }
            .padding(Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(StoreColors.green)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(closed)
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
            StoreBand(title: "Today's shelf", glyph: Glyph.person, tint: StoreColors.blue, trailing: StoreTimer.nextServerDay, art: "store.band.cosmetics")
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

/// MONEY: game money bought with gold, a three-column grid. The first tile is the free pack; each pack sells a few times a day.
struct StoreMoneySection: View {
    var ask: (GoldGood) -> Void
    private let session = StoreSession.shared

    var body: some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Money", glyph: Glyph.bank, tint: StoreColors.green, art: "store.band.money")
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
    var art: String = ""
    var limit: ServerStoreInfo.OfferLimit? = nil
    var counter: String? = nil
    @ViewBuilder var price: () -> Price

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(title).font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            RewardIcon(reward: StoreReward(kind: .money, amount: amount), size: 40, art: art)
            if let tag { StoreTag(text: tag, tint: StoreColors.yellow) } else { Color.clear.frame(height: 18) }
            if let limit {
                StoreLimitPill(limit: limit)
            } else if let counter {
                Text(counter).font(.caption2.weight(.heavy)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.3)))
            }
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
        let limit: ServerStoreInfo.OfferLimit? = session.offerLimit("money", pack.id)
        let cash: Bool = session.canSellForCash
        let open: Bool = cash && !(limit?.soldOut ?? false)
        Button { Haptics.tap(); buy() } label: {
            MoneyTileFrame(title: pack.name, amount: cash ? StorePurchase.moneyText(pack) : "Open a game",
                           tag: pack.bonusPercent > 0 ? "+\(pack.bonusPercent)%" : nil, tint: StoreColors.green, art: "moneypack." + pack.id,
                           limit: limit) {
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
                           tag: "WATCH AD", tint: StoreColors.cyan, art: "moneypack." + pack.id,
                           counter: "Remaining \(left)/\(MoneyPacks.freePerDay)") {
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
