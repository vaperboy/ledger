import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The plain words and small parts the supply market screens share.
enum SupplyMarketWords {
    static func price(_ tier: Int) -> String { ["Under market price", "Market price", "Above market price"][min(2, max(0, tier))] }
    static func quality(_ tier: Int) -> String { SupplyMarketCatalogue.qualityTiers[min(2, max(0, tier))] + " quality" }
    static func lead(_ days: Int) -> String { days <= 0 ? "Continuous" : days == 1 ? "Next day" : "\(days) days lead" }
    static func terms(_ days: Int) -> String { days == 0 ? "Paid on delivery" : "Paid after \(days) days" }
    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    static func tint(_ w: DeliveryWord) -> Color {
        switch w {
        case .reliable: return Theme.gain
        case .mostlyReliable: return Theme.inkSoft
        case .unproven: return Theme.caution
        case .struggling: return Theme.loss
        }
    }
}

/// A change in points of share: a green up arrow when it improved, a red down arrow when it slipped, nothing when flat or unknown.
struct TrendArrow: View {
    var delta: Double?

    var body: some View {
        if let d = delta, abs(d) >= 0.5 {
            HStack(spacing: Theme.Space.xs) {
                StockArrow(up: d > 0, good: d > 0)
                Text("\(Int(abs(d).rounded())) pts").textStyle(.caption, tint: d > 0 ? Theme.gain : Theme.loss, numeric: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(d > 0 ? "Up \(Int(abs(d).rounded())) points" : "Down \(Int(abs(d).rounded())) points")
        }
    }
}

/// What a buyer sees of a supplier: the word, then the plain history behind it.
struct DeliveryRecordView: View {
    var record: DeliveryRecord

    var body: some View {
        let word: DeliveryWord = SupplyRecordRules.word(record)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Chip(text: word.rawValue, tint: SupplyMarketWords.tint(word))
                Spacer(minLength: 0)
            }
            if word == .unproven {
                Text("Too little history to judge yet.").textStyle(.caption, tint: Theme.inkSoft)
            }
            line("Promised units delivered", record.ordersTotal == 0 ? "No orders yet" : SupplyMarketWords.percent(record.deliveredShare), record.deliveredTrend)
            line("Orders on time", record.ordersTotal == 0 ? "No orders yet" : SupplyMarketWords.percent(record.onTimeShare), record.onTimeTrend)
            line("Complaints", record.complaints == 0 ? "None" : "\(record.complaints)", nil)
            line("Disputes", record.disputes == 0 ? "None" : "\(record.disputes)", nil)
            line("Price changes after signing", record.priceChanges == 0 ? "None" : "\(record.priceChanges)", nil)
            line("Weeks trading", "\(record.weeksTrading)", nil)
        }
    }

    private func line(_ label: String, _ value: String, _ trend: Double?) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(label).textStyle(.caption, tint: Theme.inkSoft)
            Spacer(minLength: Theme.Space.s)
            TrendArrow(delta: trend)
            Text(value).textStyle(.caption, numeric: true)
        }
    }
}

