import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Marketplace (Phone, warm teal): every used item for sale from private sellers. A grid with filters and a sort in a fixed header, a product
/// page per listing and a price talk in a centred popup (`MarketplaceListing.swift`). The engine owns listings, sellers and prices.
struct MarketplaceApp: View {
    private let P = OutsidePalette.marketplace
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss

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

    // MARK: Chrome

    private var band: some View {
        ShopBand(title: "Marketplace", glyph: Glyph.marketplace, color: P.accent, onBack: { back() }, backLabel: openID == nil ? "Back to Phone" : "Back")
            .environment(\.outsidePalette, P)
    }

    private func back() {
        if openID != nil { openID = nil } else { dismiss() }
    }

    @ViewBuilder private var header: some View {
        if openID == nil, let e = store.engine, let co = current(e) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    companyMenu(e, co)
                    Spacer(minLength: 8)
                    sortMenu
                }
                filterChips
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(P.ground)
        }
    }

    private func companyMenu(_ e: GameEngine, _ co: Company) -> some View {
        let all: [Company] = shoppers(e)
        return Menu {
            ForEach(all, id: \.id) { (c: Company) in
                Button(c.name) { companyID = c.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Buying for").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                Text(co.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(P.ink).lineLimit(1)
                if all.count > 1 { Text("\u{25BE}").font(.system(size: 12)).foregroundStyle(P.inkFaint) }
            }
        }
        .disabled(all.count < 2)
        .accessibilityIdentifier("mk-company")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(Sort.allCases, id: \.self) { (s: Sort) in
                Button(s.rawValue) { sort = s }
            }
        } label: {
            HStack(spacing: 4) {
                Text(sort.rawValue).font(.system(size: 13, weight: .semibold)).foregroundStyle(P.accent).lineLimit(1)
                Text("\u{25BE}").font(.system(size: 12)).foregroundStyle(P.accent)
            }
        }
        .accessibilityIdentifier("mk-sort")
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { (f: Filter) in
                    ShopChip(title: f.rawValue, selected: filter == f) { filter = f }
                        .accessibilityIdentifier("mk-filter-\(f.rawValue)")
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Data

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

    // MARK: Pages

    @ViewBuilder private var page: some View {
        if let e = store.engine, let co = current(e) {
            let all: [MarketListing] = MarketplaceBridge.listings(e, companyID: co.id)
            let cur: Currency = e.currency(for: co)
            if let id = openID, let l = all.first(where: { (x: MarketListing) -> Bool in x.id == id }) {
                MarketplaceListingPage(listing: l, cur: cur, companyID: co.id, today: e.state.day, refusedHere: refusedIDs.contains(l.id),
                                       onRefused: { (rid: String) in _ = refusedIDs.insert(rid) }, onBought: { openID = nil })
                    .id(l.id + String(co.id))
            } else {
                gridPage(visible(all), cur, co)
            }
        } else {
            ShopEmptyNote(text: "Nothing to buy for. Start a company first.")
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func gridPage(_ list: [MarketListing], _ cur: Currency, _ co: Company) -> some View {
        let cols: [GridItem] = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return ShopScroll {
            VStack(alignment: .leading, spacing: 12) {
                ShopHeading(text: "For sale", trailing: list.count == 1 ? "1 listing" : "\(list.count) listings")
                if list.isEmpty {
                    ShopEmptyNote(text: "Nothing matches. New listings appear as the days go by.")
                }
                LazyVGrid(columns: cols, spacing: 12) {
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
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
        }
        .accessibilityIdentifier("mk-grid")
    }
}

/// One listing in the grid: picture, title, a line of blurb, the city and the asking price.
struct MarketplaceTile: View {
    @Environment(\.outsidePalette) private var P
    var listing: MarketListing
    var price: String
    var refused: Bool

    var body: some View {
        let key: String = ArtLibrary.itemKey(group: "", familyKey: listing.family, seed: listing.id) ?? ""
        return VStack(alignment: .leading, spacing: 5) {
            ShopPhoto(name: "", glyph: Glyph.marketplace, height: 96, item: key)
            Text(listing.title).font(.system(size: 15, weight: .bold)).foregroundStyle(P.ink).multilineTextAlignment(.leading).lineLimit(2)
            Text(listing.blurb).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).multilineTextAlignment(.leading).lineLimit(2)
            Text(listing.city).font(.system(size: 12)).foregroundStyle(P.inkFaint).lineLimit(1)
            Text(price).font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(P.accent2).lineLimit(1).minimumScaleFactor(0.7)
            if refused {
                Text("Not selling to you").font(.system(size: 12, weight: .semibold)).foregroundStyle(P.caution)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
