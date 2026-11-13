import SwiftUI
import Simulation

struct OpenAuction: Identifiable, Equatable { var id: String }

struct AuctionsApp: View {
    enum Part: Hashable { case live, mine }
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    private let session = StoreSession.shared
    @State private var tab: Part = .live
    @State private var rarity: BoxRarity?
    @State private var listing: ArtifactItem?
    @State private var opened: OpenAuction?

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if StoreGate.access(countryCode: online.profile?.countryCode) == .hidden {
                Text("Auctions are not offered where you are.").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity)
            } else {
                cashLine
                SegmentedChoice(items: [Part.live, Part.mine], title: { (t: Part) -> String in t == .live ? "Live" : "Mine" }, selection: $tab)
                if session.auctions == nil {
                    OnlineWaiting { Task { await session.refreshAuctions() } }
                } else if tab == .live {
                    LiveAuctionsList(rarity: $rarity, opened: $opened)
                } else {
                    MyAuctionsList(opened: $opened)
                }
                Text("Cash only, from and to your personal account. A sale carries a \(AuctionRules.feePercent)% fee from the seller. A bid in the last two minutes adds \(Int(AuctionRules.bidExtension)) seconds.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
            }
        }
        .appScreen(title: "Auctions", subtitle: "Artifacts and cards, bought and sold for cash")
        .centerSheet(item: $listing, title: "Put it up for auction") { (item: ArtifactItem) in
            ListingCard(item: item) { (listed: Bool) in
                if listed { tab = .mine }
                listing = nil
            }
        }
        .centerSheet(item: $opened, title: "") { (o: OpenAuction) in AuctionPopup(auctionID: o.id, onDone: { opened = nil }) }
        .task {
            await session.load()
            if let id = store.takeAuctionListing(), let item = session.state.cabinet.items.first(where: { (i: ArtifactItem) -> Bool in i.id == id }) { listing = item }
            while !Task.isCancelled {
                await session.refreshAuctions()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var cashLine: some View {
        HStack {
            Text("Cash available").textStyle(.caption)
            Text(session.money(session.spendableCash)).textStyle(.headline, numeric: true)
            Spacer()
            if session.heldCash > 0 { Text("\(session.money(session.heldCash)) set aside").textStyle(.caption) }
        }
        .padding(.horizontal, Theme.Space.m)
    }
}

@MainActor private enum AuctionLook {
    static func stance(_ a: Auction) -> String? {
        if a.seller == GoldVault.meID { return "Yours" }
        if a.leader == GoldVault.meID { return a.status == .live ? "You lead" : (a.status == .sold ? "You won" : "Returned") }
        if a.bids.contains(where: { $0.bidder == GoldVault.meID }) { return a.status == .live ? "Outbid" : "Lost" }
        return nil
    }

    static func stanceTint(_ s: String) -> Color { s == "You lead" || s == "You won" ? Theme.gain : (s == "Outbid" || s == "Lost" ? Theme.loss : Theme.inkSoft) }

    static func ago(_ seconds: Double) -> String {
        let s: Int = Int(max(0, seconds))
        if s < 60 { return "now" }
        if s < 3_600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3_600)h ago" }
        return "\(s / 86_400)d ago"
    }

    static func raise(_ a: Auction) -> String? {
        guard let last = a.bids.last else { return nil }
        let before: Int = a.bids.count > 1 ? a.bids[a.bids.count - 2].amount : a.startPrice
        let diff: Int = last.amount - before
        guard diff > 0, before > 0 else { return nil }
        return "+\(StoreSession.shared.money(diff)) (\(String(format: "%.1f", Double(diff) / Double(before) * 100))%)"
    }

    static func priceLine(_ a: Auction) -> String {
        let money: (Int) -> String = StoreSession.shared.money
        return a.bids.isEmpty ? "Starts at \(money(a.startPrice))" : "\(money(a.currentPrice)), \(a.bids.count) \(a.bids.count == 1 ? "bid" : "bids")"
    }
}

struct AuctionArt: View {
    var item: ArtifactItem
    var size: CGFloat

