import SwiftUI
import Simulation

extension BoxRarity {
    var suspense: Double { LootTiming.buildUp(self) }
}

struct BoxPlan {
    var kind: BoxKind
    var count: Int
    var stock: Int
    var gold: Int

    var toPay: Int { max(0, count - stock) }
    var cost: Int { kind.isPaid ? toPay * kind.price : 0 }
    var possible: Bool { toPay == 0 || (kind.isPaid && cost <= gold) }
    var needsGold: Bool { kind.isPaid && toPay > 0 && cost > gold }

    var title: String {
        let what: String = count == 1 ? "box" : "\(count) boxes"
        if toPay == 0 { return "Open \(what)" }
        if kind.isPaid { return "Open \(what) for \(StoreText.gold(cost))" }
        return count == 1 ? "No box to open" : "Open \(what)"
    }
}

struct BoxView: View {
    var kind: BoxKind
    var paidBoxesAllowed: Bool
    private let session = StoreSession.shared
    @State private var opened: OpenedBox?
    @State private var revealedID: UUID?
    @State private var shortOfGold = false
    @State private var shortNeed = 0
    @State private var showPacks = false
    @State private var showInfo = false
    @State private var working = false
    @State private var pending: PendingAction?

    private var paidAllowed: Bool { paidBoxesAllowed }
    private var locked: Bool { working || opened != nil }

