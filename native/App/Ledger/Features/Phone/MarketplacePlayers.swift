import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

enum ListingFormat {
    static func money(_ v: Double, _ code: String) -> String {
        let n: String = v.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
        return n + " " + code
    }

    static func lastSeen(_ at: Double?, online: Bool) -> String {
        if online { return "Online now" }
        guard let at else { return "Offline" }
        let mins: Int = max(1, Int((Date().timeIntervalSince1970 - at) / 60))
        if mins < 60 { return "Seen \(mins) min ago" }
        if mins < 60 * 24 { return "Seen \(mins / 60) h ago" }
        return "Seen \(mins / (60 * 24)) d ago"
    }

    static func condition(_ c: Double) -> String {
        switch c {
        case ..<0.35: return "Poor"
        case ..<0.6: return "Worn"
        case ..<0.8: return "Fair"
        case ..<0.93: return "Good"
        default: return "Excellent"
        }
    }

    static func kindFilter(_ title: String) -> String? {
        switch title {
        case "Cars": return "car"
        case "Vans and trucks": return "van"
        case "Planes": return "plane"
        case "Boats": return "boat"
        case "Equipment": return "equipment"
        case "Luxury": return "luxury"
        default: return nil
        }
    }

    static func condition(of l: PlayerListing) -> String {
        condition(l.item["seen"].isNull ? l.item["cond"].double : l.item["seen"].double)
    }

    static func detail(_ l: PlayerListing) -> String {
        var parts: [String] = []
        let age: Int = l.item["age"].int
        if age > 0 { parts.append(age == 1 ? "1 yr old" : "\(age) yrs old") }
        let km: Int = l.item["km"].int
        if km > 0 { parts.append("\(km.formatted()) km") }
        return parts.isEmpty ? l.kind.capitalized : parts.joined(separator: " \u{00B7} ")
    }

    static func posted(_ at: Double) -> String {
        let mins: Int = max(0, Int((Date().timeIntervalSince1970 - at) / 60))
        if mins < 60 { return "just now" }
        if mins < 60 * 24 { return "\(mins / 60) h ago" }
        return "\(mins / (60 * 24)) d ago"
    }

    static func photoKey(_ family: String, _ seed: String) -> String {
        ArtLibrary.itemKey(group: "", familyKey: family, seed: seed) ?? ""
    }
}

@MainActor
final class PlayerMarketModel: ObservableObject {
    @Published var listings: [PlayerListing] = []
    @Published var state: MarketState = .empty
    @Published var loaded = false
    @Published var loadFailed = false
    @Published var busy = false

    var openDeals: Int { state.incoming.filter { (d: MarketDeal) -> Bool in d.isOpen }.count + state.outgoing.filter { (d: MarketDeal) -> Bool in d.status == "discussing" }.count }

    func refresh(_ online: OnlineSession) async {
        guard online.isSignedIn else { listings = []; state = .empty; loaded = true; return }
        var failed = false
        do { listings = try await online.service.marketBrowse(kind: nil) } catch { failed = true }
        do { state = try await online.service.marketMine() } catch { failed = true }
        loadFailed = failed
        loaded = true
    }

    private func finish(_ store: GameStore, _ online: OnlineSession) async {
        await online.syncWorld(store: store)
        await refresh(online)
    }

