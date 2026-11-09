import SwiftUI
import Simulation

/// One kind of box: the full odds first, the count towards the guaranteed rare in words, then the open button. Nothing here counts down or presses.
struct BoxView: View {
    var kind: BoxKind
    var paidBoxesAllowed: Bool
    private let session = StoreSession.shared
    @State private var opened: OpenedBox?
    @State private var shortOfGold = false
    @State private var showPacks = false
    @State private var working = false

    var body: some View {
        let stock: Int = session.state.count(kind)
        PhonePageScroll(spacing: Theme.Space.l) {
            OnlineGroup(title: "What it holds", footer: kind.isPaid ? "" : "Season boxes come from the Season Pass. They are never sold.") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(blurb).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    if kind.isPaid { GoldAmount(amount: kind.price, style: .figure) }
                }
                .padding(.vertical, Theme.Space.m)
            }
            OnlineGroup(title: "Odds, shown before you open", footer: "These are the exact chances for every box. A cosmetic you already own is replaced by an artifact of the same rarity.") {
                BoxOddsTable(kind: kind).padding(.vertical, Theme.Space.m)
            }
            if kind.isPaid {
                OnlineGroup(title: "Guaranteed rare") {
                    Text(session.state.pity.text).textStyle(.body).fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.Space.m)
                }
            }
            openGroup(stock: stock)
        }
        .appScreen(title: kind.title, subtitle: kind.isPaid ? "Paid with gold" : "A gift from the Season Pass")
        .task { await session.load() }
        .centerSheet(item: $opened, title: "You opened a box") { (o: OpenedBox) in
            BoxResultCard(opened: o, kind: kind, paidBoxesAllowed: paidBoxesAllowed, onShort: { shortOfGold = true }, onNew: { opened = $0 })
        }
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") {
            ShortOfGoldCard(onPacks: { shortOfGold = false; showPacks = true })
        }
        .navigationDestination(isPresented: $showPacks) { GoldPacksView() }
    }

    private var blurb: String {
        switch kind {
        case .free: return "A small gift: usually a cosmetic or an artifact, sometimes a little gold."
        case .cabinet: return "Cosmetics and numbered artifacts for your cabinet. Gold prizes are small."
        case .grand: return "Better odds of rare and epic pieces. Gold prizes stay small."
        }
    }

    @ViewBuilder private func openGroup(stock: Int) -> some View {
        OnlineGroup(title: "Open", footer: stock > 0 ? "" : (kind.isPaid ? "Paid with gold from your balance: \(StoreText.gold(session.available)) available." : "You have no Season boxes right now.")) {
            VStack(spacing: Theme.Space.s) {
                if stock > 0 { Text(stock == 1 ? "You have 1 box in stock." : "You have \(stock) boxes in stock.").textStyle(.body).frame(maxWidth: .infinity, alignment: .leading) }
                Button { open() } label: { Text(buttonTitle(stock)).frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(working || (!kind.isPaid && stock == 0) || (kind.isPaid && !paidBoxesAllowed))
                    .accessibilityIdentifier("box-open")
                if kind.isPaid && !paidBoxesAllowed {
                    Text("Paid boxes are not offered in your region.").textStyle(.caption)
                }
            }
            .padding(.vertical, Theme.Space.m)
        }
    }

    private func buttonTitle(_ stock: Int) -> String {
        if stock > 0 { return "Open a box from stock" }
        return kind.isPaid ? "Open for \(StoreText.gold(kind.price))" : "No box to open"
    }

    private func open() {
        if session.state.count(kind) == 0 && kind.isPaid && session.available < kind.price { shortOfGold = true; return }
        working = true
        Task {
            let out = await session.openBox(kind, paidBoxesAllowed: paidBoxesAllowed)
            working = false
            if let out { Haptics.success(); opened = OpenedBox(opening: out) }
            else if session.problem != nil && session.available < kind.price && kind.isPaid { shortOfGold = true }
        }
    }
}

