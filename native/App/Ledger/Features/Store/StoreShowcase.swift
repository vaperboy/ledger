import SwiftUI
import Simulation

// The offer cards of the Store: the featured carousel, gold packs, the Season Pass banner and the box cards. Every price is on the card,
// and each card lists what you get.

/// One card of the featured carousel.
struct StoreFeature: Identifiable {
    enum Action {
        case seasonBundle
        case pack(GoldPack)
        case boxBundle(BoxBundle)
        case box(BoxKind)
    }
    var id: String
    var tag: String
    var title: String
    var gets: [String]
    /// "$14.99" or "120 gold", always written out.
    var price: String
    var tint: Color = Theme.gold
    /// The best deal glows and shimmers.
    var highlight = false
    /// A real fact about the offer, for example how many days the season has left.
    var footnote = ""
    var action: Action
}

/// A horizontal row of featured offers that snap one by one, with dots below.
struct FeaturedCarousel: View {
    var features: [StoreFeature]
    var onAsk: (StoreFeature.Action) -> Void
    @State private var current: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(features) { (f: StoreFeature) in
                        card(f)
                            .containerRelativeFrame(.horizontal) { (w: CGFloat, _: Axis) in w * 0.88 }
                            .scrollTransition { (content: EmptyVisualEffect, phase: ScrollTransitionPhase) in
                                content
                                    .opacity(phase.isIdentity || reduceMotion ? 1 : 0.7)
                                    .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.95)
                            }
                            .id(f.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, Theme.Space.s)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .scrollClipDisabled()
            if features.count > 1 {
                HStack(spacing: 6) {
                    ForEach(features) { (f: StoreFeature) in
                        let on: Bool = (current ?? features.first?.id) == f.id
                        Capsule().fill(on ? Theme.accent : Theme.lineStrong).frame(width: on ? 18 : 6, height: 6)
                            .animation(Motion.quick(reduceMotion), value: on)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func card(_ f: StoreFeature) -> some View {
        switch f.action {
        case .box(let kind):
            NavigationLink { BoxView(kind: kind, paidBoxesAllowed: true) } label: { face(f, cta: "See odds and open") }
                .buttonStyle(PressableStyle())
        default:
            Button { onAsk(f.action) } label: { face(f, cta: "Review and buy") }
                .buttonStyle(PressableStyle())
        }
    }

    private func face(_ f: StoreFeature, cta: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                StoreTag(text: f.tag, tint: f.tint)
                Spacer()
                Text(f.price).textStyle(.figure, tint: Theme.ink, numeric: true)
            }
            Text(f.title).textStyle(.title).fixedSize(horizontal: false, vertical: true)
            Text("If you buy this, you get").capsLabel(Theme.inkFaint)
            ForEach(0..<f.gets.count, id: \.self) { (i: Int) in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(f.tint)
                    Text(f.gets[i]).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !f.footnote.isEmpty { Text(f.footnote).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: Theme.Space.xs)
            HStack {
                Text(cta).textStyle(.headline, tint: Theme.accent)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.accent)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, minHeight: 272, alignment: .topLeading)
        .background(StoreSurface(tint: f.tint, glow: f.highlight))
        .storeSheen(radius: Theme.Radius.hero, enabled: f.highlight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One gold pack: the heap of coins, the gold you get, the real price and how it compares. The best value glows and shimmers.
struct PackCard: View {
    var pack: GoldPack
    var first: Bool
    var best: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                StoreCoinHeap(tier: (GoldStore.packs.firstIndex(where: { $0.id == pack.id }) ?? 0) + 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Space.s) {
                        Text(pack.name).textStyle(.headline)
                        if best { StoreTag(text: "Best value") }
                    }
                    GoldAmount(amount: GoldStore.totalGold(pack, firstPurchase: first))
                    Text(deal).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s)
                Text(GoldStore.priceText(cents: pack.priceCents))
                    .textStyle(.headline, tint: Theme.accentInk, numeric: true)
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                    .background(Capsule().fill(Theme.accent))
            }
            .padding(Theme.Space.m)
            .frame(minHeight: 76)
            .background(StoreSurface(tint: Theme.gold, glow: best, radius: Theme.Radius.card))
            .storeSheen(radius: Theme.Radius.card, enabled: best)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("pack-" + pack.id)
    }

    private var deal: String {
        var parts: [String] = []
        let extra: Int = GoldStore.extraPercent(pack)
        parts.append(extra == 0 ? "The base rate" : "\(extra)% more gold per \(GoldStore.priceText(cents: 100)) than the \(GoldStore.packs[0].name)")
        if first { parts.append("includes \(GoldStore.firstPurchaseBonus(pack).formatted()) bonus gold") }
        return parts.joined(separator: ", ")
    }
}

/// The Season Pass: this season's tier, a bar that fills, the days left (the real end of the season) and rewards waiting.
struct SeasonBanner: View {
    @ObservedObject private var model = SeasonModel.shared
    @Environment(Entitlements.self) private var ent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: Double = 0

    var body: some View {
        let pass: SeasonPass = model.pass
        let left: Int = pass.daysLeft(today: model.today)
        let ready: Int = pass.claimableCount(isPlus: ent.isPlus)
        NavigationLink {
            SeasonView().appScreen(title: "Season Pass", subtitle: "Tiers and rewards")
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text("Season \(pass.seasonNumber) Pass").capsLabel(Theme.accent)
                    Spacer()
                    if ready > 0 { StoreTag(text: ready == 1 ? "1 reward ready" : "\(ready) rewards ready", tint: Theme.gain) }
                }
                Text("Tier \(pass.tier) of \(SeasonPass.tierCount)").textStyle(.title)
                GeometryReader { (g: GeometryProxy) in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.inset)
                        Capsule().fill(LinearGradient(colors: [Theme.goldDeep, Theme.gold, Theme.goldLight], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, g.size.width * fill))
                            .storeSheen(radius: 4)
                    }
                }
                .frame(height: 8)
                Text(left == 1 ? "Ends tomorrow" : "\(left) days left in this season").textStyle(.caption)
                Text("Free rewards come from playing. A Plus track of extra rewards is included with Ledger Plus.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.l)
            .background(StoreSurface(tint: Theme.gold))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableStyle())
        .onAppear {
            let target: Double = pass.isComplete ? 1 : (Double(pass.tier) + pass.tierProgress) / Double(SeasonPass.tierCount)
            if reduceMotion { fill = target } else { Motion.animate(.spring(response: 0.9, dampingFraction: 0.85)) { fill = target } }
        }
    }
}

/// A paid box: its picture, price, exact odds, the guarantee and what one purchase gets you.
struct BoxShowcaseCard: View {
    var kind: BoxKind
    var index: Int

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            BoxArt(kind: kind, size: 70).storeFloat(phase: Double(index) * 0.35).padding(.top, Theme.Space.xs)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text(kind.title).textStyle(.headline)
                    Spacer()
                    GoldAmount(amount: kind.price)
                }
                Text(kind.blurb).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                BoxOddsBar(kind: kind).padding(.top, 2)
                Text(BoxOdds.rarityPercent(kind).map { "\($0.rarity.title) \(String(format: "%.2f", $0.percent))%" }.joined(separator: "  ·  "))
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                Text("If you buy this, you get one prize: a cosmetic, an artifact or a small gold prize of at most \(StoreText.gold(BoxOdds.largestGold(kind))).")
                    .textStyle(.caption, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text("A rare or better item is guaranteed at least once in every \(BoxPity.threshold) paid boxes.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("See every prize and open").textStyle(.headline, tint: Theme.accent)
                    LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.accent)
                }
                .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.m)
        .background(StoreSurface(tint: kind == .grand ? BoxRarity.epic.tint : Theme.gold, radius: Theme.Radius.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