    func buy(_ l: PlayerListing, store: GameStore, online: OnlineSession) async -> String? {
        guard let e = store.engine else { return "Not ready." }
        let cost: Double = e.internalAmount(l.price, currency: l.currency)
        if e.state.cash < cost { return "You do not have the cash for this." }
        busy = true
        defer { busy = false }
        do {
            let d: MarketDeal = try await online.service.marketBuy(listingID: l.id)
            let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in g.holdForDeal(dealID: d.id, amount: cost, label: "Marketplace: " + l.title) }
            if let why = r?.reason { _ = try? await online.service.marketWithdraw(dealID: d.id); await refresh(online); return why }
            await finish(store, online)
            return nil
        } catch { return OnlineWords.friendly(error) }
    }

    func offer(_ l: PlayerListing, price: Double, store: GameStore, online: OnlineSession) async -> String? {
        guard let e = store.engine else { return "Not ready." }
        let cost: Double = e.internalAmount(price, currency: l.currency)
        if e.state.cash < cost { return "You do not have the cash for this." }
        busy = true
        defer { busy = false }
        do {
            let d: MarketDeal = try await online.service.marketOffer(listingID: l.id, price: price)
            let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in g.holdForDeal(dealID: d.id, amount: cost, label: "Marketplace: " + l.title) }
            if let why = r?.reason { _ = try? await online.service.marketWithdraw(dealID: d.id); await refresh(online); return why }
            await finish(store, online)
            return nil
        } catch { return OnlineWords.friendly(error) }
    }

    func withdraw(_ d: MarketDeal, store: GameStore, online: OnlineSession) async -> String? {
        busy = true
        defer { busy = false }
        do {
            _ = try await online.service.marketWithdraw(dealID: d.id)
            await finish(store, online)
            return nil
        } catch { return OnlineWords.friendly(error) }
    }

    func answer(_ d: MarketDeal, accept: Bool, store: GameStore, online: OnlineSession) async -> String? {
        if accept, let e = store.engine {
            let need: Double = e.internalAmount(d.specialPrice ?? d.price, currency: d.currency) - e.inventoryHeld(dealID: d.id)
            if need > 0, e.state.cash < need { return "You do not have the cash for this." }
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await online.service.marketAnswer(dealID: d.id, accept: accept)
            await finish(store, online)
            return nil
        } catch { return OnlineWords.friendly(error) }
    }

    func respond(_ d: MarketDeal, reply: MarketReply, price: Double?, store: GameStore, online: OnlineSession) async -> String? {
        busy = true
        defer { busy = false }
        do {
            _ = try await online.service.marketRespond(dealID: d.id, reply: reply, price: price)
            await finish(store, online)
            return nil
        } catch { return OnlineWords.friendly(error) }
    }

    func list(itemID: String, price: Double, store: GameStore, online: OnlineSession) async -> String? {
        guard let e = store.engine else { return "Not ready." }
        if let why = e.inventoryListingProblem(itemID: itemID) { return why }
        guard let payload = e.inventoryListingPayload(itemID: itemID) else { return "That item is gone." }
        busy = true
        defer { busy = false }
        do {
            let l: PlayerListing = try await online.service.marketList(item: payload, price: price, currency: e.homeCurrencyCode)
            store.act { (g: inout GameEngine) in g.lockInventory(itemID: itemID, listingID: l.id) }
            await refresh(online)
            return nil
        } catch { return OnlineWords.friendly(error) }
    }

    func cancel(_ l: PlayerListing, store: GameStore, online: OnlineSession) async -> String? {
        busy = true
        defer { busy = false }
        do {
            try await online.service.marketCancel(listingID: l.id)
            store.act { (g: inout GameEngine) in g.unlockInventory(itemID: l.itemID) }
            await refresh(online)
            return nil
        } catch { return OnlineWords.friendly(error) }
    }
}

struct MarketPriceField: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var code: String
    @Binding var value: Double
    @State private var text = ""

    var body: some View {
        HStack {
            Text(code).textStyle(.caption, tint: P.inkFaint, weight: .medium)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .textStyle(.headline, numeric: true)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, new in
                    let cleaned: String = new.replacingOccurrences(of: ",", with: ".").filter { (c: Character) -> Bool in c.isNumber || c == "." }
                    value = Double(cleaned) ?? 0
                }
        }
        .padding(.vertical, Theme.Space.s)
        .overlay(alignment: .bottom) { Rectangle().fill(P.hairline).frame(height: 0.5) }
        .onAppear { if value > 0, text.isEmpty { text = String(Int(saturating: value.rounded())) } }
    }
}

