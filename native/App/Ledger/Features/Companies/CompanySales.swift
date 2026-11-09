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
    @State private var openItem: SalesItemPick?
    @State private var showAddons = false
    @Environment(\.outsidePalette) private var P

    private struct SalesItemPick: Identifiable, Hashable { var id: String }

    var body: some View {
        let items: [SalesItem] = engine.salesItems(companyID: company.id)
        let service: Bool = !items.isEmpty && items.allSatisfy { (i: SalesItem) -> Bool in i.isService }
        let ownPages: Bool = company.type == UsedCarDealer.tradeID || company.type == CarDealer.tradeID
        return VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            hero(items)
            if !ownPages {
                ItemsList(engine: engine, company: company, items: items, service: service, onOpen: { (id: String) in openItem = SalesItemPick(id: id) })
            }
            addonsCard
            OverviewSettingsCard(heading: "Marketing and more") {
                marketingRow
            }
        }
        .centerSheet(isPresented: $showMarketing, title: "Marketing", category: .detail, tone: .investment) { MarketingSheet(companyID: company.id) }
        .navigationDestination(item: $openItem) { (p: SalesItemPick) in ItemPageView(companyID: company.id, itemID: p.id) }
        .navigationDestination(isPresented: $showAddons) { DealerAddonsPage(companyID: company.id) }
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
