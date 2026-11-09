import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The four ways to choose a player supplier for a purchase, in the offers popup: Best price (every offer ranked by landed cost: price plus freight and
/// customs), Well known (best records and volume), Random pick (drawn from the fair-price reliable pool, one new draw allowed) and Browse (search and
/// filters on their own page, friends included). The House suppliers below stay as the backup and the automatic fallback. Only offers the company's
/// trade really uses are shown.
struct SupplyWaysBlock: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var companyID: Int
    var row: SupplyRow
    var currency: Currency
    var onBrowse: () -> Void

    @State private var way = 0
    @State private var drawn: SupplyListing?
    @State private var drawCount = 0
    @State private var chosen: String?

    private static let ways: [Int] = [0, 1, 2, 3]
    private static let names: [String] = ["Best price", "Well known", "Random pick", "Browse"]

    var body: some View {
        if let e = store.engine {
            let today: Int = SupplyMarketStore.today(e)
            let known: Set<String> = market.service.knownSuppliers()
            let all: [SupplyListing] = market.service.listings(lineID: row.id)
            let wanted: [SupplyListing] = all.filter { e.playerSupplyAllowed(companyID: companyID, listing: $0) }
            let landed: [String: SupplyLanded.Row] = SupplyLandedBasis.lookup(SupplyLandedBasis.rows(e, companyID: companyID, listings: wanted, weekly: row.weekly))
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Other players").capsLabel(Theme.ivoryFaint)
                if let c = market.service.contract(buyerCompanyID: companyID, lineID: row.id) { current(c) }
                SegmentedPill(items: Self.ways, title: { (i: Int) -> String in Self.names[i] }, selection: $way)
                switch way {
                case 0: bestPrice(wanted, landed, today, known)
                case 1: wellKnown(wanted, landed, today, known)
                case 2: random(all, wanted, landed, today, known)
                default: browse()
                }
            }
        }
    }

    private func current(_ c: SupplyContract) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("Supplied by \(c.supplierName)").popupText(.body)
                Spacer(minLength: Theme.Space.s)
                Chip(text: "Player supplier", tint: Theme.gold)
            }
            Text("\(c.unitsPerWeek) units a week.").popupText(.caption)
            QuietButton(title: "End and use the House supplier", fullWidth: true) {
                market.end(store, companyID: companyID, lineID: row.id)
                Haptics.tap()
            }
        }
    }

    private func units(_ l: SupplyListing) -> Int { max(l.minOrder, SupplyLandedBasis.compareUnits) }

    /// Every usable offer, cheapest landed cost first: a far supplier with a low price can cost more than a near one.
    @ViewBuilder private func bestPrice(_ wanted: [SupplyListing], _ landed: [String: SupplyLanded.Row], _ today: Int, _ known: Set<String>) -> some View {
        let usable: [SupplyListing] = wanted.filter { SupplyGuards.availability($0, buyerLinkKeys: market.service.buyerLinkKeys, units: units($0), today: today) == .available }
        let ranked: [SupplyListing] = Array(usable.sorted { (landed[$0.id]?.landedPerUnit ?? 0) < (landed[$1.id]?.landedPerUnit ?? 0) }.prefix(3))
        Text("Ranked by what a unit costs delivered: price, freight and customs.").popupText(.caption)
        if ranked.isEmpty { Text("No player offers this yet.").popupText(.caption) }
        ForEach(ranked) { (l: SupplyListing) in candidate(l, landed, today, known) }
    }

    @ViewBuilder private func wellKnown(_ wanted: [SupplyListing], _ landed: [String: SupplyLanded.Row], _ today: Int, _ known: Set<String>) -> some View {
        let ids: Set<String> = Set(wanted.map { $0.id })
        let top: [SupplyListing] = Array(market.service.wellKnown(lineID: row.id, units: 1, today: today).filter { ids.contains($0.id) }.prefix(3))
        Text("The best records and the most delivered.").popupText(.caption)
        if top.isEmpty { Text("No player supplies this yet.").popupText(.caption) }
        ForEach(top) { (l: SupplyListing) in candidate(l, landed, today, known) }
    }

    @ViewBuilder private func random(_ all: [SupplyListing], _ wanted: [SupplyListing], _ landed: [String: SupplyLanded.Row], _ today: Int, _ known: Set<String>) -> some View {
        Text("A supplier drawn from fairly priced, reliable ones, so newcomers get orders too.").popupText(.caption)
        if let l = drawn {
            candidate(l, landed, today, known)
            if drawCount < 2 {
                QuietButton(title: "Draw again (once)", fullWidth: true) { draw(all, wanted, today) }
            } else {
                Text("That was your one new draw.").popupText(.caption)
            }
        } else {
            QuietButton(title: "Draw a supplier", fullWidth: true) { draw(all, wanted, today) }
        }
    }

    private func browse() -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Search by name, friend, profile code or company, save known suppliers, and filter by price, quality, region and record.").popupText(.caption)
            QuietButton(title: "Browse suppliers", fullWidth: true) { onBrowse() }
        }
    }

    @ViewBuilder private func candidate(_ l: SupplyListing, _ landed: [String: SupplyLanded.Row], _ today: Int, _ known: Set<String>) -> some View {
        SupplyListingCard(listing: l, known: known.contains(l.ownerID),
                          availability: SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: units(l), today: today),
                          landed: landed[l.id], currency: currency, landedPriced: (row.weekly ?? 0) > 0) { chosen = (chosen == l.id ? nil : l.id) }
        if chosen == l.id {
            DeliveryRecordView(record: l.record)
            SupplySignBlock(companyID: companyID, lineID: row.id, lineTitle: row.title, listing: l, weeklyMarketSpend: row.weekly ?? 0, currency: currency, onSigned: { chosen = nil })
        }
    }

    /// Each draw uses its own seed, so the second draw differs from the first; the first one is left out of it, and so is every offer the trade has no use for.
    private func draw(_ all: [SupplyListing], _ wanted: [SupplyListing], _ today: Int) {
        let seed: String = "\(companyID):\(row.id):\(today):\(drawCount)"
        let ids: Set<String> = Set(wanted.map { $0.id })
        var skip: Set<String> = Set(all.map { $0.id }).subtracting(ids)
        if let d = drawn { skip.insert(d.id) }
        drawn = market.service.randomPick(lineID: row.id, units: SupplyLandedBasis.compareUnits, today: today, seed: seed, excluding: skip)
        drawCount += 1
        chosen = nil
        Haptics.tap()
    }
}
