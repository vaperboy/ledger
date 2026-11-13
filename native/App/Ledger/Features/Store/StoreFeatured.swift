import SwiftUI
import Simulation

/// A big section header on a slanted coloured band with a small picture at the right.
struct StoreBand: View {
    var title: String
    var glyph: String
    var tint: Color = Theme.gold

    var body: some View {
        ZStack(alignment: .leading) {
            StoreSlant().fill(LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
            HStack {
                Text(title.uppercased()).font(.system(size: 26, weight: .heavy)).italic().foregroundStyle(Theme.accentInk)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Theme.Space.s)
                LedgerGlyph(glyph: glyph, size: 34, tint: Theme.accentInk.opacity(0.8))
            }
            .padding(.horizontal, Theme.Space.l)
        }
        .frame(height: 56)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(title)
    }
}

private struct StoreSlant: Shape {
    func path(in rect: CGRect) -> Path {
        let cut: CGFloat = 18
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A bold price bar: the price in big type on a yellow strip.
struct StorePriceBar: View {
    var gold: Int

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Spacer(minLength: 0)
            Circle().fill(Theme.accentInk.opacity(0.85)).frame(width: 12, height: 12).accessibilityHidden(true)
            Text(gold.formatted()).font(.system(size: 20, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.accentInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m).frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.gold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Buy for " + StoreText.gold(gold))
    }
}

/// OFFERS: the season pass, the plans and the best box bundle as full-width cards.
struct StoreOffersSection: View {
    var ask: (GoldGood) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Offers", glyph: Glyph.shopBag)
            StoreSeasonCard()
            ProPlansView(part: .offers)
            if let b = StorePurchase.bestBundle { hero(b) }
        }
    }

    private func hero(_ b: BoxBundle) -> some View {
        Button { Haptics.tap(); ask(.boxBundle(b)) } label: {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Space.m) {
                    BoxArt(kind: b.kind, size: 72)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("Best saving").textStyle(.caption, tint: Theme.gold, weight: .semibold)
                        Text("\(b.count) \(b.kind.title)es").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.ink)
                        Text("\(b.savingPercent)% less than single boxes").textStyle(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Space.m)
                StorePriceBar(gold: b.price).padding([.horizontal, .bottom], Theme.Space.m)
            }
            .background(StoreSurface(tint: Theme.gold, glow: true, radius: Theme.Radius.card))
            .overlay(alignment: .topTrailing) { StoreTag(text: "\(b.savingPercent)% off", tint: Theme.loss).padding(Theme.Space.s) }
            .padding(.horizontal, Theme.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("store-featured-bundle")
    }
}

/// BUNDLES: one large card and the rest as half-width cards.
struct StoreBundlesSection: View {
    var ask: (GoldGood) -> Void

    var body: some View {
        let all: [BoxBundle] = GoldStore.boxBundles
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Bundles", glyph: Glyph.luxury)
            if let first = all.first { card(first, large: true) }
            let rest: [BoxBundle] = Array(all.dropFirst())
            if !rest.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible())], spacing: Theme.Space.m) {
                    ForEach(rest) { (b: BoxBundle) in card(b, large: false) }
                }
                .padding(.horizontal, Theme.Space.m)
            }
            Text("The boxes wait in your stock until you open them.").textStyle(.caption).padding(.horizontal, Theme.Space.m)
        }
    }

    private func card(_ b: BoxBundle, large: Bool) -> some View {
        Button { Haptics.tap(); ask(.boxBundle(b)) } label: {
            VStack(spacing: Theme.Space.s) {
                BoxArt(kind: b.kind, size: large ? 84 : 56)
                Text("\(b.count) \(b.kind.title)es").textStyle(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Text("\(b.savingPercent)% less than singles").textStyle(.caption)
                StorePriceBar(gold: b.price)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity)
            .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal, large ? Theme.Space.m : 0)
        .accessibilityIdentifier("store-bundle-\(b.id)")
    }
}

/// COSMETICS: a three-column grid of the rarest items still to buy, with a link to the full shelf.
struct StoreCosmeticsSection: View {
    var ask: (GoldGood) -> Void