/// One supplier listing in a list: who, the record in a word, what is offered, the limit while new, and why it cannot be used when it cannot.
struct SupplyListingCard: View {
    var listing: SupplyListing
    var known: Bool
    var availability: SupplyAvailability
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(listing.ownerName).textStyle(.headline).lineLimit(1)
                    if known { Chip(text: "Known supplier", tint: Theme.gold) }
                    else if listing.isFriend { Chip(text: "Friend", tint: Theme.gold) }
                    Spacer(minLength: Theme.Space.s)
                    Chip(text: listing.word.rawValue, tint: SupplyMarketWords.tint(listing.word))
                }
                Text("\(listing.companyName) · \(listing.tradeName) · \(listing.city)").textStyle(.caption, tint: Theme.inkSoft).lineLimit(1)
                Text("\(listing.lineName) · \(SupplyMarketWords.price(listing.priceTier)) · \(SupplyMarketWords.quality(listing.qualityTier))")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                Text("\(SupplyGuards.effectiveCapacity(listing)) units/week · \(SupplyMarketWords.lead(listing.leadDays)) · minimum \(listing.minOrder) · \(SupplyMarketWords.terms(listing.termsDays))")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                if let limit = SupplyGuards.limitText(listing) { Text(limit).textStyle(.caption, tint: Theme.caution) }
                if let why = availability.message, availability != .available {
                    Text(why).textStyle(.caption, tint: Theme.loss)
                }
            }
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The units a week and the button that signs a contract with a listing; reads what changes against the market supplier in money, with arrows.
struct SupplySignBlock: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var companyID: Int
    var lineID: String
    var lineTitle: String
    var listing: SupplyListing
    var weeklyMarketSpend: Double
    var currency: Currency
    var onSigned: () -> Void
    @State private var units: Double = 0
    @State private var message: String?

    private var room: Int { max(0, SupplyGuards.effectiveCapacity(listing) - listing.committedUnits) }

    var body: some View {
        let today: Int = store.engine.map { SupplyMarketStore.today($0) } ?? 0
        let availability: SupplyAvailability = SupplyGuards.availability(listing, buyerLinkKeys: market.service.buyerLinkKeys, units: max(listing.minOrder, Int(units)), today: today)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if room < listing.minOrder {
                Text("Fully booked this week.").popupText(.risk)
            } else if isBlocked(availability) {
                Text(availability.message ?? "").popupText(.risk)
            } else {
                HStack {
                    Text("Units a week").popupText(.rowLabel)
                    Spacer(minLength: Theme.Space.s)
                    Text("\(Int(units))").popupText(.rowValue)
                    StepperPill(value: $units, range: Double(listing.minOrder)...Double(max(listing.minOrder, room)), step: 5)
                }
                if weeklyMarketSpend > 0 {
                    let saving: Double = weeklyMarketSpend * (1 - listing.priceFactor)
                    HStack(spacing: Theme.Space.s) {
                        Text("Against the market supplier").popupText(.caption)
                        Spacer(minLength: 0)
                        ArrowAmount(gain: saving, amount: abs(saving), format: { (v: Double) -> String in currency.tidyShort(v) + " a week" }, step: .caption)
                    }
                }
                if let message { Text(message).popupText(.risk) }
                PopupOptionButton(title: "Use \(listing.ownerName)", highlighted: true) { sign() }
                Text("If they stop supplying, \(lineTitle.lowercased()) goes back to the House supplier at market price.").popupText(.caption)
            }
        }
        .onAppear { if units < Double(listing.minOrder) { units = Double(min(max(listing.minOrder, 20), max(listing.minOrder, room))) } }
    }

    private func isBlocked(_ a: SupplyAvailability) -> Bool {
        if case .notOffered = a { return true }
        return a == .linkedAccount
    }

    private func sign() {
        guard let e = store.engine else { return }
        let r: SupplySignResult = market.service.sign(buyerCompanyID: companyID, lineID: lineID, listingID: listing.id, unitsPerWeek: Int(units),
                                                      weeklyMarketSpend: weeklyMarketSpend, today: SupplyMarketStore.today(e))
        switch r {
        case .signed:
            Haptics.success()
            store.outcome(chosen: "\(listing.ownerName) for \(lineTitle)", result: "\(listing.ownerName) now supplies \(lineTitle.lowercased()), \(Int(units)) units a week. The House supplier is the backup.")
            onSigned()
        case .refused(let why):
            Haptics.warning()
            message = why
        }
    }
}

/// One listing in a popup: the owner, the full delivery record, the offer, and the way to sign. The supplier page opens from here.
struct SupplyListingPopup: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var companyID: Int
    var lineID: String
    var listingID: String
    var onProfile: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let l = market.service.listing(listingID),
           let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == lineID }) {
            let known: Bool = market.service.knownSuppliers().contains(l.ownerID)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("\(l.companyName) · \(l.tradeName) · \(l.city)").popupText(.subtitle)
                Text("\(l.lineName) · \(SupplyMarketWords.price(l.priceTier)) · \(SupplyMarketWords.quality(l.qualityTier))").popupText(.body)
                Text("\(SupplyGuards.effectiveCapacity(l)) units/week · \(SupplyMarketWords.lead(l.leadDays)) · minimum \(l.minOrder) · \(SupplyMarketWords.terms(l.termsDays))").popupText(.caption)
                if let limit = SupplyGuards.limitText(l) { Text(limit).popupText(.risk) }
                Hairline()
                Text("Delivery record").capsLabel(Theme.ivoryFaint)
                DeliveryRecordView(record: l.record)
                Hairline()
                SupplySignBlock(companyID: companyID, lineID: lineID, lineTitle: row.title, listing: l, weeklyMarketSpend: row.weekly ?? 0, currency: e.currency(for: co), onSigned: onClose)
                HStack(spacing: Theme.Space.s) {
                    QuietButton(title: known ? "Remove from known suppliers" : "Save as known supplier", fullWidth: true) { market.service.setKnown(ownerID: l.ownerID, !known) }
                    QuietButton(title: "Supplier profile", fullWidth: true) { onProfile(l.ownerID) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .centerSheetTitle(l.ownerName)
        } else {
            Text("That offer is gone.").popupText(.caption)
        }
    }
}

