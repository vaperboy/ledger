import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct CompanySupply: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var choosing: SupplierSubject?
    @State private var ordering = false
    @State private var showSell = false

    private struct ItemNeed: Identifiable {
        var id: String
        var item: SalesItem
        var page: ItemPageData
    }

    var body: some View {
        let groups: [SupplyGroup] = engine.supplyLines(companyID: company.id)
        let cur: Currency = engine.currency(for: company)
        let needs: [ItemNeed] = engine.salesItems(companyID: company.id).compactMap { (it: SalesItem) -> ItemNeed? in
            guard let p = engine.itemPage(companyID: company.id, itemID: it.id), !p.offers.isEmpty else { return nil }
            return ItemNeed(id: it.id, item: it, page: p)
        }
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text("Who supplies what you sell, and what the company needs to run.").textStyle(.body, tint: P.inkSoft)
            if !needs.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("What you sell").textStyle(.label, tint: P.inkFaint)
                    ForEach(Array(needs.enumerated()), id: \.element.id) { (n: Int, need: ItemNeed) in
                        itemCard(need, cur, first: n == 0)
                    }
                }
            }
            ForEach(groups) { (g: SupplyGroup) in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(g.name).textStyle(.label, tint: P.inkFaint)
                    ForEach(g.rows) { (r: SupplyRow) in lineCard(r, cur) }
                }
            }
            if needs.isEmpty && groups.isEmpty {
                EmptyState(glyph: Glyph.suppliers, title: "Nothing to supply yet", message: "Add a product or service and its suppliers show here.", centered: false)
            }
            InTransitSection(rows: engine.shipmentsOnTheWay(companyID: company.id), currency: cur)
            more
        }
        .centerSheet(item: $choosing, category: .detail, tone: .info) { (s: SupplierSubject) in
            SupplierPopup(companyID: company.id, subject: s, onClose: { choosing = nil }).environmentObject(store)
        }
        .navigationDestination(isPresented: $ordering) {
            SettingsPage(title: "Order stock", subtitle: company.name) { StockOrderPopup(companyID: company.id, onDone: { ordering = false }).environmentObject(store) }
        }
        .navigationDestination(isPresented: $showSell) { SupplyOtherPlayersScreen(companyID: company.id).environmentObject(store) }
        .task { market.sync(store) }
        .onChange(of: store.engine?.state.week) { _, _ in market.sync(store) }
    }

    private func itemCard(_ need: ItemNeed, _ cur: Currency, first: Bool) -> some View {
        let supply: ItemModels.SupplyLine? = need.page.supply
        let id: String = need.item.id
        return SupplyCard(title: need.item.name, tag: need.item.isService ? "Service" : "Product", supplier: supply?.vendorName ?? "No supplier chosen",
                          detail: supply.map { (s: ItemModels.SupplyLine) -> String in itemAmount(s.buyPrice, cur) + " a unit" } ?? "Pick one so it can be stocked.",
                          warn: supply == nil, note: nil, canChange: true, identifier: "item-supplier-change-\(id)", coach: first) {
            choosing = .item(id)
        }
    }

    private func lineCard(_ r: SupplyRow, _ cur: Currency) -> some View {
        let contract: SupplyContract? = market.service.contract(buyerCompanyID: company.id, lineID: r.id)
        let id: String = r.id
        let canChange: Bool = r.governed == nil && (r.canSwitch || !SupplyMarketCatalogue.tradesSupplying(line: id).isEmpty)
        return SupplyCard(title: r.title, tag: r.note == nil ? "On time" : "Late", tagTint: r.note == nil ? P.gain : P.loss, supplier: contract?.supplierName ?? r.current,
                          detail: r.weekly.map { (w: Double) -> String in cur.tidyShort(w) + " a week" } ?? "Paid per job", warn: false, note: r.governed ?? r.note,
                          canChange: canChange, identifier: "supply-change-\(id)", coach: false) {
            choosing = .line(id)
        }
    }

    private var more: some View {
        PageGroup("More") {
            if engine.stockOrderBasis(companyID: company.id) != nil {
                LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.inkSoft, title: "Order stock once",
                          subtitle: "Compare price and transport, then order", identifier: "suppliers-order") { ordering = true }
                RowRule()
            }
            if SupplyMarketCatalogue.canSupply(tradeID: company.type) {
                LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.inkSoft, title: "Supply other players",
                          subtitle: "Offer what this company makes", identifier: "suppliers-sell") { showSell = true }
            }
        }
    }
}

private struct SupplyCard: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var tag: String
    var tagTint: Color? = nil
    var supplier: String
    var detail: String
    var warn: Bool
    var note: String?
    var canChange: Bool
    var identifier: String
    var coach: Bool
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(title.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s)
                Chip(text: tag, tint: tagTint ?? P.inkFaint)
            }
            Hairline()
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(supplier.tidyText).textStyle(.body, tint: warn ? P.caution : nil).lineLimit(2).multilineTextAlignment(.leading)
                    Text(detail).textStyle(.caption, tint: P.inkSoft, numeric: true)
                }
                Spacer(minLength: Theme.Space.s)
                if canChange {
                    Button("Change") { Haptics.tap(); onChange() }
                        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                        .accessibilityIdentifier(identifier)
                        .coachAnchor(.itemSupplier, enabled: coach)
                }
            }
            if let note {
                Text(note.tidyText).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
        .accessibilityElement(children: .contain)
    }
}
