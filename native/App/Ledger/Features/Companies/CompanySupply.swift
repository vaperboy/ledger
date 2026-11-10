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
    @State private var ownerCode: OwnerRoute?

    private struct OwnerRoute: Identifiable, Hashable { var id: String }

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
            yourSupply(cur)
            if !needs.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("What you sell: who supplies it").textStyle(.label, tint: P.inkFaint)
                    ForEach(Array(needs.enumerated()), id: \.element.id) { (n: Int, need: ItemNeed) in
                        itemCard(need, cur, first: n == 0)
                    }
                }
            }
            ForEach(groups) { (g: SupplyGroup) in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("What the company buys: " + g.name.lowercased()).textStyle(.label, tint: P.inkFaint)
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
            SupplierPopup(companyID: company.id, subject: s, onClose: { choosing = nil }, onOpenOwner: { (code: String) in
                choosing = nil
                ownerCode = OwnerRoute(id: code)
            }).environmentObject(store)
        }
        .navigationDestination(item: $ownerCode) { (r: OwnerRoute) in PlayerProfileByCode(code: r.id) }
        .navigationDestination(isPresented: $ordering) {
            SettingsPage(title: "Order stock", subtitle: company.name) { StockOrderPopup(companyID: company.id, onDone: { ordering = false }).environmentObject(store) }
        }
        .task { market.sync(store) }
        .onChange(of: store.engine?.state.week) { _, _ in market.sync(store) }
    }

    private func itemCard(_ need: ItemNeed, _ cur: Currency, first: Bool) -> some View {
        let supply: ItemModels.SupplyLine? = need.page.supply
        let id: String = need.item.id
        var facts: [(String, String)] = []
        if let s = supply {
            facts.append(("Price", itemAmount(s.buyPrice, cur) + " a unit"))
            if s.leadDays > 0 { facts.append(("Lead time", "\(s.leadDays) days")) }
        }
        return SupplyCard(item: need.item.name, kind: need.item.isService ? "Service" : "Product", supplier: supply?.vendorName ?? "No supplier chosen", logoID: "", ownerName: "",
                          onOwner: nil, facts: facts, status: supply == nil ? "Pick one so it can be stocked" : "Supplier chosen", statusTint: supply == nil ? P.caution : P.gain,
                          note: nil, canChange: true, identifier: "item-supplier-change-\(id)", coach: first) {
            choosing = .item(id)
        }
    }

    private func lineCard(_ r: SupplyRow, _ cur: Currency) -> some View {
        let contract: SupplyContract? = market.service.contract(buyerCompanyID: company.id, lineID: r.id)
        let listing: SupplyListing? = contract.flatMap { (c: SupplyContract) -> SupplyListing? in market.service.listing(c.listingID) }
        let id: String = r.id
        let canChange: Bool = r.governed == nil && (r.canSwitch || !SupplyMarketCatalogue.tradesSupplying(line: id).isEmpty)
        var facts: [(String, String)] = [("Price", r.weekly.map { (w: Double) -> String in cur.tidyShort(w) + " a week" } ?? "Paid per job")]
        if let l = listing {
            facts.append(("Lead time", SupplyMarketWords.lead(l.leadDays)))
        } else if let lead = r.offers.first(where: { (o: SupplyOfferRow) -> Bool in o.isCurrent })?.lead, !lead.isEmpty {
            facts.append(("Lead time", lead))
        }
        let code: String = listing?.profileCode ?? ""
        return SupplyCard(item: r.title, kind: "Company needs", supplier: listing?.companyName ?? contract?.supplierName ?? r.current, logoID: listing?.logoID ?? "",
                          ownerName: listing?.ownerName ?? "", onOwner: code.isEmpty ? nil : { ownerCode = OwnerRoute(id: code) }, facts: facts,
                          status: r.note == nil ? "On time" : "Late", statusTint: r.note == nil ? P.gain : P.loss, note: r.governed ?? r.note,
                          canChange: canChange, identifier: "supply-change-\(id)", coach: false) {
            choosing = .line(id)
        }
    }

    @ViewBuilder private func yourSupply(_ cur: Currency) -> some View {
        let lines: [String] = SupplyMarketCatalogue.supplies[company.type] ?? []
        let mine: [SupplyListing] = lines.flatMap { (line: String) -> [SupplyListing] in
            market.service.listings(lineID: line).filter { (l: SupplyListing) -> Bool in l.companyID == company.id }
        }
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("What the company supplies to others").textStyle(.label, tint: P.inkFaint)
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

private struct SupplyCard: View {
    @Environment(\.outsidePalette) private var P
    var item: String
    var kind: String
    var supplier: String
    var logoID: String
    var ownerName: String
    var onOwner: (() -> Void)?
    var facts: [(String, String)]
    var status: String
    var statusTint: Color
    var note: String?
    var canChange: Bool
    var identifier: String
    var coach: Bool
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(kind.uppercased()).textStyle(.label, tint: P.inkFaint)
                Text(item.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
            }
            HStack(alignment: .center, spacing: Theme.Space.m) {
                SupplierLogo(logoID: logoID, name: supplier, size: 64)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Supplier").textStyle(.caption, tint: P.inkFaint)
                    Text(supplier.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            if !ownerName.isEmpty { SupplierOwnerLine(name: ownerName, onOpen: onOwner) }
            Hairline()
            VStack(spacing: Theme.Space.xs) {
                ForEach(Array(facts.enumerated()), id: \.offset) { (_: Int, f: (String, String)) in SupplierFact(label: f.0, value: f.1) }
                SupplierFact(label: "Status", value: status, tint: statusTint)
            }
            if let note {
                Text(note.tidyText).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true)
            }
            if canChange {
                Button("Change supplier") { Haptics.tap(); onChange() }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true, tint: P.accent))
                    .accessibilityIdentifier(identifier)
                    .coachAnchor(.itemSupplier, enabled: coach)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
        .accessibilityElement(children: .contain)
    }
}