    var body: some View {
        let stock: Int = session.state.count(kind)
        let one: BoxPlan = BoxPlan(kind: kind, count: 1, stock: stock, gold: session.available)
        let ten: BoxPlan = BoxPlan(kind: kind, count: 10, stock: stock, gold: session.available)
        VStack(spacing: Theme.Space.l) {
            Spacer(minLength: 0)
            BoxArt(kind: kind, size: 170).storeFloat(amplitude: 5, period: 4.6)
            VStack(spacing: Theme.Space.s) {
                Text(kind.blurb).textStyle(.body).multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if kind.isPaid && stock == 0 { GoldAmount(amount: kind.price, style: .figure) }
                Text(statusLine(stock)).textStyle(.caption).multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(spacing: Theme.Space.s) {
                Button { open(1) } label: { Text(one.title).frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(locked || (!kind.isPaid && stock == 0) || (kind.isPaid && !paidAllowed))
                    .accessibilityIdentifier("box-open")
                Button { open(10) } label: { Text(ten.title).frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    .disabled(locked || (!kind.isPaid && !ten.possible) || (kind.isPaid && !paidAllowed))
                    .accessibilityIdentifier("box-open-ten")
            }
        }
        .padding(.horizontal, Theme.Space.page).padding(.bottom, Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ledgerBackground()
        .appScreen(title: kind.title, subtitle: kind.isPaid ? "Paid with gold" : "A gift from the Season Pass") {
            LootInfoButton { showInfo = true }
        }
        .task {
            await session.load()
            if opened == nil, let unseen = session.pendingOpening { opened = OpenedBox(opening: unseen) }
        }
        .confirmAction($pending)
        .centerSheet(isPresented: $showInfo, title: "Odds and rules", size: .tall) { LootBoxInfoSheet(kind: kind) }
        .centerSheet(item: sheet(batch: false), title: "You opened a box") { (o: OpenedBox) in
            BoxResultCard(opened: o, paidBoxesAllowed: paidAllowed, onShort: { short(for: 1) }, onNew: { opened = $0 }, onRevealed: seen)
        }
        .centerSheet(item: sheet(batch: true), title: "You opened 10 boxes", size: .tall) { (o: OpenedBox) in
            BoxBatchCard(opened: o, paidBoxesAllowed: paidAllowed, onShort: { short(for: 10) }, onNew: { opened = $0 }, onRevealed: seen)
        }
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") {
            ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true })
        }
        .navigationDestination(isPresented: $showPacks) { StoreApp() }
    }

    private func sheet(batch: Bool) -> Binding<OpenedBox?> {
        Binding<OpenedBox?>(
            get: {
                guard let o = opened else { return nil }
                return (o.opening.results.count > 1) == batch ? o : nil
            },
            set: { (new: OpenedBox?) in
                if let new { opened = new; return }
                if let o = opened, revealedID != o.id { return }
                opened = nil
            })
    }

    private func seen(_ id: UUID) {
        revealedID = id
        session.acknowledgeOpening()
    }

    private func short(for count: Int) {
        shortNeed = BoxPlan(kind: kind, count: count, stock: session.state.count(kind), gold: session.available).cost
        shortOfGold = true
    }

    private func statusLine(_ stock: Int) -> String {
        if kind.isPaid && !paidAllowed { return "Paid boxes are not offered in your region." }
        if stock > 0 { return stock == 1 ? "You have 1 box in stock." : "You have \(stock) boxes in stock." }
        if kind.isPaid { return "\(StoreText.gold(session.available)) available." }
        return "You have no Season boxes right now."
    }

    private func open(_ count: Int) {
        guard !working, opened == nil, paidAllowed || !kind.isPaid else { return }
        let plan = BoxPlan(kind: kind, count: count, stock: session.state.count(kind), gold: session.available)
        guard plan.possible else {
            if plan.needsGold { shortNeed = plan.cost; shortOfGold = true }
            return
        }
        guard plan.cost > 0 else { start(count, plan); return }
        let what: String = count == 1 ? "a \(kind.title.lowercased())" : "\(count) \(kind.title.lowercased())es"
        let from: Int = min(count, plan.stock)
        let effect: String = from > 0 ? "you open \(what) now, \(from) from your stock and the rest bought." : "you open \(what) now."
        let offer = GoldOffer(title: "Open \(count == 1 ? "a box" : "\(count) boxes")?", effect: effect, price: plan.cost, icon: "shippingbox")
        StorePurchase.ask(offer: offer, pending: $pending, onShort: { (_: Int) in shortNeed = plan.cost; shortOfGold = true }) { start(count, plan) }
    }

    private func start(_ count: Int, _ plan: BoxPlan) {
        working = true
        Task {
            let out = await session.openBoxes(kind, count: count, paidBoxesAllowed: paidAllowed)
            if let out { opened = OpenedBox(opening: out) }
            else if plan.needsGold || (kind.isPaid && session.available < plan.cost) { shortNeed = plan.cost; shortOfGold = true }
            working = false
        }
    }
}

struct OpenedBox: Identifiable {
    let id = UUID()
    var opening: BoxOpening
}

struct BoxResultCard: View {
    var opened: OpenedBox
    var paidBoxesAllowed: Bool
    var onShort: () -> Void
    var onNew: (OpenedBox) -> Void
    var onRevealed: (UUID) -> Void
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let session = StoreSession.shared
    @State private var working = false
    @State private var revealed = false
    @State private var canSkip = false
    @State private var start = Date()
    @State private var ring = false
    @State private var faceUp = false
    @State private var showInfo = false
    @State private var desk = PieceDesk()

    private var kind: BoxKind { opened.opening.kind }
    private func close() { if let c = popupClose { c() } else { systemDismiss() } }
    private var shown: Bool { revealed || reduceMotion }