struct SellerLine: View {
    @Environment(\.outsidePalette) private var P
    var name: String
    var online: Bool
    var lastSeen: Double?
    var colour: Int = 0

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Circle().fill(online ? Color.green : P.inkFaint).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).textStyle(.body, weight: .semibold)
                Text(ListingFormat.lastSeen(lastSeen, online: online)).textStyle(.caption, tint: online ? P.accent : P.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PlayerListingTile: View {
    var listing: PlayerListing

    var body: some View {
        MarketCard(photoKey: ListingFormat.photoKey(listing.family, listing.itemID), badge: ListingFormat.condition(of: listing), title: listing.title,
                   detail: ListingFormat.detail(listing), price: ListingFormat.money(listing.price, listing.currency), seller: listing.sellerName,
                   avatar: PlayerAvatar(initials: ArtLibrary.initials(listing.sellerName), colour: listing.avatarColour ?? AvatarCatalog.colour(for: listing.sellerName),
                                        icon: listing.avatarIcon, size: 30),
                   online: listing.sellerOnline, note: listing.mine ? "Your listing" : "")
    }
}

struct PlayerListingPage: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject var model: PlayerMarketModel
    var listingID: String
    var onClose: () -> Void

    @State private var offering = false
    @State private var offerPrice: Double = 0
    @State private var problem: String? = nil
    @State private var pending: PendingAction? = nil

    private var listing: PlayerListing? { model.listings.first { (l: PlayerListing) -> Bool in l.id == listingID } }

    var body: some View {
        Group {
            if let l = listing { content(l) } else { ShopEmptyNote(text: "This listing is gone.", glyph: Glyph.marketplace, buttonTitle: "Back") { onClose() }.padding(Theme.Space.page) }
        }
        .confirmAction($pending)
    }

    private func content(_ l: PlayerListing) -> some View {
        let item: JSONValue = l.item
        let cond: Double = item["seen"].isNull ? item["cond"].double : item["seen"].double
        var facts: [(label: String, value: String)] = [(label: "Condition", value: ListingFormat.condition(cond))]
        if item["age"].int > 0 { facts.append((label: "Age", value: "\(item["age"].int) years")) }
        if item["km"].int > 0 { facts.append((label: "Distance", value: "\(item["km"].int.formatted()) km")) }
        let priceText: String = ListingFormat.money(l.price, l.currency)
        let country: String = (l.sellerCountry ?? "").isEmpty ? "" : OnlineCountry.name(l.sellerCountry ?? "")
        return ShopPage(spacing: Theme.Space.m) {
            ListingHero(height: 260, location: country, counter: "1/1", shareText: "\(l.title), \(priceText)") {
                ShopPhoto(name: "", glyph: Glyph.marketplace, height: 260, cornerRadius: 0, item: ListingFormat.photoKey(l.family, l.itemID))
            } badge: {
                ListingPill(text: ListingFormat.condition(cond))
            }
            HStack(spacing: Theme.Space.s) {
                Text(l.title).textStyle(.title).accessibilityAddTraits(.isHeader).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(l.kind.capitalized).textStyle(.caption, weight: .semibold)
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, 4).background(Capsule().fill(P.inset))
                Spacer(minLength: 0)
            }
            ListingStats {
                Text("Price").textStyle(.caption)
                Text(priceText).textStyle(.title, numeric: true).lineLimit(1).minimumScaleFactor(0.6)
            } right: {
                Text("Posted").textStyle(.caption)
                Text(ListingFormat.posted(l.postedAt)).textStyle(.headline)
            }
            ShopSection(title: "Details") { ShopFacts(facts: facts) }
            ShopSection(title: "Seller") {
                sellerLink(l) {
                    HStack(spacing: Theme.Space.m) {
                        PlayerAvatar(initials: ArtLibrary.initials(l.sellerName), colour: l.avatarColour ?? AvatarCatalog.colour(for: l.sellerName), icon: l.avatarIcon, size: 40)
                            .overlay(alignment: .bottomTrailing) {
                                Circle().fill(l.sellerOnline ? P.gain : P.inkDim).frame(width: 11, height: 11)
                                    .overlay(Circle().strokeBorder(P.surface, lineWidth: 2))
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.sellerName).textStyle(.body, weight: .semibold).lineLimit(1)
                            Text(ListingFormat.lastSeen(l.sellerLastSeen, online: l.sellerOnline)).textStyle(.caption, tint: l.sellerOnline ? P.gain : P.inkFaint)
                        }
                        Spacer(minLength: 0)
                        if let lv = l.sellerLevel { Text("Level \(lv)").textStyle(.caption) }
                        if !l.mine { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint) }
                    }
                }
            }
            if let d = l.openDeal { dealNote(d) }
            if let problem { Text(problem).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityIdentifier("mk-player-listing")
        .safeAreaInset(edge: .bottom, spacing: 0) { ShopBottomAction { actions(l) }.environment(\.outsidePalette, P) }
        .centerSheet(isPresented: $offering, title: "Your offer", category: .medium, tone: .info) { offerSheet(l) }
    }

    /// The seller panel opens the seller's player card; your own listing has nothing to open.
    @ViewBuilder private func sellerLink<C: View>(_ l: PlayerListing, @ViewBuilder content: @escaping () -> C) -> some View {
        if l.mine {
            ListingPanel { content() }
        } else {
            NavigationLink { PlayerProfileView(playerID: l.sellerID, knownName: l.sellerName) } label: { ListingPanel { content() } }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("mk-seller-card")
        }
    }

    private func dealNote(_ d: MarketDeal) -> some View {
        ShopSection(title: "Your request") {
            Text(d.statusText).textStyle(.body, weight: .semibold)
            if d.status == "discussing", let sp = d.specialPrice {
                Text("\(d.otherName) will sell it to you for \(ListingFormat.money(sp, d.currency)).").textStyle(.body, tint: P.inkSoft)
            } else {
                Text("The money is held until \(d.otherName) answers. You get it back if the deal does not go through.").textStyle(.caption, tint: P.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func actions(_ l: PlayerListing) -> some View {
        if l.mine {
            Text("This is your listing.").textStyle(.caption, tint: P.inkFaint)
        } else if let d = l.openDeal {
            if d.status == "discussing" {
                Button("Accept \(ListingFormat.money(d.specialPrice ?? d.price, d.currency))") { run { await model.answer(d, accept: true, store: store, online: online) } }
                    .buttonStyle(ShopFilledButtonStyle())
                Button("No thanks") { run { await model.answer(d, accept: false, store: store, online: online) } }.buttonStyle(MarketEqualButtonStyle())
            } else {
                Button("Withdraw request") { run { await model.withdraw(d, store: store, online: online) } }.buttonStyle(MarketEqualButtonStyle())
            }
        } else {
            Button("Buy now") {
                Haptics.tap()
                pending = PendingAction(title: "Send buy request", message: "\(l.sellerName) gets your request and answers when they can. \(ListingFormat.money(l.price, l.currency)) is held from your cash until then.",
                                        button: "Send request") { run { await model.buy(l, store: store, online: online) } }
            }
            .buttonStyle(ShopFilledButtonStyle())
            .disabled(model.busy)
            .accessibilityIdentifier("mk-player-buy")
            if l.offerUsed {
                Text("You have already made your one offer.").textStyle(.caption, tint: P.inkFaint)
            } else {
                Button("Make an offer") { Haptics.tap(); offerPrice = (l.price * 0.9).rounded(); offering = true }
                    .buttonStyle(MarketEqualButtonStyle()).disabled(model.busy)
                    .accessibilityIdentifier("mk-player-offer")
            }
        }
    }

    private func offerSheet(_ l: PlayerListing) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("You can make one offer. If \(l.sellerName) does not answer, you cannot send another.").textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            MarketPriceField(title: "Price", code: l.currency, value: $offerPrice)
            Button("Send offer") {
                offering = false
                run { await model.offer(l, price: offerPrice, store: store, online: online) }
            }
            .buttonStyle(ShopFilledButtonStyle())
            .disabled(offerPrice <= 0 || offerPrice >= l.price)
        }
        .padding(Theme.Space.page)
    }

    private func run(_ work: @escaping () async -> String?) {
        Task {
            problem = await work()
            if let problem { Haptics.warning(); store.show(problem, tone: "warn") } else { Haptics.success() }
        }
    }
}

struct MarketDealsView: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject var model: PlayerMarketModel
    @State private var discussing: MarketDeal? = nil
    @State private var special: Double = 0
    @State private var openID: String? = nil

    var body: some View {
        ShopPage(spacing: Theme.Space.l) {
            if model.state.incoming.isEmpty && model.state.outgoing.isEmpty {
                ShopEmptyNote(text: "No deals yet. Requests you send and receive show up here.", glyph: Glyph.marketplace)
            }
            if !model.state.incoming.isEmpty {
                ShopSection(title: "Wants to buy from you") {
                    ForEach(model.state.incoming) { (d: MarketDeal) in incomingRow(d) }
                }
            }
            if !model.state.outgoing.isEmpty {
                ShopSection(title: "Your requests") {
                    ForEach(model.state.outgoing) { (d: MarketDeal) in outgoingRow(d) }
                }
            }
        }
        .accessibilityIdentifier("mk-deals")
        .centerSheet(item: $discussing, title: "Lower the price", category: .medium, tone: .info) { (d: MarketDeal) in
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Set a price just for \(d.otherName). They can take it or leave it.").textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                MarketPriceField(title: "Price", code: d.currency, value: $special)
                Button("Send price") {
                    discussing = nil
                    let p: Double = special
                    Task { await report(model.respond(d, reply: .discuss, price: p, store: store, online: online)) }
                }
                .buttonStyle(ShopFilledButtonStyle())
                .disabled(special <= 0 || special >= d.listingPrice)
            }
            .padding(Theme.Space.page)
        }
    }

    private func report(_ r: String?) async {
        let why: String? = r
        if let why { Haptics.warning(); store.show(why, tone: "warn") } else { Haptics.success() }
    }

    private func incomingRow(_ d: MarketDeal) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SellerLine(name: d.otherName, online: d.otherOnline, lastSeen: nil)
            Text(d.title).textStyle(.body, weight: .semibold)
            Text(d.kind == "offer" ? "Offers \(ListingFormat.money(d.price, d.currency)) (asking \(ListingFormat.money(d.listingPrice, d.currency)))"
                                   : "Wants to pay \(ListingFormat.money(d.price, d.currency))").textStyle(.body, tint: P.inkSoft)
            if d.status == "discussing" {
                Text("Waiting for \(d.otherName) to answer your price.").textStyle(.caption, tint: P.inkFaint)
            } else {
                HStack(spacing: Theme.Space.xs) {
                    Button("Accept") { Task { await report(model.respond(d, reply: .accept, price: nil, store: store, online: online)) } }.buttonStyle(ShopFilledButtonStyle())
                    Button("Decline") { Task { await report(model.respond(d, reply: .decline, price: nil, store: store, online: online)) } }.buttonStyle(MarketEqualButtonStyle())
                    Button("Discuss") { special = (d.listingPrice * 0.95).rounded(); discussing = d }.buttonStyle(MarketEqualButtonStyle())
                }
            }
            Hairline()
        }
        .accessibilityIdentifier("mk-incoming-\(d.id)")
    }

    private func outgoingRow(_ d: MarketDeal) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(d.title).textStyle(.body, weight: .semibold)
            Text(d.statusText).textStyle(.caption, tint: d.status == "discussing" ? P.accent : P.inkFaint)
            Text(ListingFormat.money(d.finalPrice ?? d.specialPrice ?? d.price, d.currency)).textStyle(.body, tint: P.inkSoft, numeric: true)
            if d.status == "discussing" {
                HStack(spacing: Theme.Space.xs) {
                    Button("Accept") { Task { await report(model.answer(d, accept: true, store: store, online: online)) } }.buttonStyle(ShopFilledButtonStyle())
                    Button("No thanks") { Task { await report(model.answer(d, accept: false, store: store, online: online)) } }.buttonStyle(MarketEqualButtonStyle())
                }
            } else if d.isOpen {
                Button("Withdraw") { Task { await report(model.withdraw(d, store: store, online: online)) } }.buttonStyle(MarketEqualButtonStyle())
            }
            Hairline()
        }
    }
}

