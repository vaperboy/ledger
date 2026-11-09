import SwiftUI
import GameCore
import Countries
import Finance
import Events
import Businesses
import Simulation

/// What an offer really costs the buyer: the price, freight and customs of the goods that travel, as the engine works them out (`SupplyLanded`), and the
/// screens that use it: the landed-cost lines on offers, the one-off stock order and the list of what is on the way.
enum SupplyLandedBasis {
    /// A neutral weekly spend that ranks offers when the company has no priced spend yet; money is not shown against it.
    static let neutralWeekly = 2000.0
    /// The weekly order the offers are compared at.
    static let compareUnits = 20

    /// The offers of a purchase with their landed costs, cheapest landed cost first.
    static func rows(_ e: GameEngine, companyID: Int, listings: [SupplyListing], weekly: Double?, units: Int = compareUnits) -> [SupplyLanded.Row] {
        let spend: Double = (weekly ?? 0) > 0 ? (weekly ?? 0) : neutralWeekly
        return e.playerSupplyLanded(companyID: companyID, listings: listings, weeklyMarketSpend: spend, units: units)
    }

    static func lookup(_ rows: [SupplyLanded.Row]) -> [String: SupplyLanded.Row] {
        Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Price, freight, customs and the landed total of one offer, per unit, with how it travels. Without a priced spend it says the share freight and customs add.
struct LandedCostLines: View {
    var row: SupplyLanded.Row
    var currency: Currency
    var priced: Bool
    var popup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.mode == nil {
                line(priced ? "\(currency.tidyShort(row.unitPrice)) a unit. Delivered as a service: no freight or customs." : "Delivered as a service: no freight or customs.")
            } else if priced {
                line("Landed cost \(currency.tidyShort(row.landedPerUnit)) a unit: price \(currency.tidyShort(row.unitPrice)) + freight \(currency.tidyShort(row.freightPerUnit))"
                     + (row.crossesBorder ? " + customs \(currency.tidyShort(row.customsPerUnit))" : ""), strong: true)
                line(SupplyLanded.transitText(row))
            } else {
                let extra: Int = Int(((row.landedFactor - 1) * 100).rounded())
                line("Freight" + (row.crossesBorder ? " and customs" : "") + " add about \(max(0, extra))% to the price.", strong: true)
                line(SupplyLanded.transitText(row))
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func line(_ text: String, strong: Bool = false) -> some View {
        if popup {
            Text(text).popupText(.caption)
        } else {
            Text(text).textStyle(.caption, tint: strong ? Theme.ink : Theme.inkSoft).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
        }
    }
}

// MARK: One-off stock order

/// Orders stock from a player's company: the offers ranked by landed cost, how many units, what it costs with freight and customs, and when it arrives.
/// The goods are paid for now and join the shelves when they arrive; the order shows under "On the way".
struct StockOrderPopup: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var companyID: Int
    var onDone: () -> Void
    @State private var pickedID: String?
    @State private var units: Double = 0
    @State private var message: String?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let basis = e.stockOrderBasis(companyID: companyID) {
            content(e, co, basis)
        } else {
            Text("This company holds no stock to order.").popupText(.caption)
        }
    }

    private func usable(_ e: GameEngine) -> [SupplyListing] {
        market.service.listings(lineID: "goods").filter { e.playerSupplyAllowed(companyID: companyID, listing: $0) }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company, _ basis: StockOrderBasis) -> some View {
        let cur: Currency = e.currency(for: co)
        let today: Int = SupplyMarketStore.today(e)
        let all: [SupplyListing] = usable(e)
        let rows: [SupplyLanded.Row] = e.playerSupplyLanded(companyID: companyID, listings: all, weeklyMarketSpend: basis.unitCost * Double(SupplyLandedBasis.compareUnits), units: SupplyLandedBasis.compareUnits)
        let byID: [String: SupplyListing] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known: Set<String> = market.service.knownSuppliers()
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("On the shelves: \(Int(basis.held)) units" + (basis.target.map { " of about \(Int($0)) wanted" } ?? "") + ". At the market price a unit costs \(cur.tidyShort(basis.unitCost)).").popupText(.caption)
            if rows.isEmpty {
                Text("No player offers stock your trade uses right now.").popupText(.caption)
            }
            ForEach(Array(rows.prefix(6).enumerated()), id: \.element.id) { (n: Int, r: SupplyLanded.Row) in
                if let l = byID[r.id] {
                    if n > 0 { Hairline() }
                    offer(l, r, cur, today, known)
                }
            }
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Order stock")
    }

    @ViewBuilder private func offer(_ l: SupplyListing, _ r: SupplyLanded.Row, _ cur: Currency, _ today: Int, _ known: Set<String>) -> some View {
        let availability: SupplyAvailability = SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: l.minOrder, today: today)
        SupplyListingCard(listing: l, known: known.contains(l.ownerID), availability: availability, landed: r, currency: cur, landedPriced: true) {
            pickedID = pickedID == l.id ? nil : l.id
            units = Double(max(l.minOrder, 20))
            message = nil
        }
        if pickedID == l.id && availability == .available {
            let room: Int = max(l.minOrder, SupplyGuards.effectiveCapacity(l) - l.committedUnits)
            HStack {
                Text("Units").popupText(.rowLabel)
                Spacer(minLength: Theme.Space.s)
                Text("\(Int(units))").popupText(.rowValue)
                StepperPill(value: $units, range: Double(l.minOrder)...Double(room), step: 5)
            }
            let n: Double = max(1, units)
            Text("About \(cur.tidyShort(r.landedPerUnit * n)) with freight and customs, paid now.").popupText(.body)
            PopupOptionButton(title: "Order \(Int(units)) from \(l.ownerName)", highlighted: true) { place(l) }
        }
    }

    private func place(_ l: SupplyListing) {
        if let why = market.order(store, companyID: companyID, listing: l, units: Int(units)) {
            Haptics.warning()
            message = why
            return
        }
        Haptics.success()
        store.outcome(chosen: "Order from \(l.ownerName)", result: "\(Int(units)) units ordered from \(l.ownerName). They are on the way and join the shelves when they arrive.")
        onDone()
    }
}

// MARK: On the way

/// Orders that are still travelling: who sent them, where from, when they arrive and what a hold at the border added.
struct InTransitSection: View {
    var rows: [Shipments.Row]
    var currency: Currency

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("On the way").capsLabel(Theme.ivoryFaint).padding(.horizontal, 2)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { (n: Int, r: Shipments.Row) in
                        if n > 0 { Hairline() }
                        row(r)
                    }
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface()
            }
        }
    }

    private func arrival(_ r: Shipments.Row) -> String {
        let base: String = r.weeksLeft == 0 ? "Arrives this week" : r.weeksLeft == 1 ? "Arrives next week" : "Arrives in \(r.weeksLeft) weeks"
        return r.delayedWeeks > 0 ? base + ", held \(r.delayedWeeks) \(r.delayedWeeks == 1 ? "week" : "weeks") at the border" : base
    }

    private func row(_ r: Shipments.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.supplier).textStyle(.headline).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Text(currency.tidyShort(r.goods)).textStyle(.body, numeric: true)
            }
            Text(arrival(r) + (r.from.isEmpty ? "" : " · from \(r.from)")).textStyle(.caption, tint: r.delayedWeeks > 0 ? Theme.caution : Theme.inkSoft)
            if r.perishable { Text("Perishable: it spoils if it waits too long.").textStyle(.caption, tint: Theme.inkFaint) }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
