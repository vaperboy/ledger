import SwiftUI
import Simulation

/// Artifact auctions: the live list, and the player's own bids and listings. Bids are held in gold while they lead and returned when beaten.
/// Times are shown as plain text; nothing flashes or counts down loudly.
struct AuctionsApp: View {
    enum Part: Hashable { case live, mine }
    private let session = StoreSession.shared
    @State private var tab: Part = .live
    @State private var rarity: BoxRarity?

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            goldLine
            SegmentedChoice(items: [Part.live, Part.mine], title: { (t: Part) -> String in t == .live ? "Live auctions" : "My auctions" }, selection: $tab)
            if session.auctions == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if tab == .live {
                LiveAuctionsList(rarity: $rarity)
            } else {
                MyAuctionsList()
            }
            Text("Gold moves between players only here. A sale carries a \(AuctionRules.feePercent)% fee taken from the seller, and that gold leaves the economy. A bid in the last two minutes extends the auction by up to two minutes.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
        }
        .appScreen(title: "Auctions", subtitle: "Artifacts, bid in gold")
        .task {
            await session.load()
            while !Task.isCancelled {
                await session.refreshAuctions()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private var goldLine: some View {
        HStack {
            Text("Available").textStyle(.caption)
            GoldAmount(amount: session.available)
            Spacer()
            if session.state.wallet.held > 0 { Text("\(StoreText.gold(session.state.wallet.held)) held").textStyle(.caption) }
        }
        .padding(.horizontal, Theme.Space.m)
    }
}

// MARK: Rows

private enum AuctionLook {
    /// Whether the player has bid here, and whether they lead.
    static func stance(_ a: Auction) -> String? {
        if a.seller == GoldVault.meID { return "Yours" }
        if a.leader == GoldVault.meID { return a.status == .live ? "You lead" : (a.status == .sold ? "You won" : "Returned") }
        if a.bids.contains(where: { $0.bidder == GoldVault.meID }) { return a.status == .live ? "Outbid" : "Lost" }
        return nil
    }

    static func stanceTint(_ s: String) -> Color { s == "You lead" || s == "You won" ? Theme.gain : (s == "Outbid" || s == "Lost" ? Theme.loss : Theme.inkSoft) }

    static func priceLine(_ a: Auction) -> String {
        a.bids.isEmpty ? "Starts at \(StoreText.gold(a.startPrice))" : "\(StoreText.gold(a.currentPrice)), \(a.bids.count) \(a.bids.count == 1 ? "bid" : "bids")"
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

    /// Live, not the player's own, and of the chosen rarity.
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
                group("You lead", "Your bid is held in gold until the auction ends or someone outbids you.", leading, now)
                group("Outbid", "The gold you held came back to you.", outbid, now)
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

// MARK: Detail

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
                OnlineLine(glyph: Glyph.luxury, title: ArtifactCatalog.collection(def?.collection ?? "")?.name ?? "Collection", note: "Seller: \(name(a.seller))")
            }
            OnlineGroup(title: "Price", footer: "") {
                OnlineLine(glyph: Glyph.market, title: a.bids.isEmpty ? "Start price" : "Current bid", value: StoreText.gold(a.currentPrice))
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
            actions(a, live: live)
            history(a)
        }
    }

    private func statusText(_ a: Auction) -> String {
        switch a.status {
        case .sold: return "Sold for \(StoreText.gold(a.soldFor ?? a.currentPrice))"
        case .unsold: return a.bids.isEmpty ? "Ended, no bids" : "Ended, reserve not met"
        case .cancelled: return "Taken off sale"
        case .live: return "Ended"
        }
    }

    @ViewBuilder private func actions(_ a: Auction, live: Bool) -> some View {
        let access: StoreAccess.Access = StoreGate.access(countryCode: nil)
        OnlineGroup(title: "", footer: footer(a, live: live)) {
            VStack(spacing: Theme.Space.s) {
                if !live {
                    Text("This auction has ended.").textStyle(.body, tint: Theme.inkSoft)
                } else if a.seller == GoldVault.meID {
                    Button("Take it off sale") { askCancel(a) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true)).disabled(!a.bids.isEmpty)
                } else if a.leader == GoldVault.meID {
                    Text("You lead. \(StoreText.gold(a.currentPrice)) is held and comes back if you are outbid.").textStyle(.body, tint: Theme.gain)
                } else {
                    Button { bidding = true } label: { Text("Place a bid").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true)).disabled(access == .hidden)
                        .accessibilityIdentifier("auction-bid")
                }
            }
            .padding(.vertical, Theme.Space.m)
        }
    }

    private func footer(_ a: Auction, live: Bool) -> String {
        if a.seller == GoldVault.meID && live { return a.bids.isEmpty ? "Nobody has bid, so you can still take it back." : "It has bids, so it runs to the end. The sale fee is \(AuctionRules.feePercent)%." }
        return live ? "Next bid at least \(StoreText.gold(AuctionRules.minimumBid(a))). Sales carry a \(AuctionRules.feePercent)% fee for the seller." : ""
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
                            Text(StoreText.gold(b.amount)).textStyle(.body, tint: Theme.inkSoft, numeric: true)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private func name(_ id: String) -> String { session.name(of: id) }

    private func askCancel(_ a: Auction) {
        pending = PendingAction(title: "Take it off sale?", message: "The piece goes back into your cabinet. Nothing is charged.", button: "Take it back", alwaysAsk: true, tone: .info, icon: "arrow.uturn.backward") {
            Task { _ = await session.cancel(a.id) }
        }
    }
}