/// A supplier's page: who they are, their listings with records, and the way into the owner's profile (`SupplierOwnerProfileHook`).
struct SupplierProfileScreen: View {
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var ownerID: String
    @State private var showOwner = false

    var body: some View {
        let p: SupplierProfile? = market.service.profile(ownerID: ownerID)
        ScrollScreen(spacing: Theme.Space.xl) {
            if let p {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(p.ownerName).textStyle(.title)
                    Text("Profile code \(p.profileCode)" + (p.isFriend ? " · Friend" : "")).textStyle(.caption, tint: Theme.inkSoft)
                    QuietButton(title: market.service.knownSuppliers().contains(p.ownerID) ? "Remove from known suppliers" : "Save as known supplier") {
                        market.service.setKnown(ownerID: p.ownerID, !market.service.knownSuppliers().contains(p.ownerID))
                    }
                    ownerLink(p)
                }
                .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
                if p.listings.isEmpty {
                    EmptyState(glyph: Glyph.suppliers, title: "Not supplying now", message: "This player has no open offers.")
                }
                ForEach(p.listings) { (l: SupplyListing) in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(l.lineName).capsLabel(Theme.ivoryFaint)
                        Text("\(l.companyName) · \(l.tradeName) · \(l.city)").textStyle(.caption, tint: Theme.inkSoft)
                        Text("\(SupplyMarketWords.price(l.priceTier)) · \(SupplyMarketWords.quality(l.qualityTier)) · \(SupplyGuards.effectiveCapacity(l)) units/week · minimum \(l.minOrder)")
                            .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        if let limit = SupplyGuards.limitText(l) { Text(limit).textStyle(.caption, tint: Theme.caution) }
                        DeliveryRecordView(record: l.record)
                    }
                    .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
                }
            } else {
                EmptyState(glyph: Glyph.suppliers, title: "This supplier is gone")
            }
        }
        .appScreen(title: "Supplier", subtitle: p?.ownerName ?? "", tab: .company)
        .navigationDestination(isPresented: $showOwner) {
            if let p, let dest = SupplierOwnerProfileHook.destination { dest(p.profileCode) }
        }
    }

    @ViewBuilder private func ownerLink(_ p: SupplierProfile) -> some View {
        if SupplierOwnerProfileHook.destination != nil {
            LedgerRow(leading: .glyph(Glyph.person), leadingTint: Theme.inkSoft, title: "Open \(p.ownerName)'s profile", identifier: "supplier-owner-profile") { showOwner = true }
        } else {
            Text("The player's profile page opens here once online profiles are connected.").textStyle(.caption, tint: Theme.inkFaint)
        }
    }
}

