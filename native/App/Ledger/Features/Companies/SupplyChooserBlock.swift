import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The three ways to choose a player supplier for a purchase, in the offers popup: Well known (best records and volume), Random pick (drawn from
/// the fair-price reliable pool, one new draw allowed) and Browse (search and filters on their own page). The House suppliers below stay as
/// the backup and the automatic fallback.
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

    private static let ways: [Int] = [0, 1, 2]
    private static let names: [String] = ["Well known", "Random pick", "Browse"]

    var body: some View {
        let today: Int = store.engine.map { SupplyMarketStore.today($0) } ?? 0
        let known: Set<String> = market.service.knownSuppliers()
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Other players").capsLabel(Theme.ivoryFaint)
            if let c = market.service.contract(buyerCompanyID: companyID, lineID: row.id) { current(c) }
            SegmentedPill(items: Self.ways, title: { (i: Int) -> String in Self.names[i] }, selection: $way)
            switch way {
            case 0: wellKnown(today, known)
            case 1: random(today, known)
            default: browse()
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
                market.service.endContract(buyerCompanyID: companyID, lineID: row.id)
                market.returnToHouse(store, companyID: companyID, lineID: row.id)
                Haptics.tap()
            }
        }
    }

    private func units(_ l: SupplyListing) -> Int { max(l.minOrder, 20) }

    @ViewBuilder private func wellKnown(_ today: Int, _ known: Set<String>) -> some View {
        let top: [SupplyListing] = Array(market.service.wellKnown(lineID: row.id, units: 1, today: today).prefix(3))
        Text("The best records and the most delivered.").popupText(.caption)
        if top.isEmpty { Text("No player supplies this yet.").popupText(.caption) }
        ForEach(top) { (l: SupplyListing) in candidate(l, today, known) }
    }

    @ViewBuilder private func random(_ today: Int, _ known: Set<String>) -> some View {
        Text("A supplier drawn from fairly priced, reliable ones, so newcomers get orders too.").popupText(.caption)
        if let l = drawn {
            candidate(l, today, known)
            if drawCount < 2 {
                QuietButton(title: "Draw again (once)", fullWidth: true) { draw(today) }
            } else {
                Text("That was your one new draw.").popupText(.caption)
            }
        } else {
            QuietButton(title: "Draw a supplier", fullWidth: true) { draw(today) }
        }
    }

    private func browse() -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Search by name, friend, profile code or company, save known suppliers, and filter by price, quality, region and record.").popupText(.caption)
            QuietButton(title: "Browse suppliers", fullWidth: true) { onBrowse() }
        }
    }

    @ViewBuilder private func candidate(_ l: SupplyListing, _ today: Int, _ known: Set<String>) -> some View {
        SupplyListingCard(listing: l, known: known.contains(l.ownerID),
                          availability: SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: units(l), today: today)) { chosen = (chosen == l.id ? nil : l.id) }
        if chosen == l.id {
            DeliveryRecordView(record: l.record)
            SupplySignBlock(companyID: companyID, lineID: row.id, lineTitle: row.title, listing: l, weeklyMarketSpend: row.weekly ?? 0, currency: currency, onSigned: { chosen = nil })
        }
    }

    /// Each draw uses its own seed, so the second draw differs from the first; the first one is left out of it.
    private func draw(_ today: Int) {
        let seed: String = "\(companyID):\(row.id):\(today):\(drawCount)"
        let skip: Set<String> = drawn.map { Set([$0.id]) } ?? []
        drawn = market.service.randomPick(lineID: row.id, units: 20, today: today, seed: seed, excluding: skip)
        drawCount += 1
        chosen = nil
        Haptics.tap()
    }
}
