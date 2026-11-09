import SwiftUI
import Simulation

/// Gold packs and the season bundle. Larger packs give more gold per unit of money; the first pack ever bought carries a one-time bonus.
/// Real payments are not wired: while the stand-in service answers, the screen says plainly that nothing is charged.
struct GoldPacksView: View {
    private let session = StoreSession.shared
    @State private var pending: PendingAction?

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if session.isVisualOnly {
                Text("Preview only: in this build nothing is charged and no real purchase happens. Packs simply add gold so you can try the store.")
                    .textStyle(.caption).padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
            }
            packs
            bundle
            Text(StoreText.goldRule).textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
        }
        .appScreen(title: "Gold", subtitle: "Packs and the season bundle")
        .confirmAction($pending)
        .task { await session.load() }
    }

    private var packs: some View {
        let first: Bool = !session.state.firstPurchaseDone
        return OnlineGroup(title: "Gold packs", footer: first ? "Your first pack carries a one-time bonus of half as much gold again." : "Bigger packs give more gold for the same money.") {
            ForEach(Array(GoldStore.packs.enumerated()), id: \.element.id) { (i: Int, pack: GoldPack) in
                if i > 0 { Hairline() }
                Button { ask(pack, first: first) } label: { row(pack, first: first) }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("pack-" + pack.id)
            }
        }
    }

    private func row(_ pack: GoldPack, first: Bool) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name).textStyle(.headline)
                GoldAmount(amount: GoldStore.totalGold(pack, firstPurchase: first))
                Text(deal(pack, first: first)).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Text(GoldStore.priceText(cents: pack.priceCents)).textStyle(.headline, tint: Theme.accent, numeric: true)
        }
        .padding(.vertical, Theme.Space.s).frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func deal(_ pack: GoldPack, first: Bool) -> String {
        var parts: [String] = []
        let extra: Int = GoldStore.extraPercent(pack)
        parts.append(extra == 0 ? "The base rate" : "\(extra)% more gold per \(GoldStore.priceText(cents: 100)) than the \(GoldStore.packs[0].name)")
        if first { parts.append("includes \(GoldStore.firstPurchaseBonus(pack).formatted()) bonus gold") }
        return parts.joined(separator: ", ")
    }

    private var bundle: some View {
        let b: SeasonBundle = GoldStore.seasonBundle
        let boxes: String = b.boxes.map { "\($0.count) \($0.kind.title)\($0.count == 1 ? "" : "es")" }.joined(separator: " and ")
        return OnlineGroup(title: "Season bundle", footer: "Everything in one purchase for the season. The Plus pass part is not active in this preview build.") {
            Button { askBundle(b, boxes: boxes) } label: {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack {
                        Text(b.name).textStyle(.headline)
                        Spacer()
                        Text(GoldStore.priceText(cents: b.priceCents)).textStyle(.headline, tint: Theme.accent, numeric: true)
                    }
                    GoldAmount(amount: b.gold)
                    Text("Plus \(boxes) and Ledger Plus for the season.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Space.s).frame(minHeight: 72, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("pack-season-bundle")
        }
    }

    private func ask(_ pack: GoldPack, first: Bool) {
        let gold: Int = GoldStore.totalGold(pack, firstPurchase: first)
        let note: String = session.isVisualOnly ? " Preview build: nothing is charged." : ""
        pending = PendingAction(title: "Get \(pack.name)?", message: "\(StoreText.gold(gold)) for \(GoldStore.priceText(cents: pack.priceCents)).\(note)", button: "Get gold",
                                alwaysAsk: true, tone: .investment, icon: "plus.circle") {
            Task { if await session.buyPack(pack) { Haptics.success() } }
        }
    }

    private func askBundle(_ b: SeasonBundle, boxes: String) {
        let note: String = session.isVisualOnly ? " Preview build: nothing is charged and Ledger Plus is not added." : ""
        pending = PendingAction(title: "Get the season bundle?", message: "\(StoreText.gold(b.gold)), \(boxes) and Ledger Plus for the season, for \(GoldStore.priceText(cents: b.priceCents)).\(note)",
                                button: "Get bundle", alwaysAsk: true, tone: .investment, icon: "gift") {
            Task { if await session.buySeasonBundle() { Haptics.success() } }
        }
    }
}
