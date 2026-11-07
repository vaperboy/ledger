import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Which picture a place gets: the premises photos in the asset catalogue (`AppPhotos`), by kind of place and floor area.
enum StayPhotos {
    /// Three pictures for each kind of place. The engine fixes the picture slot of a listing (`PlaceMarket.Offer.photoSlot`, varied by its
    /// index in the feed), so a place keeps its picture when it is rented.
    static func name(category: PlaceMarket.Category, slot: Int) -> String {
        let n: Int = ((slot % 3) + 3) % 3 + 1
        switch category {
        case .offices: return "airstay-office-\(n)"
        case .shops: return "airstay-shop-\(n)"
        case .retail: return "airstay-store-\(n)"
        }
    }
}

/// AirStay (Phone, red): places to rent for your companies. It merges what used to be "Premises" and "Where you work": listings sorted into
/// offices, shops and retail and storage, each with its monthly cost and kind of building, an information page with a Rent button, then
/// "Choose company" (which company rents it and pays; where the receipt is filed), the in-game confirmation, and "Rent confirmed".
/// The Rented tab holds the active rents, which can be moved to another company. The rules are the engine's (`PlaceMarket`, `CompanySetup`).
struct AirStayApp: View {
    private let P = OutsidePalette.airStay
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }

    private enum Step: Equatable { case explore, info, company, confirmed, reassign }
    private enum StayTab: String, CaseIterable, Hashable { case explore = "Explore", rented = "Rented" }

    @State private var step: Step = .explore
    @State private var tab: StayTab = .explore
    @State private var category: PlaceMarket.Category = .offices
    @State private var query = ""
    /// 0 = every company's places; else only the places this company could take.
    @State private var focusCompany = 0
    @State private var offer: PlaceMarket.Offer?
    @State private var buy = false
    @State private var payerID = 0
    @State private var receiptID = 0
    @State private var reference = ""
    @State private var movingFrom = 0
    @State private var targetID = 0
    @State private var pending: PendingAction?

    var body: some View {
        page
            .confirmAction($pending)
            .outsideScreen(P)
            .swipeBackEnabled(canStep: { step != .explore }, step: { back() })
            .safeAreaInset(edge: .top, spacing: 0) { band }
            .onAppear { take() }
            .onChange(of: store.appRequest) { _, _ in take() }
    }

    private var band: some View {
        ShopBand(title: "AirStay", glyph: Glyph.airStay, color: P.accent, onBack: { back() }, backLabel: step == .explore ? "Back to Phone" : "Back")
            .environment(\.outsidePalette, P)
    }

    @ViewBuilder private var page: some View {
        if let e = store.engine {
            switch step {
            case .explore:
                VStack(spacing: 0) {
                    tabPicker
                    SegmentPager(items: StayTab.allCases, selection: $tab) { (t: StayTab) in
                        if t == .explore { exploreView(e) } else { rentedView(e) }
                    }
                }
            case .info:
                if let o = offer { infoView(e, o) } else { Color.clear }
            case .company:
                if let o = offer { companyView(e, o) } else { Color.clear }
            case .confirmed:
                confirmedView(e)
            case .reassign:
                reassignView(e)
            }
        } else {
            Color.clear
        }
    }

    private func back() {
        switch step {
        case .explore: dismiss()
        case .info: step = .explore
        case .company: step = .info
        case .confirmed: step = .explore
        case .reassign: step = .explore
        }
    }

    /// A link from a company ("Premises", "Where you work") opens the app on that company.
    private func take() {
        guard let id = store.takeAirStayRequest() else { return }
        focusCompany = id
        step = .explore
        var hasPlace = false
        if id != 0, let e = store.engine, let r = e.rentedPlaces().first(where: { (p: PlaceMarket.Rented) -> Bool in p.companyID == id }) { hasPlace = !r.atHome }
        tab = hasPlace ? .rented : .explore
    }

    private func money(_ v: Double, _ companyID: Int) -> String {
        if let co = store.engine?.state.company(companyID) { return store.short(v, in: co) }
        return store.short(v)
    }

    private var tabPicker: some View {
        ShopTabs(items: StayTab.allCases, title: { (t: StayTab) -> String in t.rawValue }, selection: $tab,
                 identifier: { (t: StayTab) -> String in "stay-tab-\(t.rawValue)" },
                 badges: { (t: StayTab) -> Bool in t == .rented && !store.messageItemIDs(.airStay, companyID: nil).isEmpty })
            .accessibilityIdentifier("stay-tabs")
    }

    // MARK: Explore

    private func visibleOffers(_ e: GameEngine) -> [PlaceMarket.Offer] {
        let all: [PlaceMarket.Offer] = e.placeOffers()
        if focusCompany == 0 { return all }
        return all.filter { (o: PlaceMarket.Offer) -> Bool in
            e.placeCandidates(for: o).contains { (c: PlaceMarket.Candidate) -> Bool in c.companyID == focusCompany }
        }
    }

    private func matches(_ o: PlaceMarket.Offer) -> Bool {
        let q: String = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        let hay: String = (o.title + " " + o.listing.name + " " + o.cityName + " " + o.buildingType + " " + o.listing.landlord).lowercased()
        return hay.contains(q)
    }

    private func exploreView(_ e: GameEngine) -> some View {
        let all: [PlaceMarket.Offer] = visibleOffers(e)
        // Places are offered for the kinds of premises your companies use, so a kind none of them uses has no listings: only those with places show.
        let present: [PlaceMarket.Category] = PlaceMarket.Category.allCases.filter { (c: PlaceMarket.Category) -> Bool in all.contains { (o: PlaceMarket.Offer) -> Bool in o.category == c } }
        let cat: PlaceMarket.Category = present.contains(category) ? category : (present.first ?? category)
        let shown: [PlaceMarket.Offer] = all.filter { (o: PlaceMarket.Offer) -> Bool in o.category == cat && matches(o) }
        return ShopPage(spacing: Theme.Space.l) {
            ShopSearchField(prompt: "Search offices, shops or spaces", text: $query, identifier: "stay-search")
            if present.count > 1 { chips(present, cat) }
            focusNote(e)
            resultsLine(e, shown)
            listings(e, shown)
        }
        .accessibilityIdentifier("stay-explore")
    }

    /// How many places match, where they are and what they start at: the one line that matters before the photos.
    @ViewBuilder private func resultsLine(_ e: GameEngine, _ shown: [PlaceMarket.Offer]) -> some View {
        if !shown.isEmpty {
            let rents: [Double] = shown.compactMap { (o: PlaceMarket.Offer) -> Double? in e.premisesTerms(companyID: o.originCompanyID, listing: o.listing)?.monthlyRent }
            let cities: [String] = Array(Set(shown.map { (o: PlaceMarket.Offer) -> String in o.cityName })).sorted()
            let from: String = rents.min().map { (v: Double) -> String in " \u{00B7} from " + money(v, shown[0].originCompanyID) + " a month" } ?? ""
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(shown.count == 1 ? "1 place" : "\(shown.count) places").textStyle(.title)
                Text(cities.prefix(3).joined(separator: ", ") + (cities.count > 3 ? " and more" : "") + from).textStyle(.caption).lineLimit(2)
            }
            .padding(.top, Theme.Space.s)
        }
    }

    private func chipTitle(_ c: PlaceMarket.Category) -> String {
        switch c {
        case .offices: return "Offices"
        case .shops: return "Shops"
        case .retail: return "Retail"
        }
    }

    private func chipGlyph(_ c: PlaceMarket.Category) -> String {
        switch c {
        case .offices: return Glyph.building
        case .shops: return Glyph.techPro
        case .retail: return Glyph.opsBox
        }
    }

    /// The kinds of place as icon tabs with an underline under the chosen one, like a travel app's categories.
    private func chips(_ present: [PlaceMarket.Category], _ chosen: PlaceMarket.Category) -> some View {
        HStack(spacing: 0) {
            ForEach(present, id: \.self) { (c: PlaceMarket.Category) in
                let on: Bool = chosen == c
                Button { Haptics.choose(); category = c } label: {
                    VStack(spacing: Theme.Space.xs) {
                        LedgerGlyph(glyph: chipGlyph(c), size: Theme.Icon.medium, tint: on ? P.ink : P.inkFaint)
                        Text(chipTitle(c)).textStyle(.caption, tint: on ? P.ink : P.inkFaint, weight: on ? .semibold : .medium)
                        Rectangle().fill(on ? P.ink : Color.clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("stay-chip-\(c.rawValue)")
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private func focusNote(_ e: GameEngine) -> some View {
        if focusCompany != 0, let co = e.state.company(focusCompany) {
            HStack(spacing: Theme.Space.s) {
                Text("Places for \(co.name)").textStyle(.body, weight: .medium).lineLimit(2)
                Spacer(minLength: Theme.Space.s)
                Button("Show all") { focusCompany = 0 }.buttonStyle(TertiaryButtonStyle(size: .compact))
            }
            .padding(.leading, Theme.Space.m)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.accentWash))
        }
    }

    @ViewBuilder private func listings(_ e: GameEngine, _ shown: [PlaceMarket.Offer]) -> some View {
        if shown.isEmpty {
            ShopEmptyNote(text: emptyText(e), glyph: Glyph.building, buttonTitle: query.isEmpty ? nil : "Clear search") { query = "" }
        } else {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                ForEach(shown) { (o: PlaceMarket.Offer) in listingCard(e, o) }
            }
        }
    }

    private func emptyText(_ e: GameEngine) -> String {
        if e.placeOffers().isEmpty { return "None of your companies needs a place to rent. Home-based trades look here when they outgrow the kitchen table." }
        return "Nothing in this group matches. The list changes every half year."
    }

    private func subtitleLine(_ o: PlaceMarket.Offer) -> String {
        let loc: Double = o.listing.location
        let placeWord: String = loc > 1.03 ? "more passing trade" : (loc < 0.97 ? "less passing trade" : "normal location")
        let places: String = placesText(o).map { (t: String) -> String in " \u{00B7} " + t } ?? ""
        return "\(o.cityName) \u{00B7} \(o.buildingType) \u{00B7} \(Int(o.listing.squareMetres)) m²\(places) \u{00B7} \(placeWord)"
    }

    /// "6 office places": how many people the rental holds (nil when the trade's premises have no limit).
    private func placesText(_ o: PlaceMarket.Offer) -> String? {
        guard let e = store.engine, let n: Int = e.officeCapacity(forListing: o.listing, companyID: o.originCompanyID) else { return nil }
        return n == 1 ? "1 office place" : "\(n) office places"
    }

    private func photo(_ o: PlaceMarket.Offer) -> String {
        StayPhotos.name(category: o.category, slot: o.photoSlot)
    }

    /// The sheet picture for the kinds of place the places sheet has (hall, warehouse, hotel, clinic ...); empty keeps the catalogue photo.
    private func art(_ o: PlaceMarket.Offer) -> String {
        ArtLibrary.itemKey(group: "premises", familyKey: o.placeKind, seed: o.id + "#" + String(o.photoSlot)) ?? ""
    }

    private func listingCard(_ e: GameEngine, _ o: PlaceMarket.Offer) -> some View {
        let rent: Double = e.premisesTerms(companyID: o.originCompanyID, listing: o.listing)?.monthlyRent ?? 0
        return Button {
            Haptics.tap()
            offer = o
            buy = false
            step = .info
        } label: {
            ShopProductCard(photo: photo(o), glyph: Glyph.building, item: art(o), photoHeight: 220, title: o.title, lines: [subtitleLine(o)],
                            price: money(rent, o.originCompanyID), priceUnit: "a month")
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("stay-listing-\(o.id)")
    }

    // MARK: Information page

    private func infoView(_ e: GameEngine, _ o: PlaceMarket.Offer) -> some View {
        let t: CompanySetup.PremisesTerms? = e.premisesTerms(companyID: o.originCompanyID, listing: o.listing)
        let rent: Double = t?.monthlyRent ?? 0
        return ShopPage {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ShopPhoto(name: photo(o), glyph: Glyph.building, height: 260, item: art(o))
                ShopPageTitle(title: o.title, subtitle: "\(o.buildingType) in \(o.cityName) \u{00B7} \(o.listing.landlord)")
                keyFacts(o)
            }
            factsSection(e, o, t)
            aboutSection(e, o)
            ownSpaceLine(e, o)
            if o.canBuy, let t { buyLine(e, o, t) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShopActionBar(left: {
                ShopPriceTag(value: money(rent, o.originCompanyID), caption: "a month")
            }, action: {
                Button("Rent") { goCompany(e, o, buying: false) }
                    .buttonStyle(ShopFilledButtonStyle())
                    .accessibilityIdentifier("stay-rent")
            })
            .environment(\.outsidePalette, P)
        }
    }

    /// Size, desks and passing trade side by side under the title.
    private func keyFacts(_ o: PlaceMarket.Offer) -> some View {
        let loc: Double = o.listing.location
        let locText: String = loc > 1.03 ? "Busy" : (loc < 0.97 ? "Quiet" : "Normal")
        var items: [KeyFigures.Item] = [KeyFigures.Item(label: "Floor area", value: "\(Int(o.listing.squareMetres)) m²")]
        if let n = store.engine?.officeCapacity(forListing: o.listing, companyID: o.originCompanyID) { items.append(KeyFigures.Item(label: "Desks", value: "\(n)")) }
        items.append(KeyFigures.Item(label: "Passing trade", value: locText))
        return FigureRow(items: items, columns: items.count, combineCells: true)
            .padding(.vertical, Theme.Space.m)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
    }

    private func factsSection(_ e: GameEngine, _ o: PlaceMarket.Offer, _ t: CompanySetup.PremisesTerms?) -> some View {
        let id: Int = o.originCompanyID
        let facts: [(label: String, value: String)] = [
            (label: "Deposit, returned when you leave", value: money(t?.deposit ?? 0, id)),
            (label: "Fit-out, paid once", value: money(t?.fitOut ?? 0, id))
        ]
        return ShopSection(title: "To move in") {
            ShopFacts(facts: facts, total: (label: "Due now", value: money((t?.deposit ?? 0) + (t?.fitOut ?? 0), id)))
        }
    }

    private func aboutSection(_ e: GameEngine, _ o: PlaceMarket.Offer) -> some View {
        let note: String = e.data.catalog.tables.premises[o.placeKind]?.note ?? ""
        return ShopSection(title: "About this place") {
            Text(note.isEmpty ? "Central places cost more and draw more passing trade; quiet ones are cheap. Moving gives the old deposit back." : note + " Moving gives the old deposit back.")
                .textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Room of this size free in a commercial building of yours in the same city (a franchise unit can start there, rent staying in the group).
    @ViewBuilder private func ownSpaceLine(_ e: GameEngine, _ o: PlaceMarket.Offer) -> some View {
        let free: [PremisesExtras.FreeSpace] = e.freeSpaceInYourBuildings(cityID: o.cityID, squareMetres: o.listing.squareMetres)
        if let f = free.first {
            ShopNote(title: "Space in your own building",
                     text: "\(f.name) has \(Int(f.freeSquareMetres)) m² free. A franchise unit can start there, and the rent stays in your group.")
        }
    }

    private func buyLine(_ e: GameEngine, _ o: PlaceMarket.Offer, _ t: CompanySetup.PremisesTerms) -> some View {
        let id: Int = o.originCompanyID
        return ShopNote(title: "Or buy it",
                        text: "\(money(t.purchasePrice, id)), with \(money(t.downPayment + t.fitOut, id)) now (down payment and fit-out) and a 15-year mortgage on the rest.",
                        actionTitle: "Buy instead", identifier: "stay-buy") { goCompany(e, o, buying: true) }
    }

    // MARK: Choose company

    private func goCompany(_ e: GameEngine, _ o: PlaceMarket.Offer, buying: Bool) {
        let cands: [PlaceMarket.Candidate] = e.placeCandidates(for: o)
        guard !cands.isEmpty else {
            Haptics.warning()
            store.show("None of your companies can take this place.", tone: "warn")
            return
        }
        buy = buying
        let ok: [PlaceMarket.Candidate] = cands.filter { (c: PlaceMarket.Candidate) -> Bool in buying ? c.canBuy : c.canRent }
        let preferred: PlaceMarket.Candidate? = ok.first { (c: PlaceMarket.Candidate) -> Bool in c.companyID == focusCompany } ?? ok.first
        payerID = (preferred ?? cands[0]).companyID
        receiptID = payerID
        step = .company
    }

    private func companyView(_ e: GameEngine, _ o: PlaceMarket.Offer) -> some View {
        let cands: [PlaceMarket.Candidate] = e.placeCandidates(for: o)
        let companies: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
        let chosen: PlaceMarket.Candidate? = cands.first { (c: PlaceMarket.Candidate) -> Bool in c.companyID == payerID }
        let canGo: Bool = chosen.map { (c: PlaceMarket.Candidate) -> Bool in buy ? c.canBuy : c.canRent } ?? false
        let now: Double = chosen.map { (c: PlaceMarket.Candidate) -> Double in buy ? c.upfrontBuy : c.upfrontRent } ?? 0
        return ShopPage {
            ShopHero(label: buy ? "Buy \(o.title)" : "Rent \(o.title)", value: money(now, payerID),
                     note: canGo ? "Due now to move in, paid by the company you choose" : "The chosen company cannot pay this", noteTint: canGo ? nil : P.loss)
            ShopSection(title: "Which company \(buy ? "buys" : "rents") it") {
                VStack(spacing: Theme.Space.xxs) {
                    ForEach(cands) { (c: PlaceMarket.Candidate) in candidateRow(c) }
                }
            }
            ShopReceiptPicker(companies: companies, selection: $receiptID, idPrefix: "stay")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShopBottomAction {
                Button("Continue") { askToConfirm(e, o) }
                    .buttonStyle(ShopFilledButtonStyle())
                    .disabled(!canGo)
                    .accessibilityIdentifier("stay-continue")
            }
            .environment(\.outsidePalette, P)
        }
    }

    private func candidateRow(_ c: PlaceMarket.Candidate) -> some View {
        let upfront: Double = buy ? c.upfrontBuy : c.upfrontRent
        let ok: Bool = buy ? c.canBuy : c.canRent
        var line: String = "Cash \(money(c.cash, c.companyID)) \u{00B7} \(money(c.monthlyRent, c.companyID)) a month"
        if !ok { line += " \u{00B7} needs \(money(max(0, upfront - c.cash), c.companyID)) more" }
        if ok && c.hasPlace { line += " \u{00B7} its present place is given up" }
        return ShopChoiceRow(title: c.name, subtitle: line, trailing: money(upfront, c.companyID), selected: payerID == c.companyID, enabled: ok,
                             identifier: "stay-company-\(c.companyID)") {
            payerID = c.companyID
            receiptID = c.companyID
        }
    }

    private func askToConfirm(_ e: GameEngine, _ o: PlaceMarket.Offer) {
        guard let c = e.placeCandidates(for: o).first(where: { (x: PlaceMarket.Candidate) -> Bool in x.companyID == payerID }),
              let co = e.state.company(payerID) else { return }
        let cur: Currency = e.currency(for: co)
        let isBuy: Bool = buy
        let upfront: Double = isBuy ? c.upfrontBuy : c.upfrontRent
        let id: Int = payerID
        let rid: Int = receiptID
        let place: PlaceMarket.Offer = o
        var message: String
        if isBuy {
            message = "\(cur.tidyShort(upfront)) leaves \(co.name) now (down payment and fit-out); a 15-year mortgage covers the rest. No rent. The team moves in this week."
        } else {
            message = "\(cur.tidyShort(upfront)) leaves \(co.name) now (deposit, returned when you leave, and fit-out). Then \(cur.tidyShort(c.monthlyRent)) a month in rent. The team moves in this week."
        }
        let risk: String = c.hasPlace ? "The place \(co.name) works in now is given up; its deposit comes back." : ""
        message = message.tidyMoney
        pending = PendingAction(title: (isBuy ? "Buy " : "Rent ") + o.title + "?", message: message, button: isBuy ? "Buy it" : "Rent it",
                                alwaysAsk: isBuy, amount: upfront, currency: cur, risk: risk, tone: .investment, icon: "building.2") {
            let r: PlaceMarket.RentOutcome? = store.act { $0.takePlace(companyID: id, offer: place, buy: isBuy, receiptCompanyID: rid) }
            switch r?.result {
            case .ok?:
                Haptics.success()
                reference = r?.reference ?? ""
                step = .confirmed
            case .notEnoughCash?:
                Haptics.warning()
                store.show("The company does not have enough cash for that.", tone: "warn")
            default:
                Haptics.warning()
                store.show("Not possible.", tone: "warn")
            }
        }
    }

    // MARK: Rent confirmed

    private func confirmedView(_ e: GameEngine) -> some View {
        let co: Company? = e.state.company(payerID)
        let place: PlaceMarket.Rented? = e.rentedPlaces().first { (r: PlaceMarket.Rented) -> Bool in r.companyID == payerID }
        let name: String = place?.placeName ?? offer?.title ?? "the place"
        let rent: String = place.map { (r: PlaceMarket.Rented) -> String in r.owned ? "Bought, no rent" : money(r.monthlyRent, payerID) + " a month" } ?? ""
        let receipt: String = e.state.company(receiptID)?.name ?? ""
        let facts: [(label: String, value: String)] = [
            (label: "Company", value: co?.name ?? ""),
            (label: "Place", value: name),
            (label: "Cost", value: rent),
            (label: "Receipt filed with", value: receipt),
            (label: "Reference", value: "#" + reference)
        ]
        let photoName: String = offer.map { (o: PlaceMarket.Offer) -> String in photo(o) } ?? "airstay-office-2"
        let photoItem: String = offer.map { (o: PlaceMarket.Offer) -> String in art(o) } ?? ""
        return ShopSuccess(title: "Rent confirmed", message: "\(co?.name ?? "The company") now works in \(name).", facts: facts,
                           primary: "View in Rented", secondary: "Back to Explore",
                           onPrimary: { tab = .rented; step = .explore }, onSecondary: { tab = .explore; step = .explore },
                           extra: { ShopPhoto(name: photoName, glyph: Glyph.building, height: 150, item: photoItem) })
    }

    // MARK: Rented (active rents)

    private func rentedView(_ e: GameEngine) -> some View {
        let list: [PlaceMarket.Rented] = e.rentedPlaces()
        let monthly: Double = list.filter { (r: PlaceMarket.Rented) -> Bool in !r.atHome && !r.owned }.reduce(0) { (s: Double, r: PlaceMarket.Rented) -> Double in s + r.monthlyRent }
        let places: Int = list.filter { (r: PlaceMarket.Rented) -> Bool in !r.atHome }.count
        let home: Int = list.count - places
        return ShopPage {
            if list.isEmpty {
                ShopHero(label: "Rented", value: "No places yet", note: "None of your companies rents a place.")
                Button("Explore places") { tab = .explore }.buttonStyle(TertiaryButtonStyle(size: .compact)).padding(.leading, -Theme.Space.s)
            } else {
                ShopHero(label: "Rent a month", value: store.short(monthly),
                         note: (places == 1 ? "1 place" : "\(places) places") + (home > 0 ? " \u{00B7} \(home) working from home" : ""))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, r: PlaceMarket.Rented) in
                        if n > 0 { Hairline() }
                        rentedBlock(e, r)
                    }
                }
            }
        }
        .accessibilityIdentifier("stay-rented")
    }

    private func rentedBlock(_ e: GameEngine, _ r: PlaceMarket.Rented) -> some View {
        let id: Int = r.companyID
        let fresh: [String] = store.messageItemIDs(.airStay, companyID: id)
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            if r.atHome {
                LedgerGlyph(glyph: Glyph.airStay, size: Theme.Icon.large, tint: P.inkSoft).frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.cardDeep))
            } else {
                ShopThumb(photo: StayPhotos.name(category: r.category, slot: r.photoSlot), glyph: Glyph.building, size: 56)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(r.atHome ? "Working from home" : r.placeName).textStyle(.headline).lineLimit(2)
                Text(rentedLine(r)).textStyle(.caption).lineLimit(2)
            }
            Spacer(minLength: Theme.Space.s)
            Text(r.atHome ? "No rent" : (r.owned ? "Owned" : money(r.monthlyRent, id))).textStyle(.headline, tint: r.atHome || r.owned ? P.inkSoft : nil, numeric: true).lineLimit(1)
            rentedActions(e, r, id)
        }
        .padding(.vertical, Theme.Space.m)
        .newGroupMarker(.airStay, fresh, style: .capsule, alignment: .topTrailing)
    }

    private func rentedLine(_ r: PlaceMarket.Rented) -> String {
        if r.atHome { return r.companyName }
        return "\(r.companyName) \u{00B7} \(Int(r.squareMetres)) m² \u{00B7} \(r.cityName)"
    }

    /// The row's actions in "…": find a place, move the lease, work from home.
    @ViewBuilder private func rentedActions(_ e: GameEngine, _ r: PlaceMarket.Rented, _ id: Int) -> some View {
        let canMove: Bool = !r.atHome && !r.owned && !e.placeTargets(from: id).isEmpty
        if r.atHome || canMove || (!r.atHome && r.isHomeTrade) {
            ShopMoreMenu(label: "Actions for \(r.companyName)", identifier: "stay-actions-\(id)") {
                if r.atHome {
                    Button("Find a place") { focusCompany = id; tab = .explore }
                }
                if canMove {
                    Button("Move to another company") { startReassign(e, id) }
                        .accessibilityIdentifier("stay-reassign-\(id)")
                }
                if !r.atHome && r.isHomeTrade {
                    Button("Work from home", role: .destructive) { askHome(e, id) }
                }
            }
        }
    }

    /// A home trade gives up its place: an owned place is sold and its mortgage paid off, a rented one returns the deposit (the old "Where you work" action).
    private func askHome(_ e: GameEngine, _ id: Int) {
        guard let co = e.state.company(id), let q = e.moveHomeQuote(companyID: id) else { return }
        let cur: Currency = e.currency(for: co)
        var msg: String
        if q.isOwned {
            msg = "The building is sold at today's value and the mortgage is paid off: \(cur.tidyShort(q.proceeds)) comes back to the company"
            msg += q.shortfall > 0 ? ", but the mortgage is more than the building is worth, so the company pays the \(cur.tidyShort(q.shortfall)) difference." : "."
        } else {
            msg = "The lease ends and the deposit of \(cur.tidyShort(q.proceeds)) comes back to the company. The fit-out you paid for is not refunded."
        }
        pending = PendingAction(title: "Work from home again?", message: msg + " Everyone works from home; a team of four or more loses morale and quality every week.",
                                button: "Move home", destructive: false, tone: .warning, icon: "house") {
            if store.act({ $0.giveUpPremises(companyID: id) }) == true {
                Haptics.success()
                store.show("Everyone works from home again.", tone: "n")
            } else {
                Haptics.warning()
                store.show("It could not be given up.", tone: "warn")
            }
        }
    }

    // MARK: Move a lease to another company

    private func startReassign(_ e: GameEngine, _ id: Int) {
        let targets: [PlaceMarket.Candidate] = e.placeTargets(from: id)
        guard !targets.isEmpty else { return }
        movingFrom = id
        targetID = (targets.first { (c: PlaceMarket.Candidate) -> Bool in c.canRent } ?? targets[0]).companyID
        receiptID = targetID
        step = .reassign
    }

    private func reassignView(_ e: GameEngine) -> some View {
        let targets: [PlaceMarket.Candidate] = e.placeTargets(from: movingFrom)
        let from: Company? = e.state.company(movingFrom)
        let chosen: PlaceMarket.Candidate? = targets.first { (c: PlaceMarket.Candidate) -> Bool in c.companyID == targetID }
        return ShopPage {
            ShopPageTitle(title: "Move this rent", subtitle: "Who takes over the lease from \(from?.name ?? "this company")? The deposit and the fit-out go with it.")
            VStack(spacing: Theme.Space.xxs) {
                ForEach(targets) { (c: PlaceMarket.Candidate) in
                    ShopChoiceRow(title: c.name, subtitle: "Cash \(money(c.cash, c.companyID)) \u{00B7} deposit \(money(c.upfrontRent, c.companyID)) moves" + (c.hasPlace ? " \u{00B7} its present place is given up" : ""),
                                  trailing: money(c.monthlyRent, c.companyID) + "/mo", selected: targetID == c.companyID, enabled: c.canRent,
                                  identifier: "stay-target-\(c.companyID)") { targetID = c.companyID }
                }
            }
            PrimaryAction(title: "Move the lease", blockedReason: (chosen?.canRent ?? false) ? nil : "Choose a company with the cash for the deposit.",
                          identifier: "stay-move") { askMove(e) }
        }
    }

    private func askMove(_ e: GameEngine) {
        guard let from = e.state.company(movingFrom), let to = e.state.company(targetID),
              let c = e.placeTargets(from: movingFrom).first(where: { (x: PlaceMarket.Candidate) -> Bool in x.companyID == targetID }) else { return }
        let cur: Currency = e.currency(for: to)
        let a: Int = movingFrom
        let b: Int = targetID
        pending = PendingAction(title: "Move the lease to \(to.name)?",
                                message: "\(to.name) pays the \(cur.tidyShort(c.upfrontRent)) deposit and takes over the rent of \(cur.tidyShort(c.monthlyRent)) a month; \(from.name) gets its deposit back and is left without a place.".tidyMoney,
                                button: "Move it", alwaysAsk: true, amount: c.upfrontRent, currency: cur,
                                risk: "\(from.name) has no place to work in until you rent another one.", tone: .investment, icon: "arrow.left.arrow.right") {
            switch store.act({ $0.reassignPlace(from: a, to: b) }) {
            case .ok?:
                Haptics.success()
                store.show("\(to.name) took over the lease.", tone: "good")
                tab = .rented
                step = .explore
            case .notEnoughCash?:
                Haptics.warning()
                store.show("\(to.name) does not have enough cash for the deposit.", tone: "warn")
            default:
                Haptics.warning()
                store.show("The lease could not be moved.", tone: "warn")
            }
        }
    }
}