    var body: some View {
        Group {
            if showInfo {
                VStack(spacing: Theme.Space.m) {
                    LootBoxInfoContent(kind: kind)
                    Button { Motion.animate(.easeInOut(duration: 0.2)) { showInfo = false } } label: { Text("Back to the box").frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
                .frame(maxWidth: .infinity)
            } else {
                reveal
            }
        }
        .task(id: opened.id) { await play() }
    }

    private var reveal: some View {
        let r: BoxResult = opened.opening.results[0]
        return VStack(spacing: Theme.Space.s) {
            stage(r)
            if shown && faceUp {
                VStack(spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        RarityTag(rarity: r.rarity)
                        if let tag = newTag(r) { StoreTag(text: tag.text, tint: tag.tint) }
                    }
                    content(r)
                    prizeActions(r)
                    if r.guaranteed { Text("This was your guaranteed rare.").textStyle(.caption) }
                    ForEach(opened.opening.completed, id: \.id) { (c: ArtifactCollection) in
                        Text("Collection complete: \(c.name). Reward: \(GoldCosmetics.cosmetic(c.rewardID)?.item.title ?? "a cosmetic").")
                            .textStyle(.caption, tint: Theme.gain).multilineTextAlignment(.center)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) { LootInfoButton { Motion.animate(.easeInOut(duration: 0.2)) { showInfo = true } } }
        .centerSheetLocked(!shown)
        .popupFooter {
            PopupFooter(cancel: "Done", action: againTitle, onCancel: { if shown { close() } else { reveal(r) } }, onAction: { another() },
                        actionEnabled: canAgain && !working && shown && faceUp)
        }
    }

    private func play() async {
        faceUp = false
        if reduceMotion {
            revealed = true
            canSkip = true
            onRevealed(opened.id)
            await turnOver(opened.opening.results[0])
            return
        }
        revealed = false
        canSkip = true
        ring = false
        showInfo = false
        start = Date()
        let total: Double = LootTiming.buildUp(opened.opening.results[0].rarity)
        var elapsed: Double = 0
        while elapsed < total {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled || revealed { return }
            elapsed += 0.25
            LootHaptics.buildUp(progress: elapsed / total)
        }
        reveal(opened.opening.results[0])
    }

    private func reveal(_ r: BoxResult) {
        if revealed { return }
        Motion.animate(.spring(response: 0.55, dampingFraction: 0.66)) { revealed = true }
        onRevealed(opened.id)
        Task { await turnOver(r) }
    }

    /// The face-down card waits a moment, longer for rarer prizes, then turns over.
    private func turnOver(_ r: BoxResult) async {
        try? await Task.sleep(nanoseconds: UInt64(LootTiming.hold(r.rarity) * 1_000_000_000))
        if Task.isCancelled || faceUp { return }
        faceUp = true
        Motion.animate(.easeOut(duration: 0.7)) { ring = true }
        await LootHaptics.flip(r.rarity)
    }

    private func tapStage(_ r: BoxResult) {
        guard canSkip else { return }
        if !revealed && !reduceMotion {
            reveal(r)
        } else if !faceUp {
            faceUp = true
            Motion.animate(.easeOut(duration: 0.7)) { ring = true }
            Task { await LootHaptics.flip(r.rarity) }
        }
    }

    private func newTag(_ r: BoxResult) -> (text: String, tint: Color)? {
        switch r.content {
        case .cosmetic, .artifact: return ("New!", Theme.gain)
        case .gold: return ("Gold added", Theme.gold)
        case .money: return ("Cash prize", Theme.gain)
        }
    }

    private func stage(_ r: BoxResult) -> some View {
        let tint: Color = r.rarity.tint
        return ZStack {
            if shown {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(faceUp ? 0.5 : 0.28), .clear], center: .center, startRadius: 4, endRadius: 120))
                    .frame(width: 260, height: 260)
                    .allowsHitTesting(false)
                if faceUp {
                    StoreRays(tint: tint, size: 280, strength: r.rarity >= .epic ? 0.6 : 0.32)
                        .transition(.opacity)
                    Circle().strokeBorder(tint, lineWidth: 3)
                        .frame(width: 140, height: 140)
                        .scaleEffect(ring ? 2.4 : 0.4)
                        .opacity(ring ? 0 : 0.9)
                        .allowsHitTesting(false)
                }
                if let entry = HaulEntry.group([r]).first {
                    LootFlipCard(entry: entry, faceUp: faceUp, width: 118)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
                if faceUp && r.rarity >= .rare && !reduceMotion {
                    ConfettiBurst(count: r.rarity == .legendary ? 90 : r.rarity == .epic ? 60 : 30, goldOnly: r.rarity == .legendary, originFraction: 0.5)
                        .id(opened.id)
                }
            } else {
                BoxShake(kind: kind, rarity: opened.opening.results.map(\.rarity).max() ?? r.rarity, start: start)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 200)
        .overlay(alignment: .bottom) {
            if !shown && canSkip { Text("Tap to skip").textStyle(.caption) }
        }
        .contentShape(Rectangle())
        .onTapGesture { tapStage(r) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown ? "Prize: \(r.rarity.title)" : "Opening the box")
    }

    @ViewBuilder private func content(_ r: BoxResult) -> some View {
        switch r.content {
        case .cosmetic(let id):
            let c: GoldCosmetic? = GoldCosmetics.cosmetic(id)
            Text(c?.item.title ?? "A cosmetic").textStyle(.title).multilineTextAlignment(.center).lineLimit(2)
            Text(c?.item.kind.label ?? "Cosmetic").textStyle(.caption).multilineTextAlignment(.center)
        case .artifact(let item):
            let def: ArtifactDef? = ArtifactCatalog.def(item.defID)
            Text(def?.name ?? "Artifact").textStyle(.title).multilineTextAlignment(.center).lineLimit(2)
            Text(ArtifactCatalog.label(item)).textStyle(.headline, tint: r.rarity.tint, numeric: true)
            Text("Added to your cabinet.").textStyle(.caption, tint: Theme.gain).multilineTextAlignment(.center)
        case .gold(let g, let doubled):
            GoldAmount(amount: g, style: .display)
            if doubled { Text("Doubled: this was a rare double.").textStyle(.caption, tint: Theme.gain) }
        case .money:
            Text("A cash prize").textStyle(.title).multilineTextAlignment(.center)
            Text("Paid into your personal account in the game. It never buys gold.").textStyle(.caption).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private func prizeActions(_ r: BoxResult) -> some View {
        switch r.content {
        case .artifact(let item): PieceActions(item: item, desk: desk).frame(maxWidth: 320).padding(.top, Theme.Space.xs)
        case .cosmetic(let id): EquipNowButton(id: id).frame(maxWidth: 320).padding(.top, Theme.Space.xs)
        case .gold, .money: EmptyView()
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
        guard !working, shown else { return }
        if session.state.count(kind) == 0 && kind.isPaid && session.available < kind.price { close(); onShort(); return }
        working = true
        Task {
            let out = await session.openBoxes(kind, count: 1, paidBoxesAllowed: paidBoxesAllowed)
            working = false
            if let out { onNew(OpenedBox(opening: out)) }
            else if session.problem != nil { close(); onShort() }
        }
    }
}

enum PieceFate: Equatable {
    case sold(Int)
}

@MainActor @Observable
final class PieceDesk {
    private(set) var fates: [String: PieceFate] = [:]
    private(set) var busy = false
    @ObservationIgnored private let session = StoreSession.shared

    func open(_ items: [ArtifactItem]) -> [ArtifactItem] {
        items.filter { fates[$0.id] == nil && session.state.cabinet.contains($0.id) }
    }

    func sell(_ items: [ArtifactItem]) async {
        let todo: [ArtifactItem] = open(items)
        guard !busy, !todo.isEmpty else { return }
        busy = true
        let prices: [String: Int] = Dictionary(uniqueKeysWithValues: todo.map { ($0.id, session.quickPrice($0)) })
        if await session.quickSell(todo) != nil {
            for item in todo where !session.state.cabinet.contains(item.id) { fates[item.id] = .sold(prices[item.id] ?? 0) }
            Haptics.success()
        }
        busy = false
    }

}

struct PieceActions: View {
    var item: ArtifactItem
    var desk: PieceDesk
    @EnvironmentObject var store: GameStore
    @Environment(\.popupClose) private var popupClose
    private let session = StoreSession.shared

    var body: some View {
        if let fate = desk.fates[item.id] {
            switch fate {
            case .sold(let price): Text("Sold for \(session.money(price)). The cash is in your account.").textStyle(.caption, tint: Theme.gain).multilineTextAlignment(.center)
            }
        } else if item.isBound {
            LockNote(text: "Bound to your account: it cannot be sold or traded.")
        } else if session.canSellForCash && StoreGate.access(countryCode: nil) != .hidden {
            HStack(spacing: Theme.Space.s) {
                Button { Task { await desk.sell([item]) } } label: { Text("Sell for \(session.money(session.quickPrice(item)))").lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                    .disabled(desk.busy)
                    .accessibilityIdentifier("piece-sell")
                Button { Haptics.tap(); popupClose?(); store.openApp(.auctions, request: .auctionListing(item.id)) } label: { Text("Auction").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
                    .disabled(desk.busy)
                    .accessibilityIdentifier("piece-auction")
            }
        } else {
            Text("Open a game to sell it for cash.").textStyle(.caption).multilineTextAlignment(.center)
        }
    }
}

struct EquipNowButton: View {
    var id: String
    @ObservedObject private var season = SeasonModel.shared
    @State private var pending: PendingAction?

    var body: some View {
        if let r = SeasonRewards.item(id), r.kind.isEquippable {
            if season.pass.equipped[r.kind.rawValue] == id {
                Button {} label: { Text("Equipped").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true, passive: true))
                    .disabled(true)
            } else {
                Button { Haptics.success(); season.equipAsking(id, pending: $pending) } label: { Text("Equip now").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                    .accessibilityIdentifier("equip-now")
                    .confirmAction($pending)
            }
        }
    }
}

struct HaulEntry: Identifiable {
    enum Kind { case cosmetic, artifact, gold, cash }
    var id: String
    var kind: Kind
    var title: String
    var rarity: BoxRarity
    var count = 1
    var detail = ""
    var goldTotal = 0
    var cosmetic: GoldCosmetic?
    var artifact: ArtifactDef?
    var item: ArtifactItem?

    static func group(_ results: [BoxResult]) -> [HaulEntry] {
        var order: [String] = []
        var map: [String: HaulEntry] = [:]
        for r in results {
            var entry: HaulEntry
            switch r.content {
            case .cosmetic(let id):
                let c: GoldCosmetic? = GoldCosmetics.cosmetic(id)
                entry = HaulEntry(id: "c|" + id, kind: .cosmetic, title: c?.item.title ?? "Cosmetic", rarity: r.rarity, detail: c?.item.kind.label ?? "Cosmetic", cosmetic: c)
            case .artifact(let item):
                let def: ArtifactDef? = ArtifactCatalog.def(item.defID)
                entry = HaulEntry(id: "a|" + item.id, kind: .artifact, title: def?.name ?? "Artifact", rarity: r.rarity, detail: ArtifactCatalog.label(item), artifact: def, item: item)
            case .gold(let g, _):
                entry = HaulEntry(id: "g|" + r.rarity.rawValue, kind: .gold, title: "Gold", rarity: r.rarity, goldTotal: g)
            case .money:
                entry = HaulEntry(id: "m|" + r.rarity.rawValue, kind: .cash, title: "Cash prize", rarity: r.rarity, detail: "To your account")
            }
            if var old = map[entry.id] {
                old.count += 1
                old.goldTotal += entry.goldTotal
                map[entry.id] = old
            } else {
                order.append(entry.id)
                map[entry.id] = entry
            }
        }
        return order.compactMap { map[$0] }.sorted { (a: HaulEntry, b: HaulEntry) -> Bool in
            if a.rarity.rank != b.rarity.rank { return a.rarity.rank > b.rarity.rank }
            return a.title != b.title ? a.title < b.title : a.id < b.id
        }
    }

    var line: String {
        if kind == .gold { return rarity.title + ", +" + goldTotal.formatted() }
        if count == 1 && !detail.isEmpty { return rarity.title + ", " + detail }
        return rarity.title
    }
}

struct BoxBatchCard: View {
    var opened: OpenedBox
    var paidBoxesAllowed: Bool
    var onShort: () -> Void
    var onNew: (OpenedBox) -> Void
    var onRevealed: (UUID) -> Void
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let session = StoreSession.shared
    @State private var revealed = false
    @State private var working = false
    @State private var showInfo = false
    @State private var start = Date()
    @State private var desk = PieceDesk()
    @State private var pick: String?
    @State private var flipped = 0
    @State private var haulOpen = false

    private var kind: BoxKind { opened.opening.kind }
    private var shown: Bool { revealed || reduceMotion }
    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        Group {
            main
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .centerSheetLocked(!shown)
        .task(id: opened.id) { await play() }
    }

    private var main: some View {
        Group {
            if showInfo { info } else if shown && haulOpen { results } else if shown { cards } else { shaking }
        }
        .popupFooter {
            PopupFooter(cancel: "Done", action: againTitle, onCancel: { if shown { close() } else { reveal() } }, onAction: { again() },
                        actionEnabled: canAgain && !working && shown && haulOpen && !showInfo)
        }
    }

    private var shaking: some View {
        let top: BoxRarity = opened.opening.results.map(\.rarity).max() ?? .common
        return VStack(spacing: Theme.Space.s) {
            Spacer(minLength: 0)
            BoxShake(kind: kind, rarity: top, start: start)
            Text("Opening 10 boxes").textStyle(.caption)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { reveal() }
    }

    private var bestRarity: BoxRarity { opened.opening.results.map(\.rarity).max() ?? .common }

    /// Every reward as a face-down card that turns over one after another.
    private var cards: some View {
        let singles: [HaulEntry] = opened.opening.results.compactMap { (r: BoxResult) -> HaulEntry? in HaulEntry.group([r]).first }
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 5)
        let done: Bool = flipped >= singles.count
        return VStack(spacing: Theme.Space.m) {
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(Array(singles.enumerated()), id: \.offset) { (i: Int, e: HaulEntry) in
                    LootFlipCard(entry: e, faceUp: i < flipped, width: 52)
                }
            }
            Text(done ? "Here is what you got." : "Tap to turn them all.").textStyle(.caption)
            Button { Haptics.tap(); Motion.animate(.easeInOut(duration: 0.2)) { haulOpen = true } } label: { Text("See the haul").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(!done)
                .accessibilityIdentifier("box-see-haul")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PopupLayout.inset)
        .contentShape(Rectangle())
        .onTapGesture { flipAll() }
        .transition(.opacity)
    }

    private func flipAll() {
        let n: Int = opened.opening.results.count
        guard flipped < n else { return }
        flipped = n
        let best: BoxRarity = bestRarity
        Task { await LootHaptics.flip(best) }
    }

    private func startFlips() {
        let n: Int = opened.opening.results.count
        let id: UUID = opened.id
        flipped = 0
        haulOpen = false
        Task {
            try? await Task.sleep(nanoseconds: UInt64((reduceMotion ? 0.3 : LootTiming.hold(bestRarity)) * 1_000_000_000))
            if reduceMotion { flipped = n; return }
            for i in 0..<n {
                if flipped >= n || opened.id != id { return }
                flipped = i + 1
                if opened.opening.results[i].rarity >= .rare { Haptics.success() } else { Haptics.tap() }
                try? await Task.sleep(nanoseconds: 230_000_000)
            }
            if bestRarity >= .epic { await LootHaptics.flip(bestRarity) }
        }
    }

    private var info: some View {
        VStack(spacing: Theme.Space.m) {
            LootBoxInfoSheet(kind: kind)
            Button { Motion.animate(.easeInOut(duration: 0.2)) { showInfo = false } } label: { Text("Back to the results").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .padding(.horizontal, PopupLayout.inset)
        }
    }

    private var haulPieces: [ArtifactItem] {
        opened.opening.results.compactMap { (r: BoxResult) -> ArtifactItem? in
            if case .artifact(let item) = r.content { return item } else { return nil }
        }
    }

    private var duplicates: [ArtifactItem] { desk.open(session.state.cabinet.duplicates(among: haulPieces)) }

    private var results: some View {
        let haul: BoxHaul = BoxHaul(opened.opening.results)
        let entries: [HaulEntry] = HaulEntry.group(opened.opening.results)
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3)
        let chosen: HaulEntry? = entries.first { $0.id == pick } ?? entries.first { $0.kind == .artifact || $0.kind == .cosmetic } ?? entries.first
        return VStack(spacing: Theme.Space.s) {
            HStack(alignment: .top) {
                Text(summary(haul)).textStyle(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                LootInfoButton { Motion.animate(.easeInOut(duration: 0.2)) { showInfo = true } }.offset(x: 8, y: -10)
            }
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(entries) { (e: HaulEntry) in tile(e, chosen: e.id == chosen?.id) }
            }
            ForEach(opened.opening.completed, id: \.id) { (c: ArtifactCollection) in
                Text("Collection complete: \(c.name). Reward: \(GoldCosmetics.cosmetic(c.rewardID)?.item.title ?? "a cosmetic").")
                    .textStyle(.caption, tint: Theme.gain).multilineTextAlignment(.center)
            }
            if let chosen { panel(chosen) }
            duplicatesRow
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PopupLayout.inset)
        .transition(.opacity)
    }

    @ViewBuilder private var duplicatesRow: some View {
        let dupes: [ArtifactItem] = duplicates
        if !dupes.isEmpty && session.canSellForCash {
            let total: Int = dupes.reduce(0) { $0 + session.quickPrice($1) }
            Button { Task { await desk.sell(dupes) } } label: {
                Text("Sell all duplicates (\(dupes.count)) for \(session.money(total))").lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
            .disabled(desk.busy)
            .accessibilityIdentifier("sell-duplicates")
        }
    }

    private func panel(_ e: HaulEntry) -> some View {
        let tint: Color = e.rarity.tint
        return VStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                icon(e)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).textStyle(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    Text(panelNote(e)).textStyle(.caption, tint: tint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            switch e.kind {
            case .artifact: if let item = e.item { PieceActions(item: item, desk: desk) }
            case .cosmetic: if let c = e.cosmetic { EquipNowButton(id: c.id) }
            case .gold, .cash: EmptyView()
            }
        }
        .padding(Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset))
    }

    private func panelNote(_ e: HaulEntry) -> String {
        switch e.kind {
        case .artifact:
            guard let item = e.item else { return e.line }
            return e.rarity.title + ", " + ArtifactCatalog.label(item) + ". Market " + session.money(AuctionMarket.suggestedStart(e.rarity, priceLevel: session.priceLevel))
        case .cosmetic: return e.rarity.title + " " + e.detail.lowercased() + ". In your wardrobe."
        case .gold: return "Added to your gold."
        case .cash: return "Paid into your personal account."
        }
    }

    private func summary(_ h: BoxHaul) -> String {
        var parts: [String] = []
        if !h.artifacts.isEmpty { parts.append(h.artifacts.count == 1 ? "1 artifact" : "\(h.artifacts.count) artifacts") }
        if !h.cosmetics.isEmpty { parts.append(h.cosmetics.count == 1 ? "1 cosmetic" : "\(h.cosmetics.count) cosmetics") }
        if h.gold > 0 { parts.append(StoreText.gold(h.gold)) }
        let cash: Int = opened.opening.results.filter { if case .money = $0.content { return true } else { return false } }.count
        if cash > 0 { parts.append(cash == 1 ? "1 cash prize" : "\(cash) cash prizes") }
        return parts.joined(separator: ", ") + ". Tap a piece to sell, auction or wear it."
    }

    private func tile(_ e: HaulEntry, chosen: Bool) -> some View {
        let tint: Color = e.rarity.tint
        let fate: PieceFate? = e.item.flatMap { desk.fates[$0.id] }
        return Button { Haptics.choose(); pick = e.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    icon(e)
                    Spacer(minLength: 0)
                    if e.count > 1 { Text("x\(e.count)").textStyle(.headline, tint: tint, numeric: true) }
                }
                Text(e.title).textStyle(.caption, weight: .semibold).lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                Text(fateLine(fate) ?? e.line).textStyle(.caption, tint: fate == nil ? tint : Theme.gain).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(tint.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(chosen ? Theme.ink : tint.opacity(0.7), lineWidth: chosen ? 2 : 1))
            .opacity(fate == nil ? 1 : 0.7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func fateLine(_ fate: PieceFate?) -> String? {
        switch fate {
        case .sold(let price): return "Sold, " + session.money(price)
        case nil: return nil
        }
    }

    @ViewBuilder private func icon(_ e: HaulEntry) -> some View {
        switch e.kind {
        case .cosmetic:
            if let c = e.cosmetic { ItemArt(reward: c.item, rarity: c.rarity, size: 26) } else { Image(systemName: "paintpalette.fill").frame(width: 26, height: 26) }
        case .artifact:
            if let d = e.artifact { ItemArt(artifact: d, size: 26) } else { LedgerGlyph(glyph: Glyph.luxury, size: 22, tint: Theme.ink) }
        case .gold: StoreCoin(size: 24)
        case .cash: Image(systemName: "banknote.fill").font(.system(size: 20)).foregroundStyle(Theme.ink).frame(width: 26, height: 26)
        }
    }

    private func play() async {
        flipped = 0
        haulOpen = false
        if reduceMotion { revealed = true; onRevealed(opened.id); startFlips(); return }
        revealed = false
        showInfo = false
        start = Date()
        let total: Double = LootTiming.buildUp(bestRarity)
        var elapsed: Double = 0
        while elapsed < total {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled || revealed { return }
            elapsed += 0.25
            LootHaptics.buildUp(progress: elapsed / total)
        }
        reveal()
    }

    private func reveal() {
        if revealed { return }
        Motion.animate(.spring(response: 0.5, dampingFraction: 0.8)) { revealed = true }
        onRevealed(opened.id)
        startFlips()
    }

    private var canAgain: Bool {
        if kind.isPaid { return paidBoxesAllowed }
        return BoxPlan(kind: kind, count: 10, stock: session.state.count(kind), gold: session.available).possible
    }

    private var againTitle: String {
        let plan = BoxPlan(kind: kind, count: 10, stock: session.state.count(kind), gold: session.available)
        if plan.toPay == 0 { return "Open 10 more" }
        return kind.isPaid ? "Open 10 more for \(StoreText.gold(plan.cost))" : "No more boxes"
    }

    private func again() {
        guard !working, shown else { return }
        let plan = BoxPlan(kind: kind, count: 10, stock: session.state.count(kind), gold: session.available)
        if plan.needsGold { close(); onShort(); return }
        guard plan.possible else { return }
        working = true
        Task {
            let out = await session.openBoxes(kind, count: 10, paidBoxesAllowed: paidBoxesAllowed)
            working = false
            if let out { onNew(OpenedBox(opening: out)) }
            else if session.problem != nil { close(); onShort() }
        }
    }
}

struct ShortOfGoldCard: View {
    var needed: Int = 0
    var onPacks: () -> Void
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
                    PurchaseButton(item: .goldPack(p.id), minHeight: 36, leave: { close() })
                }
                .padding(Theme.Space.m)
                .background(StoreSurface(tint: Theme.gold, glow: p.id == StorePurchase.bestPack?.id, radius: Theme.Radius.card))
                .storeSheen(radius: Theme.Radius.card, enabled: p.id == StorePurchase.bestPack?.id)
                .accessibilityElement(children: .contain)
            }
            Text("Gold from the Season Pass counts too. You confirm the price before anything is bought.").textStyle(.caption).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .popupFooter {
            PopupFooter(cancel: "Not now", action: "See all packs", onCancel: { close() }, onAction: { onPacks() })
        }
    }

    private func deals(short: Int, first: Bool) -> [GoldPack] {
        var out: [GoldPack] = Array(GoldStore.packs.filter { GoldStore.totalGold($0, firstPurchase: first) >= short }.sorted { $0.priceCents < $1.priceCents }.prefix(2))
        if let best = StorePurchase.bestPack, !out.contains(where: { $0.id == best.id }) { out.append(best) }
        return out
    }
}