    private var picks: [GoldCosmetic] {
        let owned: Set<String> = SeasonModel.shared.pass.owned
        let items: [GoldCosmetic] = GoldCosmetics.shelfItems.filter { (c: GoldCosmetic) -> Bool in
            !owned.contains(c.id) && c.item.kind != .saveSlot
        }
        return Array(items.sorted { (a: GoldCosmetic, b: GoldCosmetic) -> Bool in a.rarity > b.rarity }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Cosmetics", glyph: Glyph.person)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3), spacing: Theme.Space.s) {
                ForEach(picks) { (c: GoldCosmetic) in tile(c) }
            }
            .padding(.horizontal, Theme.Space.m)
            NavigationLink { StoreShelfView() } label: {
                Text("See everything on the shelf").textStyle(.body, tint: Theme.accent, weight: .semibold).frame(minHeight: 44)
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, Theme.Space.m)
            .accessibilityIdentifier("store-shelf")
        }
    }

    private func tile(_ c: GoldCosmetic) -> some View {
        Button { Haptics.tap(); ask(.cosmetic(c)) } label: {
            VStack(spacing: Theme.Space.xs) {
                ItemArt(cosmetic: c, size: 36).frame(height: 52).frame(maxWidth: .infinity)
                Text(c.item.title).textStyle(.caption, tint: Theme.ink, weight: .semibold).lineLimit(2).multilineTextAlignment(.center)
                    .frame(minHeight: 32)
                RarityTag(rarity: c.rarity)
                StorePriceBar(gold: c.price ?? 0)
            }
            .padding(Theme.Space.s)
            .background(StoreSurface(tint: c.rarity.tint, radius: Theme.Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// MONEY: game money bought with gold, a three-column grid like the gold packs. The first tile is the free pack.
struct StoreMoneySection: View {
    var ask: (GoldGood) -> Void
    private let session = StoreSession.shared

    var body: some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: "Money", glyph: Glyph.bank)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                FreeMoneyTile()
                ForEach(Array(MoneyPacks.packs.enumerated()), id: \.element.id) { (i: Int, pack: MoneyPack) in
                    MoneyPackTile(pack: pack, tier: i + 1) { ask(.moneyPack(pack)) }
                }
            }
            .padding(.horizontal, Theme.Space.m)
            Text(session.canSellForCash ? "Money is paid into your personal account in the open game. Bigger packs add a bonus." : "Open a game to buy money. It is paid into your personal account.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A stack of notes that grows with the pack. A drawn placeholder until there is real art.
struct MoneyHeap: View {
    var tier: Int

    var body: some View {
        ZStack {
            ForEach(0..<max(1, min(5, tier)), id: \.self) { (i: Int) in
                Image(systemName: "banknote.fill")
                    .font(.system(size: CGFloat(22 + tier * 2)))
                    .foregroundStyle(Theme.gain.opacity(0.55 + 0.1 * Double(i)))
                    .offset(x: CGFloat(i % 2 == 0 ? -1 : 1) * CGFloat(i) * 3.5, y: -CGFloat(i) * 5)
            }
        }
        .frame(width: 52, height: 48)
        .accessibilityHidden(true)
    }
}

struct MoneyPackTile: View {
    var pack: MoneyPack
    var tier: Int
    var buy: () -> Void
    private let session = StoreSession.shared

    var body: some View {
        let open: Bool = session.canSellForCash
        Button { Haptics.tap(); buy() } label: {
            VStack(spacing: Theme.Space.xs) {
                if pack.bonusPercent > 0 { StoreTag(text: "+\(pack.bonusPercent)%", tint: Theme.gain) } else { Color.clear.frame(height: 18) }
                MoneyHeap(tier: tier)
                Text(pack.name).textStyle(.headline).lineLimit(1)
                Text(open ? StorePurchase.moneyText(pack) : "Open a game").textStyle(.caption, tint: Theme.ink, weight: .semibold).lineLimit(1).minimumScaleFactor(0.6)
                StorePriceBar(gold: pack.gold)
            }
            .padding(.horizontal, Theme.Space.xs).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: 168)
            .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
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
            VStack(spacing: Theme.Space.xs) {
                StoreTag(text: left == 1 ? "1 left today" : "\(left) left today", tint: left > 0 ? Theme.gain : Theme.inkFaint)
                MoneyHeap(tier: 1)
                Text(pack.name).textStyle(.headline).lineLimit(1)
                Text(session.canSellForCash ? StorePurchase.moneyText(pack) : "Open a game").textStyle(.caption, tint: Theme.ink, weight: .semibold).lineLimit(1).minimumScaleFactor(0.6)
                Text("Free · watch an ad").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.accentInk).lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, Theme.Space.s).frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.gold))
            }
            .padding(.horizontal, Theme.Space.xs).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: 168)
            .background(StoreSurface(tint: Theme.gain, radius: Theme.Radius.card))
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
