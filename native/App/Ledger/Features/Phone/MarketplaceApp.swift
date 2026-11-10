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
    }

    @State private var companyID = 0
    @State private var filter: Filter = .all
    @State private var sort: Sort = .newest
    @State private var openID: String? = nil
    @State private var refusedIDs: Set<String> = []

    var body: some View {
        page
            .outsideScreen(P)
            .swipeBackEnabled(canStep: { openID != nil }, step: { openID = nil })
            .safeAreaInset(edge: .top, spacing: 0) { VStack(spacing: 0) { band; header } }
    }

    private var band: some View {
        ShopBand(title: "Marketplace", glyph: Glyph.marketplace, color: P.accent, onBack: { back() }, backLabel: openID == nil ? "Back to Phone" : "Back")
            .environment(\.outsidePalette, P)
    }

    private func back() {
        if openID != nil { openID = nil } else { dismiss() }
    }

    @ViewBuilder private var header: some View {
        if openID == nil, let e = store.engine, let co = current(e) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ShopChipRow {
                    ForEach(Filter.allCases, id: \.self) { (f: Filter) in
                        ShopChip(title: f.rawValue, selected: filter == f) { filter = f }
                            .accessibilityIdentifier("mk-filter-\(f.rawValue)")
                    }
                }
                lotLine(e, co)
            }
            .padding(.horizontal, Theme.Space.page).padding(.bottom, Theme.Space.xs)
            .frame(maxWidth: ShopMetrics.maxWidth)
            .frame(maxWidth: .infinity)
            .background(P.page)
            .overlay(alignment: .bottom) { Hairline() }
            .environment(\.outsidePalette, P)
        }
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

    private var sortMenu: some View {
        Menu {
            ForEach(Sort.allCases, id: \.self) { (s: Sort) in
                Button { Haptics.choose(); sort = s } label: {
                    if s == sort { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) }
                }
            }
        } label: {
            ShopMenuLabel(text: sort.rawValue)
        }
        .accessibilityIdentifier("mk-sort")
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

    private func visible(_ all: [MarketListing]) -> [MarketListing] {
        let kept: [MarketListing] = filter == .all ? all : all.filter { (l: MarketListing) -> Bool in Self.category(l.family) == filter }
        return kept.sorted { (a: MarketListing, b: MarketListing) -> Bool in
            switch sort {
            case .newest: return a.postedDay != b.postedDay ? a.postedDay > b.postedDay : a.title < b.title
            case .low: return a.askingPrice != b.askingPrice ? a.askingPrice < b.askingPrice : a.title < b.title
            case .high: return a.askingPrice != b.askingPrice ? a.askingPrice > b.askingPrice : a.title < b.title
            }
        }
    }

    @ViewBuilder private var page: some View {
        if let e = store.engine, let co = current(e) {
            let all: [MarketListing] = MarketplaceBridge.listings(e, companyID: co.id)
            let cur: Currency = e.currency(for: co)
            if let id = openID, let l = all.first(where: { (x: MarketListing) -> Bool in x.id == id }) {
                MarketplaceListingPage(listing: l, cur: cur, companyID: co.id, today: e.state.day, refusedHere: refusedIDs.contains(l.id),
                                       onRefused: { (rid: String) in _ = refusedIDs.insert(rid) }, onBought: { openID = nil })
                    .id(l.id + String(co.id))
            } else {
                gridPage(e, visible(all), cur, co)
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
                sortMenu
            }
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
                        MarketplaceTile(listing: l, price: cur.tidyShort(l.askingPrice), refused: refusedIDs.contains(l.id))
                            .newMarker(.marketplace, "l" + l.id, style: .capsule, alignment: .topLeading)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("mk-listing-\(l.id)")
                }
            }
        }
        .accessibilityIdentifier("mk-grid")
    }
}

struct MarketplaceTile: View {
    @Environment(\.outsidePalette) private var P
    var listing: MarketListing
    var price: String
    var refused: Bool

    var body: some View {
        let key: String = ArtLibrary.itemKey(group: "", familyKey: listing.family, seed: listing.id) ?? ""
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            ShopPhoto(name: "", glyph: Glyph.marketplace, height: 150, cornerRadius: Theme.Radius.medium, item: key)
                .padding(.bottom, Theme.Space.s)
            Text(price.tidyText).textStyle(.figure, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7)
            Text(listing.title.tidyText).textStyle(.body).lineLimit(2).multilineTextAlignment(.leading)
            Text(listing.city.tidyText).textStyle(.caption, tint: P.inkFaint).lineLimit(1)
            if refused { Text("Not selling to you").textStyle(.caption, tint: P.caution, weight: .medium) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}
