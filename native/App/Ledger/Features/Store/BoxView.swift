import SwiftUI
import Simulation

/// One kind of box: the full odds first, the count towards the guaranteed rare in words, then the open button. Nothing here counts down or presses.
struct BoxView: View {
    var kind: BoxKind
    var paidBoxesAllowed: Bool
    private let session = StoreSession.shared
    @State private var opened: OpenedBox?
    @State private var shortOfGold = false
    @State private var shortNeed = 0
    @State private var showPacks = false
    @State private var working = false
    @State private var pending: PendingAction?

    var body: some View {
        let stock: Int = session.state.count(kind)
        PhonePageScroll(spacing: Theme.Space.l) {
            header
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
        .confirmAction($pending)
        .centerSheet(item: $opened, title: "You opened a box") { (o: OpenedBox) in
            BoxResultCard(opened: o, kind: kind, paidBoxesAllowed: paidBoxesAllowed,
                          onShort: { shortNeed = kind.price; shortOfGold = true }, onNew: { opened = $0 }, onMore: { showPacks = true })
        }
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") {
            ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true }, onPick: { (p: GoldPack) in
                shortOfGold = false
                StorePurchase.afterPopup { pending = StorePurchase.pack(p) }
            })
        }
        .navigationDestination(isPresented: $showPacks) { GoldPacksView() }
    }

    private var header: some View {
        VStack(spacing: Theme.Space.m) {
            BoxArt(kind: kind, size: 110).storeFloat(amplitude: 4, period: 4.6).padding(.top, Theme.Space.s)
            Text(kind.blurb).textStyle(.body).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if kind.isPaid {
                GoldAmount(amount: kind.price, style: .figure)
                Text("If you buy this, you get one opening: a cosmetic, an artifact or a small gold prize of at most \(StoreText.gold(BoxOdds.largestGold(kind))).")
                    .textStyle(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Season boxes come from the Season Pass. They are never sold.").textStyle(.caption).multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity)
        .background(StoreSurface(tint: kind == .grand ? BoxRarity.epic.tint : Theme.gold))
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
        if session.state.count(kind) == 0 && kind.isPaid && session.available < kind.price { shortNeed = kind.price; shortOfGold = true; return }
        working = true
        Task {
            let out = await session.openBox(kind, paidBoxesAllowed: paidBoxesAllowed)
            working = false
            if let out { Haptics.success(); opened = OpenedBox(opening: out) }
            else if session.problem != nil && session.available < kind.price && kind.isPaid { shortNeed = kind.price; shortOfGold = true }
        }
    }
}

struct OpenedBox: Identifiable {
    let id = UUID()
    var opening: BoxOpening
}

/// The reveal of a box: the closed box floats, then opens into light rays and the prize, with more effects for rarer prizes (confetti from rare up).
/// Under Reduce Motion the prize shows at once. Below the prize, "Open another" and an always-present prompt to get more boxes or gold.
struct BoxResultCard: View {
    var opened: OpenedBox
    var kind: BoxKind
    var paidBoxesAllowed: Bool
    var onShort: () -> Void
    var onNew: (OpenedBox) -> Void
    var onMore: () -> Void
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let session = StoreSession.shared
    @State private var working = false
    @State private var revealed = false

    private func close() { if let c = popupClose { c() } else { systemDismiss() } }
    private var shown: Bool { revealed || reduceMotion }

    var body: some View {
        let r: BoxResult = opened.opening.result
        VStack(spacing: Theme.Space.m) {
            stage(r)
            if shown {
                VStack(spacing: Theme.Space.s) {
                    RarityTag(rarity: r.rarity)
                    content(r)
                    if r.guaranteed { Text("This was your guaranteed rare.").textStyle(.caption) }
                    ForEach(opened.opening.completed, id: \.id) { (c: ArtifactCollection) in
                        Text("Collection complete: \(c.name). Your reward: \(GoldCosmetics.cosmetic(c.rewardID)?.item.title ?? "a cosmetic").")
                            .textStyle(.body, tint: Theme.gain).multilineTextAlignment(.center)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
                buyMore
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: opened.id) { await play() }
        .popupFooter {
            PopupFooter(cancel: "Done", action: againTitle, onCancel: { close() }, onAction: { another() }, actionEnabled: canAgain && !working)
        }
    }

    // MARK: Reveal

    private func play() async {
        if reduceMotion { revealed = true; return }
        revealed = false
        try? await Task.sleep(nanoseconds: 900_000_000)
        if Task.isCancelled { return }
        reveal()
    }

    private func reveal() {
        if revealed { return }
        Motion.animate(.spring(response: 0.55, dampingFraction: 0.66)) { revealed = true }
    }

    private func stage(_ r: BoxResult) -> some View {
        ZStack {
            if shown {
                StoreRays(tint: r.rarity.tint, size: 280, strength: r.rarity >= .epic ? 0.6 : 0.32)
                    .transition(.opacity)
                prizeTile(r)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                if r.rarity >= .rare && !reduceMotion {
                    ConfettiBurst(count: r.rarity == .legendary ? 90 : r.rarity == .epic ? 60 : 30, goldOnly: r.rarity == .legendary, originFraction: 0.5)
                        .id(opened.id)
                }
            } else {
                BoxArt(kind: kind, size: 110).storeFloat(amplitude: 4, period: 1.8)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 220)
        .contentShape(Rectangle())
        .onTapGesture { reveal() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown ? "Prize: \(r.rarity.title)" : "Opening the box")
    }

    private func prizeTile(_ r: BoxResult) -> some View {
        let tint: Color = r.rarity.tint
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.6), tint.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(tint, lineWidth: 1.5))
            switch r.content {
            case .cosmetic: Image(systemName: "paintpalette.fill").font(.system(size: 46)).foregroundStyle(Theme.ink)
            case .artifact: LedgerGlyph(glyph: Glyph.luxury, size: 52, tint: Theme.ink)
            case .gold: StoreCoin(size: 60)
            }
        }
        .frame(width: 132, height: 132)
        .storeSheen(radius: 24, strength: 0.4)
        .shadow(color: tint.opacity(r.rarity >= .epic ? 0.75 : 0.4), radius: r.rarity >= .epic ? 24 : 14)
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

    // MARK: Buy more

    /// Shown after every box, whatever it held: the price of the next one and where to get more.
    private var buyMore: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Want more?").capsLabel(Theme.inkFaint)
            Text(moreLine).textStyle(.caption, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text("You have \(StoreText.gold(session.available)) available.").textStyle(.caption)
            Button { close(); onMore() } label: { Text("See gold packs and bundles").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
    }

    private var moreLine: String {
        let paidKind: BoxKind = kind.isPaid ? kind : .cabinet
        if let b = GoldStore.boxBundles.filter({ $0.kind == paidKind }).max(by: { $0.savingPercent < $1.savingPercent }) {
            return "\(paidKind.title)es are \(StoreText.gold(paidKind.price)) each. A bundle of \(b.count) costs \(StoreText.gold(b.price)), \(b.savingPercent)% less than single boxes. Every box shows its odds first."
        }
        return "\(paidKind.title)es are \(StoreText.gold(paidKind.price)) each. Every box shows its odds first."
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

/// Shown when the player lacks gold for what they chose: what is missing, and the packs that cover it with their real prices. It appears once per
/// attempt and never repeats on its own; "Not now" is as easy to reach as the packs.
struct ShortOfGoldCard: View {
    var needed: Int = 0
    var onPacks: () -> Void
    var onPick: (GoldPack) -> Void
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        let session: StoreSession = StoreSession.shared
        let have: Int = session.available
        let short: Int = max(0, needed - have)
        let first: Bool = !session.state.firstPurchaseDone
        VStack(spacing: Theme.Space.s) {
            Text(short > 0 ? "You need \(StoreText.gold(short)) more. You have \(StoreText.gold(have)) available." : "You have \(StoreText.gold(have)) available, which is not enough for this.")
                .textStyle(.body).multilineTextAlignment(.center)
            Text("Value deals").capsLabel(Theme.inkFaint).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(deals(short: short, first: first)) { (p: GoldPack) in
                Button { onPick(p) } label: {
                    HStack(spacing: Theme.Space.m) {
                        StoreCoinHeap(tier: (GoldStore.packs.firstIndex(where: { $0.id == p.id }) ?? 0) + 1).scaleEffect(0.8)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.Space.s) {
                                Text(p.name).textStyle(.headline)
                                if p.id == StorePurchase.bestPack?.id { StoreTag(text: "Best value") }
                            }
                            Text("\(StoreText.gold(GoldStore.totalGold(p, firstPurchase: first)))\(short > 0 && GoldStore.totalGold(p, firstPurchase: first) >= short ? ", covers it" : "")")
                                .textStyle(.caption, tint: Theme.ink)
                        }
                        Spacer(minLength: Theme.Space.s)
                        Text(GoldStore.priceText(cents: p.priceCents)).textStyle(.headline, tint: Theme.accent, numeric: true)
                    }
                    .padding(Theme.Space.m)
                    .background(StoreSurface(tint: Theme.gold, glow: p.id == StorePurchase.bestPack?.id, radius: Theme.Radius.card))
                    .storeSheen(radius: Theme.Radius.card, enabled: p.id == StorePurchase.bestPack?.id)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(PressableStyle())
            }
            Text("Gold from the Season Pass and from selling artifacts counts too. You confirm the price before anything is bought.").textStyle(.caption).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .popupFooter {
            PopupFooter(cancel: "Not now", action: "See all packs", onCancel: { close() }, onAction: { onPacks() })
        }
    }

    /// The smallest packs that cover what is missing, plus the best value pack.
    private func deals(short: Int, first: Bool) -> [GoldPack] {
        var out: [GoldPack] = Array(GoldStore.packs.filter { GoldStore.totalGold($0, firstPurchase: first) >= short }.sorted { $0.priceCents < $1.priceCents }.prefix(2))
        if let best = StorePurchase.bestPack, !out.contains(where: { $0.id == best.id }) { out.append(best) }
        return out
    }
}
