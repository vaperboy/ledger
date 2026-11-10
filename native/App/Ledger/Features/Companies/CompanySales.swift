import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanySales: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var showMarketing = false
    @State private var priceFor: SalesItemPick?
    @State private var supplierFor: SupplierSubject?
    @State private var pendingPrice: String?
    @State private var addingService: Bool?
    @State private var showHire = false
    @State private var showAddons = false
    @Environment(\.outsidePalette) private var P

    private struct SalesItemPick: Identifiable, Hashable { var id: String }
    private struct NewItemPick: Identifiable { var id: Bool }

    var body: some View {
        let items: [SalesItem] = engine.salesItems(companyID: company.id)
        let service: Bool = !items.isEmpty && items.allSatisfy { (i: SalesItem) -> Bool in i.isService }
        return VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            hero(items)
            productsArea(items, service)
            addonsCard
            OverviewSettingsCard(heading: "Marketing and more") {
                marketingRow
            }
        }
        .centerSheet(isPresented: $showMarketing, title: "Marketing", category: .detail, tone: .investment) { MarketingSheet(companyID: company.id) }
        .centerSheet(item: Binding(get: { addingService.map { (v: Bool) -> NewItemPick in NewItemPick(id: v) } }, set: { (v: NewItemPick?) in addingService = v?.id }), category: .medium, tone: .info) { (p: NewItemPick) in
            NewItemSheet(companyID: company.id, isService: p.id, onClose: { addingService = nil },
                         onHireAdvisor: { addingService = nil; showHire = true },
                         onAdded: { (name: String) in
                             let id: String? = store.engine?.salesItems(companyID: company.id).first(where: { (i: SalesItem) -> Bool in i.name == name })?.id
                             if let id { itemChosen(id) }
                         })
        }
        .centerSheet(item: $supplierFor, category: .detail, tone: .info, onDismiss: { if let id = pendingPrice { pendingPrice = nil; showPrice(id) } }) { (s: SupplierSubject) in
            SupplierPopup(companyID: company.id, subject: s, asking: true, onClose: { supplierFor = nil }).environmentObject(store)
        }
        .centerSheet(item: $priceFor, category: .detail, tone: .investment) { (p: SalesItemPick) in
            ItemPriceSheet(companyID: company.id, itemID: p.id, onClose: { priceFor = nil })
        }
        .navigationDestination(isPresented: $showHire) { HireWorkersView(companyID: company.id, startRole: "advisor") }
        .navigationDestination(isPresented: $showAddons) { DealerAddonsPage(companyID: company.id) }
    }

    @ViewBuilder private func productsArea(_ items: [SalesItem], _ service: Bool) -> some View {
        if company.type == UsedCarDealer.tradeID {
            UsedCarYardSection(engine: engine, company: company)
            CompanyInventorySection(companyID: company.id, tradeID: company.type)
        } else if company.type == CarDealer.tradeID {
            CarDealerSection(engine: engine, company: company)
        } else {
            ItemsList(engine: engine, company: company, items: items, service: service,
                      onOpen: { (id: String) in showPrice(id) }, onAdd: { addingService = service },
                      onChosen: { (id: String) in itemChosen(id) })
            if company.type == "carrepair" { CompanyInventorySection(companyID: company.id, tradeID: company.type) }
        }
    }

    private func itemChosen(_ id: String) {
        if let ask = (store.engine ?? engine).supplyAsk(companyID: company.id, itemID: id) {
            pendingPrice = id
            supplierFor = SupplierSubject(ask, itemID: id)
        } else {
            store.tutorialAdvance(from: .pickSupplier)
            showPrice(id)
        }
    }

    private func showPrice(_ id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { priceFor = SalesItemPick(id: id) }
    }

    private func hero(_ items: [SalesItem]) -> some View {
        let co: Company = company
        let h: CompanyHealth = store.memo("coHealth\(co.id)") { $0.companyHealth(co) } ?? engine.companyHealth(co)
        let week: Double = co.lastWeekRevenue
        let best: SalesItem? = items.max { (a: SalesItem, b: SalesItem) -> Bool in a.weeklyRevenue < b.weeklyRevenue }
        let brand: String = "Brand " + BrandWords.label(score: engine.brandValue(companyID: co.id)).lowercased()
        let noCap: Bool = engine.operationsFigures(companyID: co.id)?.weeks.last.map { $0.capacity <= 0 && $0.demand > 0 } ?? false
        let bestText: String = noCap ? "no one could be served" : ((best?.weeklyRevenue ?? 0) > 0 ? "best seller " + (best?.name ?? "") : "")
        return CompanyHero(label: "Sales last week", value: store.money(week, in: co), change: brand, changeTint: P.accent,
                           context: bestText, trend: Array(h.revenueSeries.suffix(12)), live: week)
    }

    @ViewBuilder private var addonsCard: some View {
        if DealerAddons.supports(company) {
            PageGroup("Add-ons") {
                LedgerRow(leading: .glyph(Glyph.opsBox), leadingTint: P.inkSoft, title: "Warranty, loans and insurance",
                          identifier: "sales-addons") { showAddons = true }
            }
        }
    }

    private var marketingRow: some View {
        let cur: Currency = engine.currency(for: company)
        let spend: Double = company.value("mkt").object.values.reduce(0) { $0 + $1["b"].double }
        return SettingsTableRow(title: "Marketing", value: spend > 0 ? cur.tidyShort(spend) + " a week" : "No campaigns", opens: .sheet, glyph: Glyph.opsMega) { showMarketing = true }
    }
}