// MARK: Bid popup

/// The bid, and what it will do before it is placed: how much gold is held, what stays spendable, what happens if someone outbids you or the auction is extended.
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
            let p = AuctionRules.preview(a, amount: amount, bidder: GoldVault.meID, wallet: session.state.wallet, now: now)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    stepButton("minus") { amount = max(AuctionRules.minimumBid(a), amount - AuctionRules.increment(at: max(1, amount))) }
                    TextField("Gold", value: $amount, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.center)
                        .textStyle(.figure, numeric: true).frame(minHeight: 48)
                        .accessibilityIdentifier("bid-amount")
                    stepButton("plus") { amount += AuctionRules.increment(at: max(1, amount)) }
                }
                Text("Lowest bid now: \(StoreText.gold(p.minimum))").textStyle(.caption).frame(maxWidth: .infinity)
                Hairline()
                line("Held while you lead", StoreText.gold(p.heldAfter))
                line("Still available", StoreText.gold(p.availableAfter))
                Text("If someone outbids you, the held gold comes back at once. If you win, the bid is paid and the piece joins your Cabinet.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                if p.extendsAuction { Text("This bid is in the last two minutes, so the auction is extended to give others time to answer.").textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
                if a.reserve != nil { Text(p.reserveMetAfter ? "This bid meets the reserve." : "This bid does not meet the reserve yet; if the reserve is not met the piece is not sold and your gold comes back.").textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
                if let why = p.problem { Text(why).textStyle(.body, tint: Theme.loss) }
                else if let why = session.problem { Text(why).textStyle(.body, tint: Theme.loss) }
            }
            .onAppear { if !seeded { amount = AuctionRules.minimumBid(a); seeded = true } }
            .popupFooter {
                PopupFooter(cancel: "Cancel", action: "Hold \(StoreText.gold(amount)) and bid", onCancel: { close() }, onAction: {
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

// MARK: Listing popup

/// Selling a piece: start price, optional reserve, length, and what the fee and the reserve will do.
struct ListingCard: View {
    var item: ArtifactItem
    private let session = StoreSession.shared
    @State private var startPrice = 0
    @State private var useReserve = false
    @State private var reserve = 0
    @State private var duration: AuctionDuration = .sixHours
    @State private var seeded = false
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        let problem: String? = AuctionRules.listingProblem(startPrice: startPrice, reserve: useReserve ? reserve : nil)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ArtifactRow(item: item)
            field("Start price (gold)", $startPrice, id: "list-start")
            Toggle("Set a reserve", isOn: $useReserve)
            if useReserve { field("Reserve (gold)", $reserve, id: "list-reserve") }
            Text("Length").textStyle(.caption)
            SegmentedChoice(items: AuctionDuration.allCases, title: { (d: AuctionDuration) -> String in d.title }, selection: $duration)
            Hairline()
            Text("The piece leaves your cabinet while it is on sale. The fee is \(AuctionRules.feePercent)% of the final price, at least 1 gold, and leaves the economy. At your start price you would receive \(StoreText.gold(AuctionRules.proceeds(forSale: startPrice))).")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            if useReserve { Text("A reserve is hidden; bidders see only whether it is met. If bids stay below it, the piece is not sold, there is no fee and it comes back to you.").textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
            if let problem { Text(problem).textStyle(.body, tint: Theme.loss) }
            else if let why = session.problem { Text(why).textStyle(.body, tint: Theme.loss) }
        }
        .onAppear {
            if !seeded {
                let base: Int = [BoxRarity.common: 20, .rare: 80, .epic: 300, .legendary: 1_200][ArtifactCatalog.def(item.defID)?.rarity ?? .common] ?? 20
                startPrice = base; reserve = base * 2; seeded = true
            }
        }
        .popupFooter {
            PopupFooter(cancel: "Cancel", action: "Put it up for \(duration.title)", onCancel: { close() }, onAction: {
                Task { if await session.list(itemID: item.id, startPrice: startPrice, reserve: useReserve ? reserve : nil, duration: duration) { Haptics.success(); close() } }
            }, actionEnabled: problem == nil)
        }
    }

    private func field(_ title: String, _ value: Binding<Int>, id: String) -> some View {
        HStack {
            Text(title).textStyle(.body)
            Spacer()
            TextField("0", value: value, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .textStyle(.headline, numeric: true).frame(width: 110, minHeight: 44)
                .accessibilityIdentifier(id)
        }
    }
}