struct MarketSellView: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject var model: PlayerMarketModel
    var onOpenItem: (String) -> Void

    @State private var pending: PendingAction? = nil

    var body: some View {
        if let e = store.engine {
            ShopPage(spacing: Theme.Space.l) {
                listings(e)
                inventory(e)
                Color.clear.frame(height: 56)
            }
            .accessibilityIdentifier("mk-sell")
            .confirmAction($pending)
        }
    }

    @ViewBuilder private func listings(_ e: GameEngine) -> some View {
        let mine: [PlayerListing] = model.state.listings.filter { (l: PlayerListing) -> Bool in l.status == "active" }
        if !mine.isEmpty {
            ShopSection(title: "For sale") {
                ForEach(mine) { (l: PlayerListing) in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.title).textStyle(.body, weight: .semibold)
                            Text(ListingFormat.money(l.price, l.currency)).textStyle(.caption, tint: P.inkFaint)
                        }
                        Spacer(minLength: 0)
                        Button("Take down") {
                            pending = PendingAction(title: "Take down", message: "The item goes back to your inventory. Open requests on it are closed and the money goes back to the buyers.", button: "Take down") {
                                Task { _ = await model.cancel(l, store: store, online: online) }
                            }
                        }
                        .textStyle(.body, tint: P.accent, weight: .semibold)
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            }
        }
    }

    @ViewBuilder private func inventory(_ e: GameEngine) -> some View {
        let items: [InventoryItem] = e.inventoryItems
        ShopSection(title: "Inventory", trailing: items.isEmpty ? "" : store.short(e.inventoryWorth), note: "Things you own and can sell, repair or keep.") {
            if items.isEmpty {
                ShopEmptyNote(text: "Nothing yet. Buy something here, or move a vehicle or machine in from a company.", glyph: Glyph.marketplace)
            }
            ForEach(items) { (i: InventoryItem) in
                Button { Haptics.tap(); onOpenItem(i.id) } label: {
                    HStack(spacing: Theme.Space.s) {
                        ShopPhoto(name: "", glyph: Glyph.marketplace, height: 64, cornerRadius: Theme.Radius.small, item: ListingFormat.photoKey(i.family, i.id)).frame(width: 84)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.title).textStyle(.body, weight: .semibold).lineLimit(2).multilineTextAlignment(.leading)
                            Text(statusText(i)).textStyle(.caption, tint: P.inkFaint)
                        }
                        Spacer(minLength: 0)
                        Text(store.short(i.value)).textStyle(.body, numeric: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("mk-inv-\(i.id)")
            }
        }
    }

    private func statusText(_ i: InventoryItem) -> String {
        if i.isListed { return "For sale" }
        if i.inRepair { return "In repair" }
        return ListingFormat.condition(i.cond)
    }
}

