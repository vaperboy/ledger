import SwiftUI
import StoreKit
import Simulation

struct StoreApp: View {
    @Environment(OnlineSession.self) private var online
    @Environment(Entitlements.self) private var ent
    private let session = StoreSession.shared
    @State private var pending: PendingAction?
    @State private var showPlans = false
    @State private var showRedeem = false
    @State private var showInfo = false
    @AppStorage(LootBoxChoice.key) private var lootOff = false

    var body: some View {
        let paid: Bool = paidBoxesAllowed
        PhonePageScroll(spacing: Theme.Space.xl) {
            StoreSeasonCard().storeAppear(0)
            StoreProRow(onPlans: { showPlans = true }).storeAppear(1)
            lootBoxes(paid: paid).storeAppear(2)
            stockGroup(paid: paid)
            packsGroup.storeAppear(3)
            seasonBundleRow.storeAppear(4)
            collectionGroup.storeAppear(5)
            footer
        }
        .appScreen(title: "Store", subtitle: "") { StoreGoldChip(amount: session.gold) }
        .confirmAction($pending)
        .centerSheet(isPresented: $showPlans, title: "Ledger plans", size: .tall, category: .detail, tone: .prestige) { ProPlansView() }
        .centerSheet(isPresented: $showInfo, title: "Odds and rules", size: .tall) { LootBoxInfoSheet(kind: .cabinet) }
        .offerCodeRedemption(isPresented: $showRedeem) { _ in Task { await ent.restore() } }
        .task { await session.load(); await ent.loadProducts() }
    }

    private var paidBoxesAllowed: Bool {
        if case .open(let paid) = StoreGate.access(countryCode: online.profile?.countryCode) { return paid && !lootOff }
        return false
    }

    private func lootBoxes(paid: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Loot boxes").capsLabel(Theme.inkFaint)
                Spacer()
                LootInfoButton { showInfo = true }
            }
            .padding(.horizontal, Theme.Space.m)
            if paid {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(Array(BoxKind.allCases.filter { $0.isPaid }.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                        NavigationLink { BoxView(kind: kind, paidBoxesAllowed: true) } label: { BoxTile(kind: kind, index: i) }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("store-box-" + kind.rawValue)
                    }
                }
            } else {
                Text(lootOff ? "Loot boxes are off. Cosmetics are on sale directly for gold below." : "Paid boxes are not offered where you are. Season boxes can still be opened.")
                    .textStyle(.body, tint: Theme.inkSoft).padding(.horizontal, Theme.Space.m)
            }
        }
    }

    @ViewBuilder private func stockGroup(paid: Bool) -> some View {
        let kinds: [BoxKind] = BoxKind.allCases.filter { session.state.count($0) > 0 && (!$0.isPaid || paid) }
        if !kinds.isEmpty {
            OnlineGroup(title: "Boxes you have", footer: "") {
                ForEach(Array(kinds.enumerated()), id: \.element) { (i: Int, kind: BoxKind) in
                    if i > 0 { Hairline() }
                    NavigationLink { BoxView(kind: kind, paidBoxesAllowed: paid) } label: {
                        OnlineLine(glyph: Glyph.luxury, title: kind.title, note: "Open it", value: "\(session.state.count(kind))", chevron: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var packsGroup: some View {
        let first: Bool = !session.state.firstPurchaseDone
        let best: String? = StorePurchase.bestPack?.id
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Gold packs").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(GoldStore.packs) { (pack: GoldPack) in
                    PackTile(pack: pack, first: first, best: pack.id == best) { pending = StorePurchase.pack(pack) }
                }
            }
            if session.isVisualOnly {
                Text("Preview store: nothing is charged and no real purchase happens in this build.").textStyle(.caption).padding(.horizontal, Theme.Space.m)
            }
            Text(first ? "Your first pack carries a one-time bonus. Bigger packs give more gold for the same money." : "Bigger packs give more gold for the same money.")
                .textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var seasonBundleRow: some View {
        let b: SeasonBundle = GoldStore.seasonBundle
        return Button { pending = StorePurchase.seasonBundle() } label: {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(b.name).textStyle(.headline)
                    Text("\(StoreText.gold(b.gold)), \(StorePurchase.boxText(b)) and Ledger Plus for this season").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s)
                Text(GoldStore.priceText(cents: b.priceCents))
                    .textStyle(.headline, tint: Theme.accentInk, numeric: true)
                    .padding(.horizontal, Theme.Space.l).frame(minHeight: 40)
                    .background(Capsule().fill(Theme.accent))
            }
            .padding(Theme.Space.m)
            .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("pack-season-bundle")
    }

    private var collectionGroup: some View {
        OnlineGroup(title: "Collection and auction", footer: "") {
            NavigationLink { CollectionView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Collection", note: "Artifacts, trophies and auctions", chevron: true) }
                .buttonStyle(PressableStyle())
            Hairline()
            NavigationLink { StoreShelfView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Cosmetics and bundles", note: "Bought with gold", chevron: true) }
                .buttonStyle(PressableStyle())
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.l) {
                Button { Task { await ent.restore() } } label: { Text("Restore purchases").textStyle(.caption, tint: Theme.accent, weight: .semibold).frame(minHeight: 32) }
                    .buttonStyle(PressableStyle())
                    .disabled(ent.isBusy)
                    .accessibilityIdentifier("store-restore")
                if ent.offerCodesAvailable {
                    Button { Haptics.tap(); showRedeem = true } label: { Text("Redeem a code").textStyle(.caption, tint: Theme.accent, weight: .semibold).frame(minHeight: 32) }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("store-redeem")
                }
                Link("Terms", destination: LedgerLinks.terms).textStyle(.caption)
                Link("Privacy", destination: LedgerLinks.privacy).textStyle(.caption)
            }
            if let note = ent.message { Text(note).textStyle(.caption) }
            Text(StoreText.goldRule).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.m)
    }
}
