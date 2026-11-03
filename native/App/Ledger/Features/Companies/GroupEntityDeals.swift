import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// An entity's deals behind a small Buy / Sell / Offers control: rivals to buy and franchise brands to join, selling the company, and
/// the offers and stakes that come to it (franchise applications, co-owners and their buy-backs, hosting, ventures).
struct GroupEntityDeals: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var part: DealPart = .buy

    enum DealPart: String, CaseIterable, Hashable { case buy = "Buy", sell = "Sell", offers = "Offers" }

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
        VStack(alignment: .leading, spacing: 12) {
            SegmentedPill(items: DealPart.allCases, title: { (p: DealPart) -> String in p.rawValue }, selection: $part, identifier: { (p: DealPart) -> String in "group-deals-\(p.rawValue)" })
            switch part {
            case .buy: buy(cos)
            case .sell: sell(cos)
            case .offers: offers(cos)
            }
        }
    }

    // MARK: Buy

    @ViewBuilder private func buy(_ cos: [Company]) -> some View {
        let open: [Company] = cos.filter { (c: Company) -> Bool in c.status == .open }
        let brands = engine.franchiseBrands()
        VStack(alignment: .leading, spacing: 8) {
            if open.isEmpty {
                Text("Open this company to look at rivals you could buy.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            } else {
                Button { Haptics.tap(); store.openMarket(companyID: entity.companyID) } label: {
                    CardRow(glyph: Glyph.market, title: "Rivals you could buy", subtitle: "Pick a rival in the market; the price and what it becomes are agreed there.")
                }.buttonStyle(PressableStyle())
            }
            NavigationLink { FranchisesView() } label: {
                CardRow(glyph: Glyph.group, title: "Brands that take franchisees",
                        subtitle: brands.isEmpty ? "No brand is looking for franchisees right now." : "\(brands.count) \(brands.count == 1 ? "brand" : "brands") \u{00B7} apply, meet them, agree terms",
                        value: brands.isEmpty ? "" : "\(brands.count)")
            }.buttonStyle(PressableStyle())
        }
    }

    // MARK: Sell

    @ViewBuilder private func sell(_ cos: [Company]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(cos) { (c: Company) in
                if cos.count > 1 { Text(c.name.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold) }
                CompanySaleSection(engine: engine, company: c)
            }
        }
    }

    // MARK: Offers

    @ViewBuilder private func offers(_ cos: [Company]) -> some View {
        let franchisors: [Company] = cos.filter { (c: Company) -> Bool in engine.isFranchisor(companyID: c.id) }
        VStack(alignment: .leading, spacing: 12) {
            if !franchisors.isEmpty { applicants(franchisors) }
            if let first = cos.first(where: { (c: Company) -> Bool in c.type != "hold" }) ?? cos.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("STAKES AND OWNERS").capsLabel()
                    CompanyOwnershipSection(engine: engine, company: first)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("OTHER GROUP DEALS").capsLabel()
                HostingSection(engine: engine)
            }
        }
    }

    private func applicants(_ franchisors: [Company]) -> some View {
        let chains = engine.chainSummaries
        return VStack(alignment: .leading, spacing: 6) {
            Text("FRANCHISE OFFERS").capsLabel()
            ForEach(franchisors) { (c: Company) in
                let chain = chains.first { (s: Chains.Summary) -> Bool in s.stores.contains { (l: Chains.StoreLine) -> Bool in l.id == c.id } }
                let cur: Currency = engine.currency(for: c)
                ForEach(engine.franchiseApplicants(companyID: c.id)) { a in
                    NavigationLink { FranchiseTalkView(companyID: c.id, applicantID: a.id) } label: {
                        CardRow(glyph: Glyph.person, title: "\(a.name) applies to \(chain?.name ?? c.name)",
                                subtitle: "\(a.experience) yr experience \u{00B7} own money \(cur.tidyShort(a.capital))", value: "Talk")
                    }.buttonStyle(PressableStyle())
                }
            }
        }
    }
}
