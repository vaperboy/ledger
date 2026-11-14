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
    @State private var ordering = false

    var body: some View {
        let groups: [SupplyGroup] = engine.supplyLines(companyID: company.id)
        let rows: [SupplyRow] = groups.flatMap { (g: SupplyGroup) -> [SupplyRow] in g.rows }
        let inputs: [SupplierInput] = engine.supplierInputs(companyID: company.id)
        let items: [SupplierFacts] = engine.salesItems(companyID: company.id).compactMap { (it: SalesItem) -> SupplierFacts? in
            SupplierFacts.make(engine, company, .item(it.id), market: market)
        }
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            yourSupply()
            if !items.isEmpty {
                SupplySection(title: "Items") {
                    ForEach(Array(items.enumerated()), id: \.element.id) { (n: Int, f: SupplierFacts) in
                        if n > 0 { RowRule(inset: 0) }
                        supplierRow(f)
                    }
                }
            }
            ForEach(groups) { (g: SupplyGroup) in
                let facts: [SupplierFacts] = g.rows.compactMap { (r: SupplyRow) -> SupplierFacts? in
                    SupplierFacts.make(engine, company, .line(r.id), market: market, rows: rows, inputs: inputs)
                }
                SupplySection(title: g.name) {
                    ForEach(Array(facts.enumerated()), id: \.element.id) { (n: Int, f: SupplierFacts) in
                        if n > 0 { RowRule(inset: 0) }
                        supplierRow(f)
                    }
                }
            }
            if items.isEmpty && groups.isEmpty {
                EmptyState(glyph: Glyph.suppliers, title: "Nothing to supply yet", message: "Add a product or service and its suppliers show here.", centered: false)
            }
            InTransitSection(rows: engine.shipmentsOnTheWay(companyID: company.id), currency: engine.currency(for: company))
            more
        }
        .navigationDestination(isPresented: $ordering) {
            SettingsPage(title: "Order stock", subtitle: company.name) { StockOrderPopup(companyID: company.id, onDone: { ordering = false }).environmentObject(store) }
        }
        .task { market.sync(store) }
        .onChange(of: store.engine?.state.week) { _, _ in market.sync(store) }
    }

    private func supplierRow(_ f: SupplierFacts) -> some View {
        SupplierListRow(facts: f, identifier: "supplier-row-" + f.id) { store.push(.supplier(company.id, f.subject.id)) }
    }

    @ViewBuilder private func yourSupply() -> some View {
        let lines: [String] = SupplyMarketCatalogue.supplies[company.type] ?? []
        let mine: [SupplyListing] = lines.flatMap { (line: String) -> [SupplyListing] in
            market.service.listings(lineID: line).filter { (l: SupplyListing) -> Bool in l.companyID == company.id }
        }
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("You supply").textStyle(.headline, tint: P.ink)
                ForEach(mine) { (l: SupplyListing) in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(spacing: Theme.Space.m) {
                            SupplierLogo(logoID: l.logoID, name: l.companyName, size: 56)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(l.lineName.tidyText).textStyle(.headline).lineLimit(2)
                                Text(l.companyName.tidyText).textStyle(.caption, tint: P.inkSoft).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        Hairline()
                        SupplierFact(label: "Price", value: SupplyMarketWords.price(l.priceTier))
                        SupplierFact(label: "Capacity", value: "\(SupplyGuards.effectiveCapacity(l)) units a week")
                        SupplierFact(label: "Lead time", value: SupplyMarketWords.lead(l.leadDays))
                        SupplierFact(label: "Status", value: l.paused ? "Paused" : "Open for orders", tint: l.paused ? P.caution : P.gain)
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private var more: some View {
        if engine.stockOrderBasis(companyID: company.id) != nil {
            PageGroup("More") {
                LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.inkSoft, title: "Order stock once",
                          subtitle: "Compare price and transport, then order", identifier: "suppliers-order") { ordering = true }
            }
        }
    }
}
