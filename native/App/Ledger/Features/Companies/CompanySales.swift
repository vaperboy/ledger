import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Sales of one company: "Your products" (or "Your services") as a list, one row per item with its name, how demand is, its price and how far
/// that is from the market. Tapping an item opens its item page. Marketing is a popup (`MarketingSheet`).
/// Customers are in Stats; the market, its
/// rivals and market research are in the Market app; Projects are a part of this section only for project businesses (`CompanyDetailView`).
/// There is no Pricing screen any more: prices are set per item.
struct CompanySales: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: OpsPart
    @State private var showMarketing = false
    @State private var openItem: SalesItemPick?
    @State private var addingService: Bool?
    @State private var showHire = false
    @State private var showAddons = false
    @Environment(\.outsidePalette) private var P

    /// A tapped item, for the popup.
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
                             if let id { openItem = SalesItemPick(id: id) }
                         })
        }
        .navigationDestination(item: $openItem) { (p: SalesItemPick) in ItemPageView(companyID: company.id, itemID: p.id) }
        .navigationDestination(isPresented: $showHire) { HireWorkersView(companyID: company.id, startRole: "advisor") }
        .navigationDestination(isPresented: $showAddons) { DealerAddonsPage(companyID: company.id) }
    }

    /// Sales last week, the brand's standing and the best seller; the sparkline is revenue by month.
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

    /// The used car yard and the new car showroom have their own pages (real cars, one price each); every other trade lists its items.
    @ViewBuilder private func productsArea(_ items: [SalesItem], _ service: Bool) -> some View {
        if company.type == UsedCarDealer.tradeID {
            UsedCarYardSection(engine: engine, company: company)
        } else if company.type == CarDealer.tradeID {
            CarDealerSection(engine: engine, company: company)
        } else {
            ItemsList(engine: engine, company: company, items: items, service: service,
                      onOpen: { (id: String) in openItem = SalesItemPick(id: id) }, onAdd: { addingService = service })
        }
    }

    /// Dealer add-ons (warranty, loans, insurance), only for trades that sell them.
    @ViewBuilder private var addonsCard: some View {
        if DealerAddons.supports(company) {
            PageGroup("Add-ons") {
                LedgerRow(leading: .glyph(Glyph.opsBox), leadingTint: P.inkSoft, title: "Warranty, loans and insurance",
                          identifier: "sales-addons") { showAddons = true }
            }
        }
    }

    // MARK: Marketing (a popup)

    private var marketingRow: some View {
        let cur: Currency = engine.currency(for: company)
        let spend: Double = company.value("mkt").object.values.reduce(0) { $0 + $1["b"].double }
        return SettingsTableRow(title: "Marketing", value: spend > 0 ? cur.tidyShort(spend) + " a week" : "No campaigns", opens: .sheet, glyph: Glyph.opsMega) { showMarketing = true }
    }

}
