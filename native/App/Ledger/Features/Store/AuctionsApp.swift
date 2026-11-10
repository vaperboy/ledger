import SwiftUI
import Simulation

struct AuctionsApp: View {
    enum Part: Hashable { case live, mine }
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    private let session = StoreSession.shared
    @State private var tab: Part = .live
    @State private var rarity: BoxRarity?
    @State private var listing: ArtifactItem?

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if StoreGate.access(countryCode: online.profile?.countryCode) == .hidden {
                Text("Auctions are not offered where you are.").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity)
            } else {
                cashLine
                SegmentedChoice(items: [Part.live, Part.mine], title: { (t: Part) -> String in t == .live ? "Live auctions" : "My auctions" }, selection: $tab)
                if session.auctions == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if tab == .live {
                    LiveAuctionsList(rarity: $rarity)
                } else {
                    MyAuctionsList()
                }
                Text("Auctions are in cash, from and to your personal account. A sale carries a \(AuctionRules.feePercent)% fee taken from the seller, and that money leaves the economy. A bid in the last two minutes extends the auction by up to two minutes.")
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
        .task {
            await session.load()
            if let id = store.takeAuctionListing(), let item = session.state.cabinet.items.first(where: { (i: ArtifactItem) -> Bool in i.id == id }) { listing = item }
            while !Task.isCancelled {
                await session.refreshAuctions()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
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

    static func priceLine(_ a: Auction) -> String {
        let money: (Int) -> String = StoreSession.shared.money
        return a.bids.isEmpty ? "Starts at \(money(a.startPrice))" : "\(money(a.currentPrice)), \(a.bids.count) \(a.bids.count == 1 ? "bid" : "bids")"
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

struct LiveAuctionsList: View {
    @Binding var rarity: BoxRarity?
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
            OnlineGroup(title: "Ending soonest first", footer: list.isEmpty ? "No auctions match." : "") {
                HStack {
                    Text("Rarity").textStyle(.headline)
                    Spacer()
                    Menu {
                        Button("All") { rarity = nil }
                        ForEach(BoxRarity.allCases, id: \.self) { (r: BoxRarity) in Button(r.title) { rarity = r } }
                    } label: { Text(rarity?.title ?? "All").textStyle(.body, tint: Theme.accent) }
                }
                .frame(minHeight: 48)
                ForEach(Array(list.enumerated()), id: \.element.id) { (_: Int, a: Auction) in
                    Hairline()
                    NavigationLink { AuctionDetailView(auctionID: a.id) } label: { AuctionRow(auction: a, now: now) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

struct MyAuctionsList: View {
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
                    NavigationLink { CabinetView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Sell a piece", note: "Pick an artifact from your cabinet", chevron: true) }
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
                    NavigationLink { AuctionDetailView(auctionID: a.id) } label: { AuctionRow(auction: a, now: now) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

struct AuctionDetailView: View {
    var auctionID: String
    private let session = StoreSession.shared
    @State private var bidding = false
    @State private var pending: PendingAction?

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if let a = session.auctions?.auctions.first(where: { $0.id == auctionID }) {
                TimelineView(.periodic(from: .now, by: 1)) { (context: TimelineViewDefaultContext) in
                    content(a, now: context.date.timeIntervalSince1970)
                }
            } else {
                Text("This auction is no longer listed.").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity)
            }
        }
        .appScreen(title: "Auction", subtitle: "")
        .confirmAction($pending)
        .centerSheet(isPresented: $bidding, title: "Place a bid") { BidCard(auctionID: auctionID) }
    }

    @ViewBuilder private func content(_ a: Auction, now: Double) -> some View {
        let def: ArtifactDef? = ArtifactCatalog.def(a.item.defID)
        let live: Bool = a.isLive(at: now)
        VStack(spacing: Theme.Space.l) {
            OnlineGroup(title: "Piece", footer: def?.note ?? "") {
                ArtifactRow(item: a.item)
                Hairline()
                OnlineLine(glyph: Glyph.luxury, title: ArtifactCatalog.collection(def?.collection ?? "")?.name ?? CardCatalog.def(a.item.defID)?.kind.title ?? "Collection", note: "Seller: \(name(a.seller))")
            }
            OnlineGroup(title: "Price", footer: "") {
                OnlineLine(glyph: Glyph.market, title: a.bids.isEmpty ? "Start price" : "Current bid", value: session.money(a.currentPrice))
                if let b = a.buyNow {
                    Hairline()
                    OnlineLine(glyph: Glyph.market, title: "Buy now", value: a.canBuyNow(at: now) ? session.money(b) : "Gone")
                }
                Hairline()
                OnlineLine(glyph: Glyph.person, title: "Leading", value: a.leader.map { name($0) } ?? "No bids yet")
                Hairline()
                OnlineLine(glyph: Glyph.goals, title: live ? "Time left" : "Status", value: live ? StoreText.timeLeft(a.endsAt - now) : statusText(a))
                Hairline()
                OnlineLine(glyph: Glyph.check, title: "Reserve", value: a.reserve == nil ? "None" : (a.reserveMet ? "Met" : "Not met"))
                if a.extensions > 0 {
                    Hairline()
                    Text("Extended \(a.extensions) \(a.extensions == 1 ? "time" : "times") by late bids.").textStyle(.caption).padding(.vertical, Theme.Space.s)
                }
            }
            actions(a, live: live, now: now)
            history(a)
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

    @ViewBuilder private func actions(_ a: Auction, live: Bool, now: Double) -> some View {
        let access: StoreAccess.Access = StoreGate.access(countryCode: nil)
        OnlineGroup(title: "", footer: footer(a, live: live)) {
            VStack(spacing: Theme.Space.s) {
                if !live {
                    Text("This auction has ended.").textStyle(.body, tint: Theme.inkSoft)
                } else if a.seller == GoldVault.meID {
                    Button("Take it off sale") { askCancel(a) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true)).disabled(!a.bids.isEmpty)
                } else if a.leader == GoldVault.meID {
                    Text("You lead. \(session.money(a.currentPrice)) is set aside and is free again if you are outbid.").textStyle(.body, tint: Theme.gain)
                } else {
                    Button { bidding = true } label: { Text("Place a bid").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true)).disabled(access == .hidden)
                        .accessibilityIdentifier("auction-bid")
                    if a.canBuyNow(at: now), let price = a.buyNow {
                        Button { askBuyNow(a, price: price) } label: { Text("Buy now for \(session.money(price))").frame(maxWidth: .infinity) }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true)).disabled(access == .hidden)
                            .accessibilityIdentifier("auction-buy-now")
                    }
                }
            }
            .padding(.vertical, Theme.Space.m)
        }
    }

    private func footer(_ a: Auction, live: Bool) -> String {
        if a.seller == GoldVault.meID && live { return a.bids.isEmpty ? "Nobody has bid, so you can still take it back." : "It has bids, so it runs to the end. The sale fee is \(AuctionRules.feePercent)%." }
        return live ? "Next bid at least \(session.money(AuctionRules.minimumBid(a))). Sales carry a \(AuctionRules.feePercent)% fee for the seller." : ""
    }

    private func history(_ a: Auction) -> some View {
        let bids: [AuctionBid] = Array(a.bids.suffix(6).reversed())
        return Group {
            if !bids.isEmpty {
                OnlineGroup(title: "Recent bids", footer: "") {
                    ForEach(Array(bids.enumerated()), id: \.offset) { (i: Int, b: AuctionBid) in
                        if i > 0 { Hairline() }
                        HStack {
                            Text(name(b.bidder)).textStyle(.body)
                            Spacer()
                            Text(session.money(b.amount)).textStyle(.body, tint: Theme.inkSoft, numeric: true)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private func name(_ id: String) -> String { session.name(of: id) }

    private func askBuyNow(_ a: Auction, price: Int) {
        pending = PendingAction(title: "Buy it now?", message: "If you buy this, \(session.money(price)) leaves your personal account at once and the piece joins your Cabinet. The auction ends.",
                                button: "Buy for \(session.money(price))", alwaysAsk: true, tone: .investment, icon: "bag") {
            Task { if await session.buyNow(a.id) { Haptics.success() } }
        }
    }

    private func askCancel(_ a: Auction) {
        pending = PendingAction(title: "Take it off sale?", message: "The piece goes back into your cabinet. Nothing is charged.", button: "Take it back", alwaysAsk: true, tone: .info, icon: "arrow.uturn.backward") {
            Task { _ = await session.cancel(a.id) }
        }
    }
}

struct BidCard: View {
    var auctionID: String
    private let session = StoreSession.shared
    @State private var amount = 0
    @State private var seeded = false
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        if let a = session.auctions?.auctions.first(where: { $0.id == auctionID }) {
            let now: Double = Date().timeIntervalSince1970
            let p = AuctionRules.preview(a, amount: amount, bidder: GoldVault.meID, cash: session.cash, held: session.heldCash, now: now)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    stepButton("minus") { amount = max(AuctionRules.minimumBid(a), amount - AuctionRules.increment(at: max(1, amount))) }
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.center)
                        .textStyle(.figure, numeric: true).frame(minHeight: 48)
                        .accessibilityIdentifier("bid-amount")
                    stepButton("plus") { amount += AuctionRules.increment(at: max(1, amount)) }
                }
                Text("Your bid: \(session.money(max(0, amount))). Lowest bid now: \(session.money(p.minimum))").textStyle(.caption).frame(maxWidth: .infinity)
                Hairline()
                line("Set aside while you lead", session.money(p.heldAfter))
                line("Cash still free", session.money(p.availableAfter))
                Text("Nothing leaves your account yet. If someone outbids you, the cash is free again at once. If you win, the bid is paid from your personal account and the piece joins your Cabinet.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                if p.extendsAuction { Text("This bid is in the last two minutes, so the auction is extended to give others time to answer.").textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
                if a.reserve != nil { Text(p.reserveMetAfter ? "This bid meets the reserve." : "This bid does not meet the reserve yet; if the reserve is not met the piece is not sold and you pay nothing.").textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
                if let why = p.problem { Text(p.shortBy > 0 ? "\(why) You are \(session.money(p.shortBy)) short." : why).textStyle(.body, tint: Theme.loss) }
                else if let why = session.problem { Text(why).textStyle(.body, tint: Theme.loss) }
            }
            .onAppear { if !seeded { amount = AuctionRules.minimumBid(a); seeded = true } }
            .popupFooter {
                PopupFooter(cancel: "Cancel", action: "Bid \(session.money(max(0, amount)))", onCancel: { close() }, onAction: {
                    Task { if await session.bid(a.id, amount: amount) { Haptics.success(); close() } }
                }, actionEnabled: p.allowed)
            }
        } else {
            Text("This auction is no longer listed.").textStyle(.body)
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack { Text(title).textStyle(.body); Spacer(); Text(value).textStyle(.body, numeric: true) }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: symbol).frame(width: 44, height: 44).background(Circle().fill(Theme.inset))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Raise the bid" : "Lower the bid")
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

    var body: some View {
        let preview = AuctionRules.listingPreview(startPrice: startPrice, reserve: useReserve ? reserve : nil, buyNow: useBuyNow ? buyNow : nil, duration: duration)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ArtifactRow(item: item)
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
                let base: Int = AuctionMarket.suggestedStart(ArtifactCatalog.def(item.defID)?.rarity ?? .common, priceLevel: session.priceLevel)
                startPrice = base; reserve = base * 2; buyNow = base * 3; seeded = true
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
        }
    }
}
