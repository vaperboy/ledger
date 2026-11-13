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
    @State private var ownerTrip: OwnerTrip?
    @Environment(\.outsidePalette) private var P

    /// A look at a supplier's owner from the chooser: the card is pushed, and the chooser comes back when the player returns.
    private struct OwnerTrip: Equatable {
        var subject: SupplierSubject
        var tab: AppTab
        var depth: Int
        var shown: Bool = false
    }

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
        .centerSheet(item: $supplierFor, category: .detail, tone: .info, onDismiss: { supplierClosed() }) { (s: SupplierSubject) in
            SupplierPopup(companyID: company.id, subject: s, asking: true, onClose: { supplierFor = nil },
                          onOpenOwner: { (ref: SupplierOwnerRef) in openOwner(ref, from: s) }).environmentObject(store)
        }
        .onChange(of: ownerTripDepth) { (_: Int, depth: Int) in ownerTripMoved(depth) }
        .onAppear { ownerTripMoved(ownerTripDepth) }
        .centerSheet(item: $priceFor, category: .detail, tone: .investment) { (p: SalesItemPick) in
            ItemPriceSheet(companyID: company.id, itemID: p.id, onClose: { priceFor = nil }, onRestock: { restock(p.id) })
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
                      onOpen: { (id: String) in openItem(id) }, onAdd: { addingService = service },
                      onChosen: { (id: String) in itemChosen(id) })
            if company.type == "carrepair" { CompanyInventorySection(companyID: company.id, tradeID: company.type) }
        }
    }

    /// Suppliers are picked when the company opens, so a new product goes straight to its price.
    private func itemChosen(_ id: String) { showPrice(id) }

    private func openItem(_ id: String) { showPrice(id) }

    /// The price page follows the supplier question, unless the player only stepped out to look at an owner.
    private func supplierClosed() {
        guard ownerTrip == nil, let id = pendingPrice else { return }
        pendingPrice = nil
        showPrice(id)
    }

    private func openOwner(_ ref: SupplierOwnerRef, from s: SupplierSubject) {
        let t: AppTab = store.tab
        ownerTrip = OwnerTrip(subject: s, tab: t, depth: store.path(for: t).count)
        supplierFor = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            store.push(.supplierOwner(ref), on: t)
            ownerTrip?.shown = true
        }
    }

    private var ownerTripDepth: Int {
        guard let trip = ownerTrip else { return -1 }
        return store.path(for: trip.tab).count
    }

    /// Notes when the owner card is on screen, and brings the chooser back once the player leaves it.
    private func ownerTripMoved(_ depth: Int) {
        guard var trip = ownerTrip, depth >= 0 else { return }
        if depth > trip.depth {
            trip.shown = true
            ownerTrip = trip
        } else if trip.shown {
            ownerTrip = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { supplierFor = trip.subject }
        }
    }

    /// Closes the product page, asks the supplier question, then brings the product page back.
    private func restock(_ id: String) {
        guard let ask = (store.engine ?? engine).supplyAsk(companyID: company.id, itemID: id) else { return }
        priceFor = nil
        pendingPrice = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { supplierFor = SupplierSubject(ask, itemID: id) }
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
