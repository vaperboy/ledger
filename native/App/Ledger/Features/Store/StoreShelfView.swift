import SwiftUI
import Simulation

struct StoreShelfView: View {
    @Environment(\.dismiss) private var dismiss
    private let session = StoreSession.shared
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.xl) {
            cosmeticsGroup.storeAppear(0)
            bundlesGroup.storeAppear(1)
            Text("Wear what you own in the Cabinet. These change how things look and how many saves you can keep, never how the game plays.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
        }
        .appScreen(title: "Cosmetics", subtitle: "Bought with gold")
        .confirmAction($pending)
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") {
            ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; dismiss() }, onPick: { (p: GoldPack) in
                shortOfGold = false
                StorePurchase.afterPopup { pending = StorePurchase.pack(p) }
            })
        }
        .task { await session.load() }
    }

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
        }
    }

    private func isLockedSlot(_ c: GoldCosmetic, owned: Set<String>) -> Bool {
        let slots: [GoldCosmetic] = GoldCosmetics.storeItems.filter { $0.item.kind == .saveSlot }
        guard c.item.kind == .saveSlot, let i = slots.firstIndex(where: { $0.id == c.id }), i > 0 else { return false }
        return !owned.contains(slots[i - 1].id)
    }

    private func cosmeticTile(_ c: GoldCosmetic, owned: Bool, blocked: Bool, index: Int) -> some View {
        let shiny: Bool = c.rarity >= .epic
        return Button { askCosmetic(c) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ItemArt(cosmetic: c, size: 36).frame(height: 56).frame(maxWidth: .infinity)
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

    private func askCosmetic(_ c: GoldCosmetic) {
        guard let price = c.price else { return }
        if session.available < price { shortNeed = price; shortOfGold = true; return }
        pending = StorePurchase.cosmetic(c, price: price)
    }

    private var bundlesGroup: some View {
        let best: String? = StorePurchase.bestBundle?.id
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Box bundles, paid with gold").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
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
            Text("The boxes wait in your stock until you open them.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func askBundle(_ b: BoxBundle) {
        if session.available < b.price { shortNeed = b.price; shortOfGold = true; return }
        pending = StorePurchase.boxBundle(b)
    }
}
