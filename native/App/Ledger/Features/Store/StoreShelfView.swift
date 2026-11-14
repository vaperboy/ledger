import SwiftUI
import Simulation

/// Extra save slots, always on sale for gold. Cosmetics are sold from the daily shelf on the Store page.
struct StoreShelfView: View {
    @Environment(\.dismiss) private var dismiss
    private let session = StoreSession.shared
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0

    var body: some View {
        let owned: Set<String> = SeasonModel.shared.pass.owned
        PhonePageScroll(spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                StoreBand(title: "Save slots", glyph: Glyph.luxury, tint: StoreColors.violet)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.s), GridItem(.flexible())], spacing: Theme.Space.s) {
                    ForEach(Self.slots) { (c: GoldCosmetic) in
                        slotTile(c, owned: owned.contains(c.id), blocked: Self.isLockedSlot(c, owned: owned))
                            .adminPrice(kind: "item", id: c.id, current: StoreRotation.price(c) ?? 0)
                    }
                }
                .id(session.priceVersion)
                .padding(.horizontal, Theme.Space.m)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                NavigationLink { CustomiseView() } label: { Text("Wear what you own in Customise").textStyle(.body, tint: Theme.accent, weight: .semibold).frame(minHeight: 44) }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("shelf-look")
                Text("A slot keeps one more game. Slots never change how the game plays.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.m)
        }
        .appScreen(title: "Save slots", subtitle: "Bought with gold")
        .confirmAction($pending)
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") {
            ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; dismiss() })
        }
        .task { await session.load() }
    }

    static var slots: [GoldCosmetic] { GoldCosmetics.storeItems.filter { $0.item.kind == .saveSlot } }

    /// Slots are bought in order.
    static func isLockedSlot(_ c: GoldCosmetic, owned: Set<String>) -> Bool {
        guard let i = slots.firstIndex(where: { $0.id == c.id }), i > 0 else { return false }
        return !owned.contains(slots[i - 1].id)
    }

    private func slotTile(_ c: GoldCosmetic, owned: Bool, blocked: Bool) -> some View {
        Button { StorePurchase.ask(.cosmetic(c), pending: $pending, onShort: { (price: Int) in shortNeed = price; shortOfGold = true }) } label: {
            VStack(spacing: Theme.Space.s) {
                RewardIcon(reward: StoreReward(kind: .slot, amount: "+1", caption: "save slot"), size: 48)
                Text(c.item.title).font(.headline.weight(.heavy)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
                if owned {
                    Text("Owned").font(.headline.weight(.heavy)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
                } else if blocked {
                    Text("Buy the one before").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    StorePriceBar(gold: StoreRotation.price(c) ?? 0)
                }
            }
            .padding(Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: 168)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(StoreColors.violet)))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableStyle())
        .disabled(owned || blocked)
    }
}
