import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Everything about chain and franchise for ONE company, as plain content (a VStack: the host page owns the scroll area):
/// a status line, then the stage the company is at. Not a chain: the requirements checklist and registration. A store of a chain:
/// its place, new stores, companies that can join, supply overview, and franchising when it is the chain's flagship. Outside a chain:
/// franchising it out. A franchisee: its agreement. Supply between own companies stays in Operations > Suppliers (one row).
struct EntityExpansionView: View {
    @EnvironmentObject var store: GameStore
    let companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            content(e, co)
        } else {
            Text("This company no longer exists.").textStyle(.body, tint: Theme.inkFaint)
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        let chain: Chains.Summary? = e.chainSummary(containing: co.id)
        let franchisee: Bool = !co.value("franchise").isNull
        let live: Bool = co.status == .open || co.status == .closed
        let relevant: Bool = CompanyChain.isRelevant(co, e)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            statusHeader(e, co, chain: chain, franchisee: franchisee)
            if relevant && live {
                stage(e, co, chain: chain, franchisee: franchisee)
            } else {
                Text("Not available for this company yet.").textStyle(.caption, tint: Theme.inkFaint)
            }
            EntityAbroadSection(companyID: co.id)
        }
    }

    @ViewBuilder private func stage(_ e: GameEngine, _ co: Company, chain: Chains.Summary?, franchisee: Bool) -> some View {
        if let sum = chain {
            let cur: Currency = e.currency(for: co)
            StoreInChainCard(engine: e, company: co, summary: sum)
            ChainNewStore(engine: e, summary: sum, currency: cur)
            ChainJoin(engine: e, summary: sum)
            ChainSupplyOverview(engine: e, summary: sum, currency: cur)
            if sum.franchisingCompanyID == co.id { FranchisorCard(engine: e, company: co) }
        } else if franchisee {
            FranchiseeCard(engine: e, company: co)
        } else {
            GrowIntoChain(engine: e, company: co)
            if e.canFranchise(companyID: co.id) || e.isFranchisor(companyID: co.id) {
                FranchisorCard(engine: e, company: co)
            }
        }
        NavigationLink(value: CompanyRoute.companyAt(co.id, .operations)) {
            CardRow(glyph: Glyph.market, title: "Suppliers and own-company supply", subtitle: "Prices, terms and risks, in Manage")
        }.buttonStyle(PressableStyle())
    }

    private func statusHeader(_ e: GameEngine, _ co: Company, chain: Chains.Summary?, franchisee: Bool) -> some View {
        var title: String = "One company, not a chain yet"
        if let chain {
            let n: Int = chain.stores.count
            title = "Chain of \(n) \(n == 1 ? "store" : "stores")"
            if e.isFranchisor(companyID: co.id) {
                let units: Int = e.franchiseSystem(companyID: co.id)["units"].array.count
                title += " \u{00B7} franchisor with \(units) \(units == 1 ? "franchisee" : "franchisees")"
            }
        } else if franchisee {
            title = "Franchisee of \(co.value("franchise")["brandName"].string)"
        } else if e.isFranchisor(companyID: co.id) {
            let units: Int = e.franchiseSystem(companyID: co.id)["units"].array.count
            title = "Franchisor with \(units) \(units == 1 ? "franchisee" : "franchisees")"
        }
        // The stage the company is at is the lead line of the tab; the steps for the next stage follow under it.
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("Stage").textStyle(.label, tint: Theme.inkFaint)
            Text(title.tidyText).textStyle(.figure)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
