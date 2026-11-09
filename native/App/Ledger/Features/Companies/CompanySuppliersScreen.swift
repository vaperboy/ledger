import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

extension CompanySourcing {
    /// Whether this company buys anything from suppliers or sells to a company of yours (the same test the Manage row uses to show itself).
    static func isAvailable(engine: GameEngine, company: Company) -> Bool {
        engine.hasSupplyLines(companyID: company.id)
    }
}

/// What this company buys, as one list grouped by what is supplied. Each row names the item, the supplier in use, how good and how dependable
/// it is in words, and this week's cost against the week before; a tap opens the offers to compare and switch to. Payment terms, price talks and
/// the companies you supply are one tap further, on the detail page. A trade that buys nothing (a holding company) says so.
struct CompanySuppliersScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var picked: SupplyPick?
    @State private var showTerms = false

    struct SupplyPick: Identifiable, Equatable { var id: String }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            ScrollView {
                content(e, co)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: "Suppliers", subtitle: co.name, tab: .company)
            .centerSheet(item: $picked, category: .medium, tone: .info) { (p: SupplyPick) in SupplyOffersPopup(companyID: companyID, lineID: p.id).environmentObject(store) }
            .navigationDestination(isPresented: $showTerms) {
                SettingsPage(title: "Terms and deals", subtitle: co.name) { CompanySourcing(engine: e, company: co) }
            }
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        let groups: [SupplyGroup] = e.supplyLines(companyID: co.id)
        let cur: Currency = e.currency(for: co)
        if groups.isEmpty {
            empty(e, co)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                summary(groups, cur)
                ForEach(groups) { (g: SupplyGroup) in group(g, cur) }
                if CompanySourcing.isAvailable(engine: e, company: co) {
                    LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: Theme.inkSoft, title: "Terms and deals",
                              subtitle: "How you pay, price talks, lunch with a supplier, companies you supply", identifier: "suppliers-terms") { showTerms = true }
                        .padding(.horizontal, Theme.Space.m)
                        .glassSurface()
                }
            }
        }
    }

    // MARK: Parts

    private func summary(_ groups: [SupplyGroup], _ cur: Currency) -> some View {
        let rows: [SupplyRow] = groups.flatMap { $0.rows }
        let priced: [SupplyRow] = rows.filter { $0.weekly != nil }
        let now: Double = priced.reduce(0) { $0 + ($1.weekly ?? 0) }
        let before: Double = priced.reduce(0) { $0 + ($1.weeklyBefore ?? $1.weekly ?? 0) }
        let names: Int = Set(rows.map { $0.current }).count
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Bought from suppliers").capsLabel(Theme.ivoryFaint)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                SupplyCost(now: priced.isEmpty ? nil : now, before: before, currency: cur, step: .figure)
                if !priced.isEmpty { Text("a week").textStyle(.caption, tint: Theme.inkFaint) }
            }
            Text("\(rows.count) \(rows.count == 1 ? "thing" : "things") from \(names) \(names == 1 ? "supplier" : "suppliers"). Costs are set against last week.")
                .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private func group(_ g: SupplyGroup, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(g.name).capsLabel(Theme.ivoryFaint).padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(Array(g.rows.enumerated()), id: \.element.id) { (n: Int, r: SupplyRow) in
                    if n > 0 { Hairline() }
                    SupplyLineRow(row: r, currency: cur) { picked = SupplyPick(id: r.id) }
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
        }
    }

    @ViewBuilder private func empty(_ e: GameEngine, _ co: Company) -> some View {
        let holding: Bool = e.tradeInfo(companyID: co.id)?.family == "hold"
        if holding {
            EmptyState(glyph: Glyph.suppliers, title: "Buys nothing from suppliers",
                       message: "A holding company has no goods or services to buy. The companies it holds buy for themselves.")
        } else {
            EmptyState(glyph: Glyph.suppliers, title: "No suppliers yet", message: "What the business buys shows here once it is open.")
        }
    }
}