    var body: some View {
        if let card = CardCatalog.def(forItem: item.id) { CardThumb(def: card, width: size * 1.3) }
        else if let def = ArtifactCatalog.def(item.defID) { ItemArt(artifact: def, size: size) }
        else { RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset).frame(width: size, height: size) }
    }
}

struct AuctionHero: View {
    var item: ArtifactItem
    var height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        GeometryReader { (g: GeometryProxy) in
            ZStack {
                Theme.inset
                if let card = CardCatalog.def(forItem: item.id) {
                    CardThumb(def: card, width: min(g.size.width * 0.82, height * 0.9 / 0.62))
                } else {
                    AuctionArt(item: item, size: height * 0.88)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .frame(height: height)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

struct AuctionRow: View {
    var auction: Auction
    var now: Double

    var body: some View {
        let stance: String? = AuctionLook.stance(auction)
        VStack(alignment: .leading, spacing: 2) {
            ArtifactRow(item: auction.item, trailing: auction.status == .live ? StoreText.timeLeft(auction.endsAt - now) : "")
            HStack(spacing: Theme.Space.s) {
                Text(AuctionLook.priceLine(auction)).textStyle(.caption, numeric: true)
                if auction.reserve != nil { Text(auction.reserveMet ? "Reserve met" : "Reserve not met").textStyle(.caption) }
                if auction.canBuyNow(at: now) { Text("Buy now").textStyle(.caption, tint: Theme.accent) }
                Spacer()
                if let s = stance { Text(s).textStyle(.caption, tint: AuctionLook.stanceTint(s), weight: .semibold) }
            }
            .padding(.bottom, Theme.Space.s)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AuctionTile: View {
    var auction: Auction
    var now: Double

    var body: some View {
        let def: ArtifactDef? = ArtifactCatalog.def(auction.item.defID)
        let card: CardDef? = CardCatalog.def(forItem: auction.item.id)
        let left: Double = auction.endsAt - now
        let stance: String? = AuctionLook.stance(auction)
        let money: (Int) -> String = StoreSession.shared.money
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            AuctionHero(item: auction.item, height: 230)
                .overlay(alignment: .topLeading) {
                    if left > 0 { ListingPill(text: "LIVE", dot: Theme.loss).padding(Theme.Space.s) }
                }
                .overlay(alignment: .topTrailing) {
                    ListingPill(text: StoreText.timeLeft(left), glyph: Glyph.clock).padding(Theme.Space.s)
                }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    Text(card?.name ?? def?.name ?? "Artifact").textStyle(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    if let r = def?.rarity ?? card?.rarity { RarityTag(rarity: r) }
                    Spacer(minLength: 0)
                    if let s = stance { Text(s).textStyle(.caption, tint: AuctionLook.stanceTint(s), weight: .semibold) }
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auction.bids.isEmpty ? "Starting bid" : "Current bid").textStyle(.caption)
                        Text(money(auction.currentPrice)).textStyle(.title, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Text(auction.bids.count == 1 ? "1 bid" : "\(auction.bids.count) bids").textStyle(.caption)
                }
            }
            .padding(.horizontal, Theme.Space.xs).padding(.bottom, Theme.Space.xs)
        }
        .padding(Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct LiveAuctionsList: View {
    @Binding var rarity: BoxRarity?
    @Binding var opened: OpenAuction?
    private let session = StoreSession.shared

    private func shown(_ a: Auction, now: Double) -> Bool {
        guard a.status == .live, a.endsAt > now, a.seller != GoldVault.meID else { return false }
        guard let wanted = rarity else { return true }
        return ArtifactCatalog.def(a.item.defID)?.rarity == wanted
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { (context: TimelineViewDefaultContext) in
            let now: Double = context.date.timeIntervalSince1970
            let list: [Auction] = (session.auctions?.auctions ?? []).filter { (a: Auction) -> Bool in shown(a, now: now) }.sorted { $0.endsAt < $1.endsAt }
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack {
                    Text(list.count == 1 ? "1 live, ending soonest first" : "\(list.count) live, ending soonest first").textStyle(.label, tint: Theme.inkFaint)
                    Spacer()
                    Menu {
                        Button("All") { rarity = nil }
                        ForEach(BoxRarity.allCases, id: \.self) { (r: BoxRarity) in Button(r.title) { rarity = r } }
                    } label: { Text(rarity?.title ?? "All rarities").textStyle(.body, tint: Theme.accent).frame(minHeight: 44) }
                }
                if list.isEmpty {
                    Text(rarity == nil ? "No auctions are running right now. Check back soon." : "No auctions match this rarity.").textStyle(.body, tint: Theme.inkSoft).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: Theme.Space.l) {
                        ForEach(list) { (a: Auction) in
                            Button { Haptics.tap(); opened = OpenAuction(id: a.id) } label: { AuctionTile(auction: a, now: now) }
                                .buttonStyle(PressableStyle())
                                .accessibilityIdentifier("auction-" + a.id)
                        }
                    }
                }
            }
        }
    }
}

struct MyAuctionsList: View {
    @Binding var opened: OpenAuction?
    private let session = StoreSession.shared

    private func iBid(_ a: Auction) -> Bool { a.bids.contains { (b: AuctionBid) -> Bool in b.bidder == GoldVault.meID } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { (context: TimelineViewDefaultContext) in
            let now: Double = context.date.timeIntervalSince1970
            let all: [Auction] = session.auctions?.auctions ?? []
            let me: String = GoldVault.meID
            let leading: [Auction] = all.filter { $0.status == .live && $0.leader == me }
            let outbid: [Auction] = all.filter { (a: Auction) -> Bool in a.status == .live && a.leader != me && a.seller != me && iBid(a) }
            let selling: [Auction] = all.filter { $0.status == .live && $0.seller == me }
            let ended: [Auction] = all.filter { (a: Auction) -> Bool in a.status != .live && (a.seller == me || iBid(a)) }.sorted { $0.endsAt > $1.endsAt }
            VStack(spacing: Theme.Space.l) {
                if !session.notes.isEmpty { notes }
                group("You lead", "The cash for your bid is set aside until the auction ends or someone outbids you.", leading, now)
                group("Outbid", "The cash you had set aside is free again.", outbid, now)
                group("You are selling", "A piece comes off sale if nobody bids and you cancel; with bids it runs to the end.", selling, now)
                group("Ended", "", ended, now)
                if leading.isEmpty && outbid.isEmpty && selling.isEmpty && ended.isEmpty {
                    Text("You have no bids or listings yet.").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity)
                }
                OnlineGroup(title: "", footer: "") {
                    NavigationLink { CabinetView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Sell a piece", note: "Pick one from your artifacts", chevron: true) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var notes: some View {
        OnlineGroup(title: "Recently", footer: "") {
            ForEach(Array(session.notes.suffix(6).enumerated()), id: \.offset) { (i: Int, n: String) in
                if i > 0 { Hairline() }
                Text(n).textStyle(.body).fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.Space.s).frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            Button("Clear") { session.clearNotes() }.buttonStyle(TertiaryButtonStyle()).frame(minHeight: 44)
        }
    }

    @ViewBuilder private func group(_ title: String, _ footer: String, _ list: [Auction], _ now: Double) -> some View {
        if !list.isEmpty {
            OnlineGroup(title: title, footer: footer) {
                ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, a: Auction) in
                    if i > 0 { Hairline() }
                    Button { Haptics.tap(); opened = OpenAuction(id: a.id) } label: { AuctionRow(auction: a, now: now) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

struct AuctionPopup: View {
    var auctionID: String
    var onDone: () -> Void
    private let session = StoreSession.shared
    @State private var amount = 0
    @State private var seeded = false
    @State private var pending: PendingAction?

    var body: some View {
        let auction: Auction? = session.auctions?.auctions.first(where: { (a: Auction) -> Bool in a.id == auctionID })
        Group {
            if let a = auction {
                TimelineView(.periodic(from: .now, by: 1)) { (context: TimelineViewDefaultContext) in
                    page(a, now: context.date.timeIntervalSince1970)
                }
            } else {
                Text("This auction is no longer listed.").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity)
            }
        }
        .confirmAction($pending)
        .popupFooter { footer(auction) }
    }

    @ViewBuilder private func page(_ a: Auction, now: Double) -> some View {
        let def: ArtifactDef? = ArtifactCatalog.def(a.item.defID)
        let card: CardDef? = CardCatalog.def(forItem: a.item.id)
        let live: Bool = a.isLive(at: now)
        let title: String = card?.name ?? def?.name ?? "Artifact"
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ListingHero(height: 240, location: a.seller == GoldVault.meID ? "Your listing" : name(a.seller), locationGlyph: Glyph.gavel, counter: "1/1",
                        shareText: "\(title), \(a.bids.isEmpty ? "starts at" : "current bid") \(session.money(a.currentPrice))") {
                AuctionHero(item: a.item, height: 240)
            } badge: {
                if live { ListingPill(text: "LIVE", dot: Theme.loss) } else { ListingPill(text: "ENDED") }
            }
            HStack(spacing: Theme.Space.s) {
                Text(title).textStyle(.title).lineLimit(2)
                if let r = def?.rarity ?? card?.rarity {
                    RarityTag(rarity: r).padding(.horizontal, Theme.Space.s).padding(.vertical, 4).background(Capsule().fill(Theme.inset))
                }
                Spacer(minLength: 0)
            }
            if let note = def?.note, !note.isEmpty { Text(note).textStyle(.body, tint: Theme.inkSoft).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            ListingStats {
                Text(a.bids.isEmpty ? "Start price" : "Current bid").textStyle(.caption)
                Text(session.money(a.currentPrice)).textStyle(.title, numeric: true).lineLimit(1).minimumScaleFactor(0.6)
                if let up = AuctionLook.raise(a) { Text(up).textStyle(.caption, tint: Theme.gain, numeric: true) }
            } right: {
                Text(live ? "Time left" : "Status").textStyle(.caption)
                if live { ListingCountdown(seconds: a.endsAt - now) } else { Text(statusText(a)).textStyle(.headline) }
            }
            if a.reserve != nil || a.buyNow != nil {
                HStack(spacing: Theme.Space.m) {
                    if a.reserve != nil { Text(a.reserveMet ? "Reserve met" : "Reserve not met").textStyle(.caption) }
                    if let b = a.buyNow { Text("Buy now " + (a.canBuyNow(at: now) ? session.money(b) : "gone")).textStyle(.caption) }
                }
            }
            bids(a, now: now)
            ListingPanel {
                HStack(spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: Glyph.gavel, size: Theme.Icon.medium, tint: Theme.inkSoft)
                    Text("Starting price").textStyle(.body, tint: Theme.inkSoft)
                    Spacer(minLength: Theme.Space.s)
                    Text(session.money(a.startPrice)).textStyle(.headline, numeric: true)
                }
            }
            if live { bidControls(a, now: now) }
        }
    }

    private func bids(_ a: Auction, now: Double) -> some View {
        let list: [AuctionBid] = Array(a.bids.suffix(5).reversed())
        let bidders: Int = Set(a.bids.map { (b: AuctionBid) -> String in b.bidder }).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(list.isEmpty ? "No bids yet" : "Bidders").textStyle(.headline)
                Spacer()
                if !list.isEmpty { Text("\(bidders)").textStyle(.headline, numeric: true) }
            }
            .padding(.bottom, Theme.Space.xs)
            ForEach(Array(list.enumerated()), id: \.offset) { (i: Int, b: AuctionBid) in
                Hairline()
                let me: Bool = b.bidder == GoldVault.meID
                HStack(spacing: Theme.Space.m) {
                    PlayerAvatar(name: me ? "You" : name(b.bidder), isYou: me, size: 36)
                    Text(me ? "You" : name(b.bidder)).textStyle(.body, weight: i == 0 ? .semibold : .regular).lineLimit(1)
                    if i == 0 { LedgerGlyph(glyph: Glyph.crown, size: Theme.Icon.small, tint: Theme.accent) }
                    Spacer(minLength: Theme.Space.s)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(session.money(b.amount)).textStyle(.body, numeric: true, weight: .semibold)
                        HStack(spacing: Theme.Space.xxs) {
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.gain)
                            Text(AuctionLook.ago(now - b.at)).textStyle(.caption)
                        }
                    }
                }
                .frame(minHeight: 52)
            }
        }
        .animation(.default, value: a.bids.count)
    }

    @ViewBuilder private func bidControls(_ a: Auction, now: Double) -> some View {
        if a.seller == GoldVault.meID {
            Text(a.bids.isEmpty ? "Nobody has bid, so you can still take it back." : "It has bids, so it runs to the end.").textStyle(.caption)
        } else if a.leader == GoldVault.meID {
            Text("You lead. \(session.money(a.currentPrice)) is set aside and is free again if you are outbid.").textStyle(.body, tint: Theme.gain)
        } else {
            let p = AuctionRules.preview(a, amount: amount, bidder: GoldVault.meID, cash: session.cash, held: session.heldCash, now: now)
            HStack(spacing: Theme.Space.m) {
                stepButton("minus") { amount = max(AuctionRules.minimumBid(a), amount - AuctionRules.increment(at: max(1, amount))) }
                TextField("Amount", value: $amount, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .textStyle(.figure, numeric: true).frame(minHeight: 48)
                    .accessibilityIdentifier("bid-amount")
                stepButton("plus") { amount += AuctionRules.increment(at: max(1, amount)) }
            }
            .onAppear { if !seeded { amount = AuctionRules.minimumBid(a); seeded = true } }
            .onChange(of: a.currentPrice) { _, _ in amount = max(amount, AuctionRules.minimumBid(a)) }
            Text("Lowest bid now: \(session.money(p.minimum)). Cash free after: \(session.money(p.availableAfter)).").textStyle(.caption)
            if p.extendsAuction { Text("A bid now adds \(Int(AuctionRules.bidExtension)) seconds.").textStyle(.caption) }
            if let why = p.problem { Text(p.shortBy > 0 ? "\(why) You are \(session.money(p.shortBy)) short." : why).textStyle(.body, tint: Theme.loss) }
            else if let why = session.problem { Text(why).textStyle(.body, tint: Theme.loss) }
        }
    }

    @ViewBuilder private func footer(_ auction: Auction?) -> some View {
        if let a = auction, a.isLive(at: Date().timeIntervalSince1970) {
            let access: StoreAccess.Access = StoreGate.access(countryCode: nil)
            if a.seller == GoldVault.meID {
                PopupFooter(cancel: "Close", action: "Take it off sale", onCancel: { onDone() }, onAction: { askCancel(a) }, actionEnabled: a.bids.isEmpty)
            } else if a.leader == GoldVault.meID {
                PopupFooter(cancel: "Close", action: "You lead", onCancel: { onDone() }, onAction: {}, actionEnabled: false)
            } else {
                let p = AuctionRules.preview(a, amount: amount, bidder: GoldVault.meID, cash: session.cash, held: session.heldCash, now: Date().timeIntervalSince1970)
                PopupFooter(cancel: a.canBuyNow(at: Date().timeIntervalSince1970) ? "Buy now" : "Close", action: "Bid \(session.money(max(0, amount)))", onCancel: {
                    if a.canBuyNow(at: Date().timeIntervalSince1970), let price = a.buyNow { askBuyNow(a, price: price) } else { onDone() }
                }, onAction: {
                    Task { if await session.bid(a.id, amount: amount) { Haptics.success() } }
                }, actionEnabled: p.allowed && access != .hidden)
            }
        } else {
            PopupFooter(cancel: "Close", action: "Done", onCancel: { onDone() }, onAction: { onDone() })
        }
    }

    private func statusText(_ a: Auction) -> String {
        switch a.status {
        case .sold: return "Sold for \(session.money(a.soldFor ?? a.currentPrice))"
        case .unsold: return a.bids.isEmpty ? "Ended, no bids" : "Ended, reserve not met"
        case .cancelled: return "Taken off sale"
        case .live: return "Ended"
        }
    }

    private func name(_ id: String) -> String { session.name(of: id) }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: symbol).frame(width: 44, height: 44).background(Circle().fill(Theme.inset))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Raise the bid" : "Lower the bid")
    }

    private func askBuyNow(_ a: Auction, price: Int) {
        pending = PendingAction(title: "Buy it now?", message: "If you buy this, \(session.money(price)) leaves your personal account at once and the piece joins your storage. The auction ends.",
                                button: "Buy for \(session.money(price))", alwaysAsk: true, tone: .investment, icon: "bag") {
            Task { if await session.buyNow(a.id) { Haptics.success() } }
        }
    }

    private func askCancel(_ a: Auction) {
        pending = PendingAction(title: "Take it off sale?", message: "The piece goes back into your storage. Nothing is charged.", button: "Take it back", alwaysAsk: true, tone: .info, icon: "arrow.uturn.backward") {
            Task { _ = await session.cancel(a.id); onDone() }
        }
    }
}

struct ListingCard: View {
    var item: ArtifactItem
    var onFinish: ((Bool) -> Void)? = nil
    private let session = StoreSession.shared
    @State private var startPrice = 0
    @State private var useReserve = false
    @State private var reserve = 0
    @State private var useBuyNow = false
    @State private var buyNow = 0
    @State private var duration: AuctionDuration = .sixHours
    @State private var seeded = false
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func finish(_ listed: Bool) {
        if let onFinish { onFinish(listed) } else if let c = popupClose { c() } else { systemDismiss() }
    }

    /// Market value of the piece; every asking price is capped at three times this.
    private var marketValue: Int { AuctionMarket.value(of: item, priceLevel: session.priceLevel) }
    private var maxAsk: Int { AuctionRules.maxAsk(value: marketValue) }

    var body: some View {
        let preview = AuctionRules.listingPreview(startPrice: startPrice, reserve: useReserve ? reserve : nil, buyNow: useBuyNow ? buyNow : nil, duration: duration, value: marketValue)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ArtifactRow(item: item)
            Text("Market value \(session.money(marketValue)). The most you can ask is \(session.money(maxAsk)).").textStyle(.caption)
            field("Start price", $startPrice, id: "list-start")
            Toggle("Set a reserve", isOn: $useReserve)
            if useReserve { field("Reserve", $reserve, id: "list-reserve") }
            Toggle("Set a buy-now price", isOn: $useBuyNow)
            if useBuyNow { field("Buy now", $buyNow, id: "list-buynow") }
            Text("Length").textStyle(.caption)
            SegmentedChoice(items: AuctionDuration.allCases, title: { (d: AuctionDuration) -> String in d.title }, selection: $duration)
            Hairline()
            Text(proceeds(preview)).textStyle(.caption, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { (_: Int, line: String) in
                Text(line).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let problem = preview.problem { Text(problem).textStyle(.body, tint: Theme.loss) }
            else if let why = session.problem { Text(why).textStyle(.body, tint: Theme.loss) }
        }
        .onAppear {
            if !seeded {
                let base: Int = marketValue
                startPrice = base; reserve = base * 2; buyNow = min(base * 3, maxAsk); seeded = true
            }
        }
        .popupFooter {
            PopupFooter(cancel: "Cancel", action: "Put it up for \(duration.title)", onCancel: { finish(false) }, onAction: {
                Task {
                    if await session.list(itemID: item.id, startPrice: startPrice, reserve: useReserve ? reserve : nil, buyNow: useBuyNow ? buyNow : nil, duration: duration) {
                        Haptics.success(); finish(true)
                    }
                }
            }, actionEnabled: preview.problem == nil)
        }
    }

    private func proceeds(_ p: AuctionRules.ListingPreview) -> String {
        var text: String = "You are paid in cash into your personal account. At your start price you would receive \(session.money(p.proceedsAtStart))"
        if let r = p.proceedsAtReserve { text += ", at your reserve \(session.money(r))" }
        if let b = p.proceedsAtBuyNow { text += ", at the buy-now price \(session.money(b))" }
        return text + ", after the fee."
    }

    private func field(_ title: String, _ value: Binding<Int>, id: String) -> some View {
        HStack {
            Text(title).textStyle(.body)
            Spacer()
            TextField("0", value: value, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .textStyle(.headline, numeric: true).frame(width: 130).frame(minHeight: 44)
                .accessibilityIdentifier(id)
                .onChange(of: value.wrappedValue) { (_: Int, new: Int) in
                    if new > maxAsk { value.wrappedValue = maxAsk }
                }
        }
    }
}
