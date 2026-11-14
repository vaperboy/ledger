import SwiftUI
import GameCore
import Countries
import Finance
import Events
import Businesses
import Simulation

enum SupplyLandedBasis {
    static let neutralWeekly = 2000.0
    static let compareUnits = 20

    static func rows(_ e: GameEngine, companyID: Int, listings: [SupplyListing], weekly: Double?, units: Int = compareUnits) -> [SupplyLanded.Row] {
        let spend: Double = (weekly ?? 0) > 0 ? (weekly ?? 0) : neutralWeekly
        return e.playerSupplyLanded(companyID: companyID, listings: listings, weeklyMarketSpend: spend, units: units)
    }

    static func lookup(_ rows: [SupplyLanded.Row]) -> [String: SupplyLanded.Row] {
        Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

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

// A one-off stock order: the game orders what brings the shelves back to target; the player picks who from.
struct StockOrderPopup: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var companyID: Int
    var onDone: () -> Void
    @State private var pickedID: String?
    @State private var message: String?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let basis = e.stockOrderBasis(companyID: companyID) {
            content(e, co, basis)
        } else {
            Text("This company holds no stock to order.").popupText(.caption)
        }
    }

    private func usable(_ e: GameEngine, _ co: Company) -> [SupplyListing] {
        guard let bd = e.data.catalog[co.type], let line = SupplyCatalogue.stockLine(co, bd) else { return [] }
        return market.service.listings(lineID: line.id).filter { e.playerSupplyAllowed(companyID: companyID, listing: $0) }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company, _ basis: StockOrderBasis) -> some View {
        let cur: Currency = e.currency(for: co)
        let today: Int = SupplyMarketStore.today(e)
        let units: Int = e.stockOrderUnits(companyID: companyID)
        let all: [SupplyListing] = usable(e, co)
        let rows: [SupplyLanded.Row] = e.playerSupplyLanded(companyID: companyID, listings: all, weeklyMarketSpend: basis.unitCost * Double(units), units: units)
        let byID: [String: SupplyListing] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known: Set<String> = market.service.knownSuppliers()
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("On the shelves: \(Int(basis.held)) units" + (basis.target.map { " of about \(Int($0)) wanted" } ?? "") + ". This order brings in \(units) units at about \(cur.tidyShort(basis.unitCost)) a unit.").popupText(.caption)
            if rows.isEmpty {
                Text("No player offers stock your trade uses right now.").popupText(.caption)
            }
            ForEach(Array(rows.prefix(6).enumerated()), id: \.element.id) { (n: Int, r: SupplyLanded.Row) in
                if let l = byID[r.id] {
                    if n > 0 { Hairline() }
                    offer(l, r, cur, today, known, units)
                }
            }
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Order stock")
    }

    @ViewBuilder private func offer(_ l: SupplyListing, _ r: SupplyLanded.Row, _ cur: Currency, _ today: Int, _ known: Set<String>, _ units: Int) -> some View {
        let room: Int = SupplyGuards.effectiveCapacity(l) - l.committedUnits
        let fit: SupplyFit = SupplyFit.of(free: Double(max(0, room)), need: Double(units))
        let availability: SupplyAvailability = SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: max(l.minOrder, units), today: today)
        SupplyListingCard(listing: l, known: known.contains(l.ownerID), availability: availability, landed: r, currency: cur, landedPriced: true) {
            pickedID = pickedID == l.id ? nil : l.id
            message = nil
        }
        FitMark(fit: fit)
        if pickedID == l.id && availability == .available && fit != .cannot {
            Text("About \(cur.tidyShort(r.landedPerUnit * Double(units))) with freight and customs, paid now.").popupText(.body)
            PopupOptionButton(title: "Order from \(l.companyName.isEmpty ? l.ownerName : l.companyName)", highlighted: true) { place(l, units) }
        }
    }

    private func place(_ l: SupplyListing, _ units: Int) {
        if let why = market.order(store, companyID: companyID, listing: l, units: units) {
            Haptics.warning()
            message = why
            return
        }
        Haptics.success()
        let who: String = l.companyName.isEmpty ? l.ownerName : l.companyName
        store.outcome(chosen: "Order from \(who)", result: "\(units) units ordered from \(who). They are on the way and join the shelves when they arrive.")
        onDone()
    }
}

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
