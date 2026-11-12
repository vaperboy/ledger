import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct MarketplaceApp: View {
    private let P = OutsidePalette.marketplace
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }

    enum Filter: String, CaseIterable, Hashable {
        case all = "All", cars = "Cars", vans = "Vans and trucks", equipment = "Equipment", furniture = "Furniture", other = "Other"
    }

    enum Sort: String, CaseIterable, Hashable {
        case newest = "Newest", low = "Price low to high", high = "Price high to low"

        var short: String {
            switch self {
            case .newest: return "Newest"
            case .low: return "Low price"
            case .high: return "High price"
            }
        }
    }

    enum Mode: String, CaseIterable, Hashable {
        case nearby = "Near you", players = "Players", deals = "Deals", sell = "Sell"
    }

    private static let playerKinds: [String] = ["All", "Cars", "Vans and trucks", "Planes", "Boats", "Equipment", "Luxury"]

    @Environment(OnlineSession.self) private var online
    @StateObject private var players = PlayerMarketModel()
    @State private var mode: Mode = .nearby
    @State private var playerKind = "All"
    @State private var playerListingID: String? = nil
    @State private var itemID: String? = nil
    @State private var companyID = 0
    @State private var filter: Filter = .all
    @State private var sort: Sort = .newest
    @State private var openID: String? = nil
    @State private var refusedIDs: Set<String> = []
    @State private var query = ""
    @State private var recentOnly = false
    @State private var onlineOnly = false
    @State private var picking = false
    private let storeSession = StoreSession.shared

    var body: some View {
        page
            .overlay(alignment: .bottom) {
                if showsNew { MarketNewButton { picking = true }.padding(.bottom, Theme.Space.l) }
            }
            .centerSheet(isPresented: $picking, title: "New listing", category: .medium, tone: .info) {
                MarketPickItemSheet(model: players, onPick: { (id: String) in picking = false; itemID = id })
                    .environmentObject(store)
            }
            .outsideScreen(P)
            .swipeBackEnabled(canStep: { openID != nil || playerListingID != nil || itemID != nil }, step: { stepBack() })
            .task(id: mode) { await players.refresh(online) }
            .task { if !storeSession.loaded { await storeSession.load() } }
            .safeAreaInset(edge: .top, spacing: 0) { VStack(spacing: 0) { band; header } }
    }

    private var showsNew: Bool { openID == nil && playerListingID == nil && itemID == nil && mode != .deals }

    private var band: some View {
        ShopBand(title: "Marketplace", glyph: Glyph.marketplace, color: P.accent, onBack: { back() }, backLabel: (openID == nil && playerListingID == nil && itemID == nil) ? "Back to Phone" : "Back") {
            MarketGoldPill(gold: storeSession.gold)
        }
        .environment(\.outsidePalette, P)
    }

    private func back() {
        if openID != nil || playerListingID != nil || itemID != nil { stepBack() } else { dismiss() }
    }

    private func stepBack() {
        if itemID != nil { itemID = nil } else if playerListingID != nil { playerListingID = nil } else { openID = nil }
    }

    @ViewBuilder private var header: some View {
        if openID == nil && playerListingID == nil && itemID == nil {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ShopChipRow {
                    ForEach(Mode.allCases, id: \.self) { (m: Mode) in
                        ShopChip(title: m == .deals && players.openDeals > 0 ? "Deals (\(players.openDeals))" : m.rawValue, selected: mode == m) { mode = m }
                            .accessibilityIdentifier("mk-mode-\(m.rawValue)")
                    }
                }
                if mode == .players {
                    ShopChipRow {
                        ForEach(Self.playerKinds, id: \.self) { (k: String) in
                            ShopChip(title: k, selected: playerKind == k) { playerKind = k }
                        }
                    }
                }
                if mode == .nearby, let e = store.engine, let co = current(e) { nearbyHeader(e, co) }
            }
            .padding(.horizontal, Theme.Space.page).padding(.bottom, Theme.Space.xs)
            .frame(maxWidth: ShopMetrics.maxWidth)
            .frame(maxWidth: .infinity)
            .background(P.page)
            .overlay(alignment: .bottom) { Hairline() }
            .environment(\.outsidePalette, P)
        }
    }

    @ViewBuilder private func nearbyHeader(_ e: GameEngine, _ co: Company) -> some View {
        ShopChipRow {
            ForEach(Filter.allCases, id: \.self) { (f: Filter) in
                ShopChip(title: f.rawValue, selected: filter == f) { filter = f }
                    .accessibilityIdentifier("mk-filter-\(f.rawValue)")
            }
        }
        lotLine(e, co)
    }

    @ViewBuilder private func lotLine(_ e: GameEngine, _ co: Company) -> some View {
        if co.type == UsedCarDealer.tradeID, let lot = e.usedCarLot(companyID: co.id) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text("Lot").textStyle(.caption, tint: P.inkFaint)
                Text("\(lot.used) of \(lot.spaces) spaces used, \(lot.free) free").textStyle(.caption, tint: lot.free == 0 ? P.caution : P.ink, weight: .semibold)
                Spacer(minLength: 0)
            }
            .accessibilityIdentifier("mk-lot-line")
        }
    }

    private func companyMenu(_ e: GameEngine, _ co: Company) -> some View {
        ShopCompanyMenu(caption: "Buying for", choices: shoppers(e).map { (c: Company) -> ShopCompanyMenu.Choice in
            ShopCompanyMenu.Choice(id: c.id, name: c.name, detail: "")
        }, selected: co.id, identifier: "mk-company", idPrefix: "mk-company") { (id: Int) in companyID = id }
    }

    private func tools(players isPlayers: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            Menu {
                Toggle("Posted in the last 3 days", isOn: $recentOnly)
                if isPlayers { Toggle("Online sellers only", isOn: $onlineOnly) }
            } label: {
                MarketPill(text: "Filter", symbol: "line.3.horizontal.decrease", active: recentOnly || (isPlayers && onlineOnly))
            }
            .accessibilityIdentifier("mk-filter")
            Menu {
                ForEach(Sort.allCases, id: \.self) { (s: Sort) in
                    Button { Haptics.choose(); sort = s } label: {
                        if s == sort { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) }
                    }
                }
            } label: {
                MarketPill(text: sort.short, symbol: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("mk-sort")
            MarketSearchBox(text: $query)
        }
    }

    private func shoppers(_ e: GameEngine) -> [Company] {
        e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
    }

    private func current(_ e: GameEngine) -> Company? {
        if let c = e.state.company(companyID), c.status.isLive { return c }
        return shoppers(e).first
    }

    static func category(_ family: String) -> Filter {
        let f: String = family.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { (w: String) -> Bool in f.contains(w) } }
        if has(["van", "truck", "bus", "pickup", "trailer", "tractor", "mixer", "tow", "ambulance"]) { return .vans }
        if has(["car", "taxi", "limousine", "suv", "estate", "bike", "scooter", "motorbike"]) { return .cars }
        if has(["desk", "chair", "table", "furniture", "sofa", "shelf", "shelving", "cabinet", "bed", "wardrobe", "counter"]) { return .furniture }
        if !ArtLibrary.itemKeys(group: "", familyKey: family).isEmpty { return .equipment }
        return .other
    }

    private func visible(_ all: [MarketListing], today: Int) -> [MarketListing] {
        var kept: [MarketListing] = filter == .all ? all : all.filter { (l: MarketListing) -> Bool in Self.category(l.family) == filter }
        if recentOnly { kept = kept.filter { (l: MarketListing) -> Bool in today - l.postedDay <= 3 } }
        let q: String = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            kept = kept.filter { (l: MarketListing) -> Bool in
                l.title.lowercased().contains(q) || l.city.lowercased().contains(q) || l.sellerName.lowercased().contains(q)
            }
        }
        return kept.sorted { (a: MarketListing, b: MarketListing) -> Bool in
            switch sort {
            case .newest: return a.postedDay != b.postedDay ? a.postedDay > b.postedDay : a.title < b.title
            case .low: return a.askingPrice != b.askingPrice ? a.askingPrice < b.askingPrice : a.title < b.title
            case .high: return a.askingPrice != b.askingPrice ? a.askingPrice > b.askingPrice : a.title < b.title
            }
        }
    }

    @ViewBuilder private var page: some View {
        if let id = itemID {
            InventoryItemPage(model: players, itemID: id, onClose: { itemID = nil })
        } else if let id = playerListingID {
            PlayerListingPage(model: players, listingID: id, onClose: { playerListingID = nil })
        } else {
            switch mode {
            case .nearby: nearbyPage
            case .players: playersPage
            case .deals: MarketDealsView(model: players)
            case .sell: MarketSellView(model: players, onOpenItem: { (id: String) in itemID = id })
            }
        }
    }

    private var playersPage: some View {
        let kind: String? = ListingFormat.kindFilter(playerKind)
        let q: String = query.trimmingCharacters(in: .whitespaces).lowercased()
        let now: Double = Date().timeIntervalSince1970
        var list: [PlayerListing] = players.listings.filter { (l: PlayerListing) -> Bool in kind == nil || l.kind == kind }
        if recentOnly { list = list.filter { (l: PlayerListing) -> Bool in now - l.postedAt <= 3 * 86_400 } }
        if onlineOnly { list = list.filter { (l: PlayerListing) -> Bool in l.sellerOnline } }
        if !q.isEmpty {
            list = list.filter { (l: PlayerListing) -> Bool in l.title.lowercased().contains(q) || l.sellerName.lowercased().contains(q) }
        }
        list.sort { (a: PlayerListing, b: PlayerListing) -> Bool in
            switch sort {
            case .newest: return a.postedAt != b.postedAt ? a.postedAt > b.postedAt : a.title < b.title
            case .low: return a.price != b.price ? a.price < b.price : a.title < b.title
            case .high: return a.price != b.price ? a.price > b.price : a.title < b.title
            }
        }
        let shown: [PlayerListing] = list
        return ShopPage(spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(shown.count == 1 ? "1 listing" : "\(shown.count) listings").textStyle(.title)
                Text("Buy from players, grow your business").textStyle(.caption)
            }
            tools(players: true)
            if !online.isSignedIn {
                ShopEmptyNote(text: "Sign in to see what other players are selling.", glyph: Glyph.marketplace)
            } else if shown.isEmpty {
                ShopEmptyNote(text: players.loaded ? "Nothing here yet. Be the first to list something." : "Loading.", glyph: Glyph.marketplace)
            }
            ShopGrid {
                ForEach(shown) { (l: PlayerListing) in
                    Button { Haptics.tap(); playerListingID = l.id } label: { PlayerListingTile(listing: l) }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("mk-player-\(l.id)")
                }
            }
            Color.clear.frame(height: 56)
        }
        .accessibilityIdentifier("mk-players")
    }

    @ViewBuilder private var nearbyPage: some View {
        if let e = store.engine, let co = current(e) {
            let all: [MarketListing] = MarketplaceBridge.listings(e, companyID: co.id)
            let cur: Currency = e.currency(for: co)
            if let id = openID, let l = all.first(where: { (x: MarketListing) -> Bool in x.id == id }) {
                MarketplaceListingPage(listing: l, cur: cur, companyID: co.id, today: e.state.day, refusedHere: refusedIDs.contains(l.id),
                                       onRefused: { (rid: String) in _ = refusedIDs.insert(rid) }, onBought: { openID = nil })
                    .id(l.id + String(co.id))
            } else {
                gridPage(e, visible(all, today: e.state.day), cur, co)
            }
        } else {
            ShopEmptyNote(text: "Nothing to buy for. Start a company first.", glyph: Glyph.marketplace)
                .padding(Theme.Space.page).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func gridPage(_ e: GameEngine, _ list: [MarketListing], _ cur: Currency, _ co: Company) -> some View {
        ShopPage(spacing: Theme.Space.l) {
            companyMenu(e, co)
            HStack(alignment: .center, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(list.count == 1 ? "1 listing" : "\(list.count) listings").textStyle(.title)
                    Text(filter == .all ? "Near you, from private sellers" : filter.rawValue).textStyle(.caption)
                }
                Spacer(minLength: Theme.Space.s)
            }
            tools(players: false)
            if list.isEmpty {
                ShopEmptyNote(text: "Nothing matches. New listings appear as the days go by.", glyph: Glyph.marketplace,
                              buttonTitle: filter == .all ? nil : "Show all listings") { filter = .all }
            }
            ShopGrid {
                ForEach(list, id: \.id) { (l: MarketListing) in
                    Button {
                        Haptics.tap()
                        openID = l.id
                    } label: {
                        MarketplaceTile(listing: l, price: cur.tidyShort(l.askingPrice), refused: refusedIDs.contains(l.id), today: e.state.day)
                            .newMarker(.marketplace, "l" + l.id, style: .capsule, alignment: .topTrailing)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("mk-listing-\(l.id)")
                }
            }
            Color.clear.frame(height: 56)
        }
        .accessibilityIdentifier("mk-grid")
    }
}

struct MarketplaceTile: View {
    var listing: MarketListing
    var price: String
    var refused: Bool
    var today: Int

    var body: some View {
        let key: String = listing.art.isEmpty ? (ArtLibrary.itemKey(group: "", familyKey: listing.family, seed: listing.id) ?? "") : ArtLibrary.vehicleCell(listing.art)
        let ago: Int = max(0, today - listing.postedDay)
        let agoText: String = ago == 0 ? "today" : (ago == 1 ? "yesterday" : "\(ago) days ago")
        return MarketCard(photoKey: key, badge: "Used", title: listing.title, detail: "\(listing.city) \u{00B7} \(agoText)", price: price,
                          seller: listing.sellerName, avatar: PlayerAvatar(name: listing.sellerName, isYou: false, size: 30),
                          note: refused ? "Not selling to you" : "")
    }
}