/// Every offer for one purchase with search and filters.
struct SupplyBrowseScreen: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var companyID: Int
    var lineID: String

    @State private var query = ""
    @State private var priceFilter = -1
    @State private var qualityFilter = -1
    @State private var regionFilter = ""
    @State private var recordFilter = 0
    @State private var knownOnly = false
    @State private var opened: ListingPick?
    @State private var profile: ProfilePick?

    struct ListingPick: Identifiable, Equatable { var id: String }
    struct ProfilePick: Identifiable, Hashable { var id: String }

    private static let recordFilters: [String] = ["Any record", "Not struggling", "Reliable only"]

    var body: some View {
        if let e = store.engine, e.state.company(companyID) != nil {
            let today: Int = SupplyMarketStore.today(e)
            let known: Set<String> = market.service.knownSuppliers()
            let all: [SupplyListing] = market.service.listings(lineID: lineID)
            let shown: [SupplyListing] = all.filter { matches($0, known) }.sorted(by: SupplyRecordRules.wellKnownOrder)
            ScrollScreen(spacing: Theme.Space.m) {
                AcctSearchField(text: $query, prompt: "Name, friend, profile code, company", identifier: "supply-search")
                filters(all, known)
                if shown.isEmpty {
                    EmptyState(glyph: Glyph.suppliers, title: "No supplier matches", message: "Try fewer filters or a different search.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { (n: Int, l: SupplyListing) in
                            if n > 0 { Hairline() }
                            SupplyListingCard(listing: l, known: known.contains(l.ownerID),
                                              availability: SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: l.minOrder, today: today)) { opened = ListingPick(id: l.id) }
                        }
                    }
                    .padding(.horizontal, Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
                }
            }
            .appScreen(title: "Browse suppliers", subtitle: SupplyMarketCatalogue.line(lineID)?.name ?? "", tab: .company)
            .centerSheet(item: $opened, category: .medium, tone: .info) { (p: ListingPick) in
                SupplyListingPopup(companyID: companyID, lineID: lineID, listingID: p.id, onProfile: { (owner: String) in opened = nil; profile = ProfilePick(id: owner) }, onClose: { opened = nil })
                    .environmentObject(store)
            }
            .navigationDestination(item: $profile) { (p: ProfilePick) in SupplierProfileScreen(ownerID: p.id).environmentObject(store) }
        }
    }

    private func matches(_ l: SupplyListing, _ known: Set<String>) -> Bool {
        if knownOnly && !known.contains(l.ownerID) { return false }
        if priceFilter >= 0 && l.priceTier != priceFilter { return false }
        if qualityFilter >= 0 && l.qualityTier != qualityFilter { return false }
        if !regionFilter.isEmpty && l.region != regionFilter { return false }
        if recordFilter == 1 && l.word == .struggling { return false }
        if recordFilter == 2 && l.word != .reliable { return false }
        let q: String = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        if l.ownerName.lowercased().contains(q) || l.companyName.lowercased().contains(q) || l.profileCode.lowercased().contains(q) { return true }
        if q == "friend" || q == "friends" { return l.isFriend }
        if q.hasPrefix("known") { return known.contains(l.ownerID) }
        return false
    }

    private func filters(_ all: [SupplyListing], _ known: Set<String>) -> some View {
        let regions: [String] = Array(Set(all.map { $0.region })).sorted()
        return ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                menu("Price", priceFilter < 0 ? "Any" : SupplyMarketCatalogue.priceTiers[priceFilter]) {
                    Button("Any") { priceFilter = -1 }
                    ForEach(0..<3, id: \.self) { (i: Int) in Button(SupplyMarketCatalogue.priceTiers[i]) { priceFilter = i } }
                }
                menu("Quality", qualityFilter < 0 ? "Any" : SupplyMarketCatalogue.qualityTiers[qualityFilter]) {
                    Button("Any") { qualityFilter = -1 }
                    ForEach(0..<3, id: \.self) { (i: Int) in Button(SupplyMarketCatalogue.qualityTiers[i]) { qualityFilter = i } }
                }
                menu("Region", regionFilter.isEmpty ? "Any" : regionFilter) {
                    Button("Any") { regionFilter = "" }
                    ForEach(regions, id: \.self) { (r: String) in Button(r) { regionFilter = r } }
                }
                menu("Record", Self.recordFilters[recordFilter]) {
                    ForEach(0..<3, id: \.self) { (i: Int) in Button(Self.recordFilters[i]) { recordFilter = i } }
                }
                Button { knownOnly.toggle(); Haptics.tap() } label: {
                    Chip(text: "Known only", tint: knownOnly ? Theme.gold : Theme.inkSoft).padding(.horizontal, Theme.Space.s).frame(minHeight: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func menu<M: View>(_ title: String, _ value: String, @ViewBuilder _ items: () -> M) -> some View {
        Menu {
            items()
        } label: {
            Chip(text: "\(title): \(value)", tint: Theme.inkSoft).padding(.horizontal, Theme.Space.s).frame(minHeight: 36)
        }
    }
}
