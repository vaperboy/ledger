import SwiftUI
import Simulation

struct StoreGoldChip: View {
    var amount: Int
    private let session = StoreSession.shared

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            StoreCoin(size: 20)
            Text(session.isAdmin ? "Unlimited" : amount.formatted()).textStyle(.headline, tint: Theme.ink, numeric: true)
        }
        .padding(.horizontal, Theme.Space.m).frame(minHeight: 36)
        .background(Capsule().fill(Theme.surfaceRaised))
        .overlay(Capsule().strokeBorder(StoreColors.yellow.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.isAdmin ? "Unlimited gold" : StoreText.gold(amount))
        .accessibilityIdentifier("store-gold")
    }
}

/// The pass once premium is open: level, progress, the next reward and a way in.
struct StoreSeasonCard: View {
    @ObservedObject private var model = SeasonModel.shared
    @Environment(Entitlements.self) private var ent

    var body: some View {
        let pass: SeasonPass = model.pass
        let left: Int = pass.daysLeft(today: model.today)
        let ready: Int = pass.claimableCount(isPlus: model.premiumOpen(plus: ent.isPlus, founder: ent.isFounder))
        let fill: Double = pass.isComplete ? 1 : (Double(pass.tier) + pass.tierProgress) / Double(SeasonPass.tierCount)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            OfferPicture(name: "offer.seasonlevels")
            HStack {
                Text("SEASON \(pass.seasonNumber) PASS").font(.title3.weight(.black)).italic().foregroundStyle(.white)
                Spacer()
                if ready > 0 { StoreTag(text: ready == 1 ? "1 reward ready" : "\(ready) rewards ready", tint: StoreColors.yellow) }
            }
            Text(pass.isComplete ? "All \(SeasonPass.tierCount) tiers reached" : "Level \(pass.tier) of \(SeasonPass.tierCount)")
                .font(.headline.weight(.heavy)).foregroundStyle(.white)
            GeometryReader { (g: GeometryProxy) in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.3))
                    Capsule().fill(StoreColors.yellow).frame(width: max(8, g.size.width * fill))
                }
            }
            .frame(height: 10)
            Text(nextReward(pass)).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(left == 1 ? "Ends tomorrow" : "\(left) days left").font(.caption.weight(.heavy)).foregroundStyle(.white)
                Spacer()
                NavigationLink {
                    SeasonView().appScreen(title: "Season Pass", subtitle: "Tiers and rewards")
                } label: {
                    Text("Open pass").font(.headline.weight(.heavy)).foregroundStyle(StoreColors.priceInk)
                        .padding(.horizontal, Theme.Space.l).frame(minHeight: 44)
                        .background(Capsule().fill(StoreColors.yellow))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("store-open-pass")
            }
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(StoreColors.pink)))
        .padding(.horizontal, Theme.Space.m)
    }

    private func nextReward(_ pass: SeasonPass) -> String {
        guard !pass.isComplete else { return "Every reward of this season is within reach." }
        for t in (pass.tier + 1)...SeasonPass.tierCount {
            if let r = pass.reward(.free, tier: t) { return "Next reward: \(r.title), at level \(t)" }
        }
        return "More rewards arrive as you play."
    }
}

struct BoxTile: View {
    var kind: BoxKind
    var index: Int

    var body: some View {
        let tint: Color = kind == .elite ? StoreColors.red : (kind == .grand || kind == .cardElite ? StoreColors.purple : (kind.isCardPack ? StoreColors.blue : StoreColors.orange))
        VStack(spacing: Theme.Space.xs) {
            Text(kind.title.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
            BoxArt(kind: kind, size: 60).padding(.vertical, Theme.Space.xs)
            StorePriceBar(gold: kind.price)
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 156)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(tint)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct PackTile: View {
    var pack: GoldPack
    var first: Bool
    var best: Bool

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(pack.name).font(.caption.weight(.heavy)).foregroundStyle(.white).lineLimit(1)
            RewardIcon(reward: .gold(GoldStore.totalGold(pack, firstPurchase: first)), size: 44, art: pack.art)
            if best { StoreTag(text: "BEST VALUE", tint: StoreColors.red) } else if first { StoreTag(text: "+BONUS", tint: StoreColors.green) } else { Color.clear.frame(height: 18) }
            StoreAppStoreButton(item: .goldPack(pack.id), identifier: "pack-" + pack.id)
        }
        .padding(Theme.Space.xs)
        .frame(maxWidth: .infinity, minHeight: 168)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(StoreColors.orange)))
        .accessibilityElement(children: .contain)
    }
}
