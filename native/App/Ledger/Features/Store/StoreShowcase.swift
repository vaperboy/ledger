import SwiftUI
import Simulation

struct StoreGoldChip: View {
    var amount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            StoreCoin(size: 20).storeFloat(amplitude: 1.5, period: 3.6)
            CountingNumber(value: reduceMotion ? Double(amount) : shown).textStyle(.headline, tint: Theme.ink, numeric: true)
        }
        .padding(.horizontal, Theme.Space.m).frame(minHeight: 36)
        .background(Capsule().fill(Theme.surfaceRaised))
        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.4), lineWidth: 0.8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StoreText.gold(amount))
        .accessibilityIdentifier("store-gold")
        .onAppear { if reduceMotion { shown = Double(amount) } else { Motion.animate(.easeOut(duration: 1.0)) { shown = Double(amount) } } }
        .onChange(of: amount) { (_: Int, new: Int) in
            if reduceMotion { shown = Double(new) } else { Motion.animate(.easeOut(duration: 0.9)) { shown = Double(new) } }
        }
    }
}

struct StoreSeasonCard: View {
    @ObservedObject private var model = SeasonModel.shared
    @Environment(Entitlements.self) private var ent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: Double = 0

    var body: some View {
        let pass: SeasonPass = model.pass
        let left: Int = pass.daysLeft(today: model.today)
        let ready: Int = pass.claimableCount(isPlus: model.premiumOpen(plus: ent.isPlus, founder: ent.isFounder))
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Season \(pass.seasonNumber) Pass").capsLabel(Theme.accent)
                Spacer()
                if ready > 0 { StoreTag(text: ready == 1 ? "1 reward ready" : "\(ready) rewards ready", tint: Theme.gain) }
            }
            Text(pass.isComplete ? "All \(SeasonPass.tierCount) tiers reached" : "Level \(pass.tier) of \(SeasonPass.tierCount)").textStyle(.title)
            GeometryReader { (g: GeometryProxy) in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inset)
                    Capsule().fill(LinearGradient(colors: [Theme.goldDeep, Theme.gold, Theme.goldLight], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, g.size.width * fill))
                        .storeSheen(radius: 4)
                }
            }
            .frame(height: 8)
            Text(nextReward(pass)).textStyle(.caption, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(left == 1 ? "Ends tomorrow" : "\(left) days left").textStyle(.caption)
                Spacer()
                NavigationLink {
                    SeasonView().appScreen(title: "Season Pass", subtitle: "Tiers and rewards")
                } label: {
                    Text("Open pass").textStyle(.headline, tint: Theme.accentInk)
                        .padding(.horizontal, Theme.Space.l).frame(minHeight: 40)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("store-open-pass")
            }
        }
        .padding(Theme.Space.l)
        .background(StoreSurface(tint: Theme.gold))
        .onAppear {
            let target: Double = pass.isComplete ? 1 : (Double(pass.tier) + pass.tierProgress) / Double(SeasonPass.tierCount)
            if reduceMotion { fill = target } else { Motion.animate(.spring(response: 0.9, dampingFraction: 0.85)) { fill = target } }
        }
    }

    private func nextReward(_ pass: SeasonPass) -> String {
        guard !pass.isComplete else { return "Every reward of this season is within reach." }
        for t in (pass.tier + 1)...SeasonPass.tierCount {
            if let r = pass.reward(.free, tier: t) { return "Next reward: \(r.title), at level \(t)" }
        }
        return "More rewards arrive as you play."
    }
}

struct StoreProRow: View {
    var onPlans: () -> Void
    @Environment(Entitlements.self) private var ent

    var body: some View {
        Button { Haptics.tap(); onPlans() } label: {
            HStack(spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.lock, size: Theme.Icon.large, tint: Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plans and gold").textStyle(.headline)
                    Text(subtitle).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s)
                if ent.ownsPro || ent.isPlus { StoreTag(text: "Owned", tint: Theme.gain) }
                else { Text("See all").textStyle(.caption, tint: Theme.accent, weight: .semibold) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(Theme.Space.m)
            .frame(minHeight: 44)
            .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("store-plans")
    }

    private var subtitle: String {
        if ent.isFounder { return "Founder's Edition is yours. Gold packs are here too." }
        if ent.isPlus { return "Ledger Plus is active. Gold packs are here too." }
        return "Plus, Pro, Battle Pass, Founder's Edition and gold packs."
    }
}

struct BoxTile: View {
    var kind: BoxKind
    var index: Int

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            BoxArt(kind: kind, size: 64).storeFloat(phase: Double(index) * 0.35).padding(.top, Theme.Space.xs)
            Text(kind.title).textStyle(.headline).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            GoldAmount(amount: kind.price)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 156)
        .background(StoreSurface(tint: kind == .grand || kind == .cardElite ? BoxRarity.epic.tint : Theme.gold, radius: Theme.Radius.card))
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
            if best { StoreTag(text: "Best value") } else { Color.clear.frame(height: 18) }
            StoreCoinHeap(tier: (GoldStore.packs.firstIndex(where: { $0.id == pack.id }) ?? 0) + 1)
            Text(pack.name).textStyle(.headline).lineLimit(1)
            Text(GoldStore.totalGold(pack, firstPurchase: first).formatted()).textStyle(.body, tint: Theme.ink, numeric: true)
            Text(first ? "gold, bonus in" : "gold").textStyle(.caption)
            PurchaseButton(item: .goldPack(pack.id), minHeight: 34, identifier: "pack-" + pack.id)
        }
        .padding(.horizontal, Theme.Space.xs).padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 168)
        .background(StoreSurface(tint: Theme.gold, glow: best, radius: Theme.Radius.card))
        .storeSheen(radius: Theme.Radius.card, enabled: best)
        .accessibilityElement(children: .contain)
    }
}