struct MarketPickItemSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @ObservedObject var model: PlayerMarketModel
    var onPick: (String) -> Void

    var body: some View {
        let e: GameEngine? = store.engine
        let free: [InventoryItem] = (e?.inventoryItems ?? []).filter { (i: InventoryItem) -> Bool in i.isFree }
        let pieces: [Luxury.Piece] = e.map { (g: GameEngine) -> [Luxury.Piece] in Luxury.pieces(g.state).filter { (p: Luxury.Piece) -> Bool in p.companyID == 0 && g.luxurySaleProblem(pieceID: p.id) == nil } } ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            if free.isEmpty && pieces.isEmpty {
                Text("Nothing to list. Move a vehicle or machine in from a company, or buy something here.").textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(free) { (i: InventoryItem) in
                row(i.title, store.short(i.value)) { onPick(i.id) }
            }
            ForEach(pieces) { (p: Luxury.Piece) in
                row(p.item.name, store.short(p.value)) {
                    let before: Set<String> = Set((store.engine?.inventoryItems ?? []).map { (i: InventoryItem) -> String in i.id })
                    let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in g.moveLuxuryToInventory(pieceID: p.id) }
                    if let why = r?.reason { store.show(why, tone: "warn"); return }
                    if let made = store.engine?.inventoryItems.first(where: { (i: InventoryItem) -> Bool in !before.contains(i.id) }) { onPick(made.id) }
                }
            }
        }
        .padding(Theme.Space.page)
    }

    private func row(_ title: String, _ value: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack {
                Text(title).textStyle(.body, weight: .semibold).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s)
                Text(value).textStyle(.body, tint: P.inkSoft, numeric: true)
            }
            .padding(.vertical, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct InventoryItemPage: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject var model: PlayerMarketModel
    var itemID: String
    var onClose: () -> Void

    @State private var price: Double = 0
    @State private var listing = false
    @State private var pending: PendingAction? = nil

    var body: some View {
        if let e = store.engine, let i = e.inventoryItem(itemID) {
            ShopPage {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ShopPhoto(name: "", glyph: Glyph.marketplace, height: 280, item: ListingFormat.photoKey(i.family, i.id)).padding(.bottom, Theme.Space.m)
                    Text(store.short(i.value)).textStyle(.display)
                    Text(i.title).textStyle(.title).accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
                }
                ShopSection(title: "Item") { ShopFacts(facts: facts(i)) }
                repairSection(e, i)
                stockSection(e, i)
            }
            .accessibilityIdentifier("mk-inventory-item")
            .confirmAction($pending)
            .safeAreaInset(edge: .bottom, spacing: 0) { ShopBottomAction { actions(e, i) }.environment(\.outsidePalette, P) }
            .centerSheet(isPresented: $listing, title: "List for sale", category: .medium, tone: .info) { listSheet(e, i) }
        } else {
            ShopEmptyNote(text: "That item is gone.", glyph: Glyph.marketplace, buttonTitle: "Back") { onClose() }.padding(Theme.Space.page)
        }
    }

    private func facts(_ i: InventoryItem) -> [(label: String, value: String)] {
        var f: [(label: String, value: String)] = [(label: "Condition", value: ListingFormat.condition(i.cond)), (label: "Paid", value: store.short(i.paid))]
        if i.age > 0 { f.append((label: "Age", value: "\(i.age) years")) }
        if i.km > 0 { f.append((label: "Distance", value: "\(i.km.formatted()) km")) }
        return f
    }

    @ViewBuilder private func repairSection(_ e: GameEngine, _ i: InventoryItem) -> some View {
        if i.inRepair {
            ShopSection(title: "Repair") { Text("At the garage. It comes back in better condition.").textStyle(.body, tint: P.inkSoft) }
        } else if i.isFree && !i.luxury {
            let offers: [InventoryRepairOffer] = e.inventoryRepairOffers(itemID: i.id)
            if !offers.isEmpty {
                ShopSection(title: "Repair", note: "Raises its condition and what it is worth.") {
                    ForEach(offers) { (o: InventoryRepairOffer) in
                        Button {
                            pending = PendingAction(title: "Repair", message: "\(o.shopName) repairs it in \(o.weeks) weeks for \(store.short(o.price)). It should be worth about \(store.short(o.valueGain)) more.",
                                                    button: "Repair", amount: o.price) {
                                let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in g.startInventoryRepair(itemID: i.id, shopID: o.shopID) }
                                if let why = r?.reason { store.show(why, tone: "warn") }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.shopName).textStyle(.body, weight: .semibold)
                                    Text("\(o.weeks) weeks \u{00B7} worth \(store.short(o.valueGain)) more").textStyle(.caption, tint: P.inkFaint)
                                }
                                Spacer(minLength: 0)
                                Text(store.short(o.price)).textStyle(.body, numeric: true)
                            }
                            .padding(.vertical, Theme.Space.xs).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder private func stockSection(_ e: GameEngine, _ i: InventoryItem) -> some View {
        let dealers: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive && c.type == UsedCarDealer.tradeID && e.inventoryStockProblem(itemID: i.id, companyID: c.id) == nil }
        if i.isFree && i.canMoveToCompany && !dealers.isEmpty {
            ShopSection(title: "Sell through your dealership", note: "The dealership buys it at what you paid and sells it to customers.") {
                ForEach(dealers) { (c: Company) in
                    Button(c.name) {
                        let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in g.stockInventoryItem(itemID: i.id, companyID: c.id) }
                        if let why = r?.reason { store.show(why, tone: "warn") } else { onClose() }
                    }
                    .buttonStyle(MarketEqualButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private func actions(_ e: GameEngine, _ i: InventoryItem) -> some View {
        if i.isFree {
            Button("List for sale") {
                Haptics.tap()
                price = e.serverAmount(e.inventorySuggestedPrice(itemID: i.id), currency: e.homeCurrencyCode).rounded()
                listing = true
            }
            .buttonStyle(ShopFilledButtonStyle())
            .accessibilityIdentifier("mk-list-item")
            if i.luxury && e.inventoryCanKeepLuxury(itemID: i.id) {
                Button("Keep it") {
                    let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in g.keepInventoryLuxury(itemID: i.id) }
                    if let why = r?.reason { store.show(why, tone: "warn") } else { onClose() }
                }
                .buttonStyle(MarketEqualButtonStyle())
            }
        } else if i.isListed {
            Text("It is for sale. Take it down from the Sell tab to change it.").textStyle(.caption, tint: P.inkFaint)
        }
    }

    private func listSheet(_ e: GameEngine, _ i: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Buyers see the item and how it looks. You can take the listing down any time.").textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            MarketPriceField(title: "Price", code: e.homeCurrencyCode, value: $price)
            Button("List it") {
                listing = false
                let p: Double = price
                Task {
                    if let why = await model.list(itemID: i.id, price: p, store: store, online: online) { Haptics.warning(); store.show(why, tone: "warn") } else { Haptics.success(); onClose() }
                }
            }
            .buttonStyle(ShopFilledButtonStyle())
            .disabled(price <= 0)
        }
        .padding(Theme.Space.page)
    }
}
