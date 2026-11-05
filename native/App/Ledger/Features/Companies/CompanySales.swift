import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Sales of one company: "Your products" (or "Your services") as a list, one row per item with its name, how demand is, its price and how far
/// that is from the market. Tapping an item opens its item page. Marketing is a popup (`MarketingSheet`); a trade that
/// can develop new things also has that row (a timed project, not a new item). Customers are in Stats, the Market is a Phone app, and Projects
/// are a part of this section only for project businesses (`CompanyDetailView`). There is no Pricing screen any more: prices are set per item.
struct CompanySales: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: OpsPart
    /// The last opened page, kept while the page slides away so it does not flash the settings list.
    @State private var heldPart: OpsPart = .setup
    @State private var showMarketing = false
    @State private var openItem: SalesItemPick?
    @State private var addingService: Bool?
    @State private var showHire = false
    @State private var showAddons = false

    /// A tapped item, for the popup.
    private struct SalesItemPick: Identifiable, Hashable { var id: String }
    private struct NewItemPick: Identifiable { var id: Bool }

    var body: some View {
        let items: [SalesItem] = engine.salesItems(companyID: company.id)
        let service: Bool = !items.isEmpty && items.allSatisfy { (i: SalesItem) -> Bool in i.isService }
        return VStack(spacing: Theme.Space.m) {
            CompanyBrandLine(engine: engine, companyID: company.id)
            trendCard
            productsArea(items, service)
            addonsCard
            OverviewSettingsCard(heading: "Marketing and more") {
                marketingRow
                ResearchRow(engine: engine, company: company)
            }
        }
        .centerSheet(isPresented: $showMarketing) { MarketingSheet(companyID: company.id) }
        .centerSheet(item: Binding(get: { addingService.map { (v: Bool) -> NewItemPick in NewItemPick(id: v) } }, set: { (v: NewItemPick?) in addingService = v?.id })) { (p: NewItemPick) in
            NewItemSheet(companyID: company.id, isService: p.id, onClose: { addingService = nil },
                         onHireAdvisor: { addingService = nil; presentAfterSheet { showHire = true } },
                         onAdded: { (name: String) in
                             let id: String? = store.engine?.salesItems(companyID: company.id).first(where: { (i: SalesItem) -> Bool in i.name == name })?.id
                             if let id { presentAfterSheet { openItem = SalesItemPick(id: id) } }
                         })
        }
        .navigationDestination(item: $openItem) { (p: SalesItemPick) in ItemPageView(companyID: company.id, itemID: p.id) }
        .navigationDestination(isPresented: $showHire) { HireWorkersView(companyID: company.id, startRole: "advisor") }
        .navigationDestination(isPresented: $showAddons) { DealerAddonsPage(companyID: company.id) }
        .navigationDestination(isPresented: Binding(get: { part != .setup }, set: { if !$0 { part = .setup } })) {
            OpsPageDestination(part: part == .setup ? heldPart : part, companyID: company.id)
        }
        .onChange(of: part) { (_: OpsPart, new: OpsPart) in if new != .setup { heldPart = new } }
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

    /// Dealer warranty, car loans and insurance at the sale, for both car dealers.
    @ViewBuilder private var addonsCard: some View {
        if DealerAddons.supports(company) {
            OverviewSettingsCard(heading: "Sale add-ons") {
                SettingsTableRow(title: "Warranty, loans and insurance", note: "Set up, switch on, and see what each sale brings", value: "", glyph: Glyph.opsBox) { showAddons = true }
            }
        }
    }

    @ViewBuilder private var trendCard: some View {
        let trend: MarketTrend = engine.marketTrend(companyID: company.id)
        if trend.points.count >= 2 { MarketTrendCard(trend: trend) }
    }

    // MARK: Marketing (a popup)

    private var marketingRow: some View {
        let cur: Currency = engine.currency(for: company)
        let spend: Double = company.value("mkt").object.values.reduce(0) { $0 + $1["b"].double }
        return SettingsTableRow(title: "Marketing", value: spend > 0 ? cur.tidyShort(spend) + " a week" : "No campaigns", opens: .sheet, glyph: Glyph.opsMega) { showMarketing = true }
    }

}