struct OpenedBox: Identifiable {
    let id = UUID()
    var opening: BoxOpening
}

/// What the box held, and "Open another" for a box that is paid for or in stock.
struct BoxResultCard: View {
    var opened: OpenedBox
    var kind: BoxKind
    var paidBoxesAllowed: Bool
    var onShort: () -> Void
    var onNew: (OpenedBox) -> Void
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private let session = StoreSession.shared
    @State private var working = false

    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        let r: BoxResult = opened.opening.result
        VStack(spacing: Theme.Space.m) {
            RarityTag(rarity: r.rarity)
            content(r)
            if r.guaranteed { Text("This was your guaranteed rare.").textStyle(.caption) }
            ForEach(opened.opening.completed, id: \.id) { (c: ArtifactCollection) in
                Text("Collection complete: \(c.name). Your reward: \(GoldCosmetics.cosmetic(c.rewardID)?.item.title ?? "a cosmetic").")
                    .textStyle(.body, tint: Theme.gain).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .popupFooter {
            PopupFooter(cancel: "Done", action: againTitle, onCancel: { close() }, onAction: { another() }, actionEnabled: canAgain && !working)
        }
    }

    @ViewBuilder private func content(_ r: BoxResult) -> some View {
        switch r.content {
        case .cosmetic(let id):
            let c: GoldCosmetic? = GoldCosmetics.cosmetic(id)
            Text(c?.item.title ?? "A cosmetic").textStyle(.title).multilineTextAlignment(.center)
            Text((c?.item.kind.label ?? "Cosmetic") + ". " + (c?.item.detail ?? "")).textStyle(.caption).multilineTextAlignment(.center)
            Text("Added to your wardrobe.").textStyle(.caption, tint: Theme.gain)
        case .artifact(let item):
            let def: ArtifactDef? = ArtifactCatalog.def(item.defID)
            Text(def?.name ?? "Artifact").textStyle(.title).multilineTextAlignment(.center)
            Text(ArtifactCatalog.label(item)).textStyle(.figure, tint: r.rarity.tint, numeric: true)
            Text(def?.note ?? "").textStyle(.caption).multilineTextAlignment(.center)
            Text("Added to your cabinet.").textStyle(.caption, tint: Theme.gain)
        case .gold(let g, let doubled):
            GoldAmount(amount: g, style: .display)
            if doubled { Text("Doubled: this was a rare double.").textStyle(.caption, tint: Theme.gain) }
        }
    }

    private var canAgain: Bool {
        let stock: Int = session.state.count(kind)
        if stock > 0 { return true }
        return kind.isPaid && paidBoxesAllowed
    }

    private var againTitle: String {
        let stock: Int = session.state.count(kind)
        if stock > 0 { return "Open another (\(stock) in stock)" }
        return kind.isPaid ? "Open another for \(StoreText.gold(kind.price))" : "No more boxes"
    }

    private func another() {
        if session.state.count(kind) == 0 && kind.isPaid && session.available < kind.price { close(); onShort(); return }
        working = true
        Task {
            let out = await session.openBox(kind, paidBoxesAllowed: paidBoxesAllowed)
            working = false
            if let out { Haptics.success(); onNew(OpenedBox(opening: out)) }
            else { close(); onShort() }
        }
    }
}

/// A calm note when the player lacks gold: what is missing and a way to the value packs. It is shown once per attempt and never repeats on its own.
struct ShortOfGoldCard: View {
    var onPacks: () -> Void
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Text("You have \(StoreText.gold(StoreSession.shared.available)) available, which is not enough for this.").textStyle(.body).multilineTextAlignment(.center)
            Text("Larger gold packs give more gold for the same money. Gold from the Season Pass and from selling artifacts counts too.").textStyle(.caption).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .popupFooter {
            PopupFooter(cancel: "Not now", action: "See value packs", onCancel: { close() }, onAction: { onPacks() })
        }
    }
}
