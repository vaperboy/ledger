import SwiftUI
import Simulation

/// Gold packs, the season bundle and box bundles. Larger packs give more gold per unit of money; the first pack ever bought carries a one-time bonus.
/// Real payments are not wired: while the stand-in service answers, the screen says plainly that nothing is charged.
struct GoldPacksView: View {
    private let session = StoreSession.shared
    @State private var pending: PendingAction?

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.xl) {
            if session.isVisualOnly {
                Text("Preview only: in this build nothing is charged and no real purchase happens. Packs simply add gold so you can try the store.")
                    .textStyle(.caption).padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
            }
            balance.storeAppear(0)
            packs.storeAppear(1)
            bundle.storeAppear(2)
            boxBundles.storeAppear(3)
            Text(StoreText.goldRule).textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
        }
        .appScreen(title: "Gold", subtitle: "Packs and bundles")
        .confirmAction($pending)
        .task { await session.load() }
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Your gold").capsLabel()
            GoldCounter(amount: session.gold)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoreSurface(tint: Theme.gold, glow: true))
    }

    private var packs: some View {
        let first: Bool = !session.state.firstPurchaseDone
        let best: String? = StorePurchase.bestPack?.id
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Gold packs").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            ForEach(GoldStore.packs) { (pack: GoldPack) in
                PackCard(pack: pack, first: first, best: pack.id == best) { pending = StorePurchase.pack(pack) }
            }
            Text(first ? "Your first pack carries a one-time bonus of half as much gold again." : "Bigger packs give more gold for the same money.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bundle: some View {
        let b: SeasonBundle = GoldStore.seasonBundle
        let left: Int = SeasonModel.shared.pass.daysLeft(today: SeasonModel.shared.today)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Season bundle").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            Button { pending = StorePurchase.seasonBundle() } label: {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Text(b.name).textStyle(.headline)
                        Spacer()
                        Text(GoldStore.priceText(cents: b.priceCents)).textStyle(.figure, tint: Theme.accent, numeric: true)
                    }
                    Text("If you buy this, you get").capsLabel(Theme.inkFaint)
                    GoldAmount(amount: b.gold)
                    Text("\(StorePurchase.boxText(b)) and Ledger Plus for this season. The season ends in \(left) \(left == 1 ? "day" : "days").").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                    if session.isVisualOnly { Text("The Plus pass part is not active in this preview build.").textStyle(.caption) }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StoreSurface(tint: Theme.gold))
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("pack-season-bundle")
        }
    }

    /// Box bundles are paid with gold; each row says plainly when more gold is needed.
    private var boxBundles: some View {
        let best: String? = StorePurchase.bestBundle?.id
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Box bundles, paid with gold").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            ForEach(GoldStore.boxBundles) { (b: BoxBundle) in
                let short: Int = max(0, b.price - session.available)
                Button { pending = StorePurchase.boxBundle(b) } label: {
                    HStack(spacing: Theme.Space.m) {
                        BoxArt(kind: b.kind, size: 40).padding(.trailing, Theme.Space.xs)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Theme.Space.s) {
                                Text("\(b.count) \(b.kind.title)es").textStyle(.headline)
                                if b.id == best { StoreTag(text: "Best saving") }
                            }
                            Text("\(b.savingPercent)% less than single boxes (\(StoreText.gold(b.singlesPrice)))").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                            if short > 0 { Text("You need \(StoreText.gold(short)) more gold.").textStyle(.caption, tint: Theme.warn) }
                        }
                        Spacer(minLength: Theme.Space.s)
                        GoldAmount(amount: b.price)
                    }
                    .padding(Theme.Space.m).frame(minHeight: 64)
                    .background(StoreSurface(tint: Theme.gold, glow: b.id == best && short == 0, radius: Theme.Radius.card))
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(PressableStyle())
                .disabled(short > 0)
            }
        }
    }
}
