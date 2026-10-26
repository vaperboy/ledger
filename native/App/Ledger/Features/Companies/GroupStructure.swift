import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// What needs the owner at group level: board decisions, franchise applicants, chains with stores losing money, franchise units
/// below the brand's standard, managers nobody has met. Each row opens the record it concerns.
struct GroupAttention: View {
    var engine: GameEngine

    private struct Item: Identifiable {
        enum Target { case board(String), chain(Int), company(Int, CompanySection), none }
        var id: String
        var title: String
        var sub: String
        var tint: Color
        var target: Target
    }

    private var items: [Item] {
        var out: [Item] = []
        for key in engine.boardKeys where engine.boardIsActive(key: key) {
            let n = engine.boardMeetings(key: key).filter { $0.status.isEmpty }.count
            if n > 0 { out.append(Item(id: "b" + key, title: "Board of \(engine.boardName(key: key)): \(n) to decide", sub: "Approve or decline at the board.", tint: Theme.caution, target: .board(key))) }
        }
        let chains = engine.chainSummaries
        for c in engine.state.companies where c.status.isLive && engine.isFranchisor(companyID: c.id) {
            let n = engine.franchiseApplicants(companyID: c.id).count
            if n > 0 {
                let chain = chains.first { $0.stores.contains { $0.id == c.id } }
                out.append(Item(id: "f\(c.id)", title: "\(chain?.name ?? c.name) franchise: \(n) \(n == 1 ? "applicant" : "applicants")", sub: "Talk to them before they lose interest.", tint: Theme.gain,
                                target: chain.map { .chain($0.id) } ?? .company(c.id, .chain)))
            }
        }
        for s in chains {
            let losing = s.stores.filter { $0.status == .open && $0.profit < 0 }.count
            if losing > 0 && s.stores.count > 1 {
                out.append(Item(id: "c\(s.id)", title: "\(s.name): \(losing) of \(s.stores.count) stores lost money", sub: "Compare the stores on the chain page.", tint: Theme.loss, target: .chain(s.id)))
            }
        }
        for c in engine.state.companies where c.status == .open && !c.value("franchise").isNull {
            let minQ = engine.franchiseMinimumQuality(companyID: c.id)
            if c.quality < minQ {
                out.append(Item(id: "q\(c.id)", title: "\(c.name) is below \(c.value("franchise")["brandName"].string)'s standard", sub: "Quality \(Int(c.quality.rounded())) of \(Int(minQ)) needed. The brand warns, then ends the contract.", tint: Theme.loss, target: .company(c.id, .operations)))
            }
        }
        let due = engine.managersDueMeeting.filter { $0.status == .open }
        if !due.isEmpty {
            out.append(Item(id: "m", title: "\(due.count) \(due.count == 1 ? "manager has" : "managers have") not met you for 8 weeks or more", sub: "A manager left alone slowly works worse. Call a meeting under Group office below.", tint: Theme.caution, target: .none))
        }
        return out
    }

    var body: some View {
        let list = items
        if !list.isEmpty {
            LedgerSection(title: "Needs you", trailing: { Text("\(list.count)").font(.system(size: 11)).foregroundStyle(Theme.caution) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.prefix(8).enumerated()), id: \.element.id) { n, it in
                        if n > 0 { Hairline() }
                        row(it)
                    }
                    if list.count > 8 { Text("And \(list.count - 8) more below.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6) }
                }
            }
        }
    }

    @ViewBuilder private func row(_ it: Item) -> some View {
        switch it.target {
        case .board(let key): NavigationLink { BoardView(key: key) } label: { GroupLinkRow(title: it.title, sub: it.sub, subTint: it.tint) }.buttonStyle(.plain)
        case .chain(let id): NavigationLink { ChainView(chainID: id) } label: { GroupLinkRow(title: it.title, sub: it.sub, subTint: it.tint) }.buttonStyle(.plain)
        case .company(let id, let sec): NavigationLink(value: CompanyRoute.companyAt(id, sec)) { GroupLinkRow(title: it.title, sub: it.sub, subTint: it.tint) }.buttonStyle(.plain)
        case .none:
            VStack(alignment: .leading, spacing: 1) {
                Text(it.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                Text(it.sub).font(.system(size: 11)).foregroundStyle(it.tint)
            }.padding(.vertical, 9)
        }
    }
}

/// Ownership and structure: holdings and the companies under them, chains and their stores, franchises you run and units you hold
/// under someone's brand, and the companies that stand alone. Summaries scale with the group; each row opens the holding, chain or company.
struct GroupStructureOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var openBrand: String?
    @State private var aloneQuery = ""
    @State private var aloneAll = false

    var body: some View {
        let live = engine.state.companies.filter { $0.status.isLive && $0.type != "hold" }
        let holdings = engine.holdingCompanies
        let chains = engine.chainSummaries
        let franchisors = live.filter { engine.isFranchisor(companyID: $0.id) }
        let franchised = live.filter { !$0.value("franchise").isNull }
        let alone = live.filter { $0.value("chain").isNull && $0.value("franchise").isNull && $0.holdingID == 0 && !engine.isFranchisor(companyID: $0.id) }
        let units = franchisors.reduce(0) { $0 + engine.franchiseSystem(companyID: $1.id)["units"].array.count }
        LedgerSection("Structure") {
            VStack(alignment: .leading, spacing: 0) {
                KeyFigures(items: [
                    .init(label: "Companies", value: "\(live.count)", sub: "\(Set(live.map { $0.cityID }).count) \(Set(live.map { $0.cityID }).count == 1 ? "city" : "cities")"),
                    .init(label: "Holdings", value: "\(holdings.count)", sub: "\(live.filter { $0.holdingID != 0 }.count) held"),
                    .init(label: "Chains", value: "\(chains.count)", sub: "\(chains.reduce(0) { $0 + $1.stores.count }) \(chains.reduce(0) { $0 + $1.stores.count } == 1 ? "store" : "stores")"),
                    .init(label: "Your franchise units", value: "\(units)", sub: "run by others"),
                    .init(label: "Franchisee", value: "\(franchised.count)", sub: "under a brand"),
                    .init(label: "Stand alone", value: "\(alone.count)", sub: "no chain, franchise or holding"),
                ])
                if live.isEmpty { Text("Start a company to build a group.").font(.caption).foregroundStyle(Theme.ivoryFaint).padding(.top, 8) }
            }
        }
        holdingsSection(holdings, live: live)
        chainsSection(chains)
        franchiseSection(franchisors, franchised, chains: chains)
        standAloneSection(alone)
    }

    // MARK: Stand alone

    /// Companies that belong to no chain, franchise or holding: key figures per company, opened in place (Back returns here).
    @ViewBuilder private func standAloneSection(_ alone: [Company]) -> some View {
        if !alone.isEmpty {
            let q = aloneQuery.trimmingCharacters(in: .whitespaces)
            let rows = alone.map { (co: $0, h: engine.companyHealth($0)) }
                .filter { q.isEmpty || $0.co.name.localizedCaseInsensitiveContains(q) || engine.cityName($0.co).localizedCaseInsensitiveContains(q) || engine.tradeName($0.co).localizedCaseInsensitiveContains(q) }
                .sorted { $0.h.profitTTM < $1.h.profitTTM }
            let cap = aloneAll || !q.isEmpty ? rows.count : 8
            LedgerSection(title: "Stand alone", trailing: { Text("\(alone.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    if alone.count > 8 {
                        TextField("Name, city or trade", text: $aloneQuery).textFieldStyle(.plain).font(.system(size: 13.5)).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.vertical, 8).overlay(alignment: .bottom) { Hairline() }
                    }
                    if rows.isEmpty { Text("No company matches.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).padding(.vertical, 8) }
                    ForEach(Array(rows.prefix(cap).enumerated()), id: \.element.co.id) { n, r in
                        if n > 0 { Hairline() }
                        NavigationLink(value: CompanyRoute.company(r.co.id)) {
                            GroupLinkRow(title: r.co.name,
                                         sub: "\(engine.tradeName(r.co)) · \(engine.cityName(r.co)) · \(r.h.label) · value \(store.short(r.h.value, in: r.co))",
                                         trailing: store.short(r.h.profitTTM, in: r.co) + " / yr", tint: r.h.profitTTM < 0 ? Theme.loss : Theme.ivory,
                                         subTint: r.h.label == "Struggling" || r.h.label == "Tight" ? Theme.caution : Theme.ivoryFaint)
                        }.buttonStyle(.plain)
                    }
                    if rows.count > 8 && q.isEmpty {
                        Button(aloneAll ? "Show fewer" : "Show all \(rows.count)") { aloneAll.toggle() }.font(.system(size: 12)).foregroundStyle(Theme.gold).buttonStyle(.plain).padding(.top, 6)
                    }
                    Text("Profit is the last twelve months. Comparisons across all companies stay under Company.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                }
            }
        }
    }

    // MARK: Holdings

    @ViewBuilder private func holdingsSection(_ holdings: [Company], live: [Company]) -> some View {
        let free = engine.companiesForHolding
        if !holdings.isEmpty || !free.isEmpty {
            LedgerSection(title: "Holding companies", trailing: { Text("\(holdings.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(holdings.enumerated()), id: \.element.id) { n, h in
                        if n > 0 { Hairline() }
                        let subs = live.filter { $0.holdingID == h.id }
                        NavigationLink(value: CompanyRoute.companyAt(h.id, .holding)) {
                            GroupLinkRow(title: h.name,
                                         sub: subs.isEmpty ? "No companies under it yet" : "\(subs.count) \(subs.count == 1 ? "company" : "companies"): " + subs.prefix(3).map { $0.name }.joined(separator: ", ") + (subs.count > 3 ? "…" : ""),
                                         trailing: store.short(Valuation.companyValue(h, state: engine.state, trades: engine.data.catalog), in: h))
                        }.buttonStyle(.plain)
                    }
                    if !holdings.isEmpty && !free.isEmpty {
                        Text("\(free.count) limited \(free.count == 1 ? "company is" : "companies are") still owned by you directly. Put them under a holding on its page.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                    }
                    if holdings.isEmpty {
                        NavigationLink { NewHoldingView() } label: {
                            GroupLinkRow(title: "Set up a holding company", sub: "Dividends into it are taxed far lower; companies it owns 90% of share profits and losses for tax.")
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Chains

    @ViewBuilder private func chainsSection(_ chains: [Chains.Summary]) -> some View {
        let loose = engine.looseStoreGroups
        if !chains.isEmpty || !loose.isEmpty {
            LedgerSection(title: "Chains", trailing: { Text("\(chains.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(chains.enumerated()), id: \.element.id) { n, s in
                        if n > 0 { Hairline() }
                        let cities = Set(s.stores.map { $0.cityName }).count
                        let losing = s.stores.filter { $0.status == .open && $0.profit < 0 }.count
                        NavigationLink { ChainView(chainID: s.id) } label: {
                            GroupLinkRow(title: s.name,
                                         sub: "\(s.stores.count) \(s.stores.count == 1 ? "store" : "stores") in \(cities) \(cities == 1 ? "city" : "cities") · \(s.reach.label)" + (s.franchiseUnits > 0 ? " · \(s.franchiseUnits) franchise units" : "") + (losing > 0 ? " · \(losing) losing money" : ""),
                                         trailing: engine.homeCurrency.tidyShort(s.profit) + " / mo", tint: s.profit < 0 ? Theme.loss : Theme.ivory,
                                         subTint: losing > 0 ? Theme.caution : Theme.ivoryFaint)
                        }.buttonStyle(.plain)
                    }
                    ForEach(Array(loose.enumerated()), id: \.element.id) { n, g in
                        if n > 0 || !chains.isEmpty { Hairline() }
                        if let id = g.companyIDs.first {
                            NavigationLink(value: CompanyRoute.companyAt(id, .chain)) {
                                GroupLinkRow(title: g.name, sub: "\(g.companyIDs.count) \(engine.data.catalog[g.tradeID]?.name.lowercased() ?? "stores") under one name · register them as a chain", subTint: Theme.gold)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Franchises

    @ViewBuilder private func franchiseSection(_ franchisors: [Company], _ franchised: [Company], chains: [Chains.Summary]) -> some View {
        let brands = engine.franchiseBrands()
        let byBrand = Dictionary(grouping: franchised) { $0.value("franchise")["brandName"].string }
        let brandNames = byBrand.keys.sorted()
        if !franchisors.isEmpty || !franchised.isEmpty || !brands.isEmpty {
            LedgerSection("Franchises") {
                VStack(alignment: .leading, spacing: 0) {
                    if !franchisors.isEmpty { Text("Your concept, run by others").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 6) }
                    ForEach(Array(franchisors.enumerated()), id: \.element.id) { n, c in
                        if n > 0 { Hairline() }
                        franchisorRow(c, chain: chains.first { $0.stores.contains { $0.id == c.id } })
                    }
                    if !franchised.isEmpty {
                        Text("You as franchisee").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).padding(.top, franchisors.isEmpty ? 0 : 12).padding(.bottom, 6)
                    }
                    ForEach(Array(brandNames.enumerated()), id: \.element) { n, b in
                        if n > 0 { Hairline() }
                        brandRow(b, byBrand[b] ?? [])
                    }
                    if !brands.isEmpty {
                        if !franchisors.isEmpty || !franchised.isEmpty { Hairline() }
                        NavigationLink { FranchisesView() } label: {
                            GroupLinkRow(title: "Join a franchise", sub: "A known brand, their rules, a fee · \(brands.count) \(brands.count == 1 ? "brand takes" : "brands take") franchisees", subTint: Theme.gold)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func franchisorRow(_ c: Company, chain: Chains.Summary?) -> some View {
        let f = engine.franchiseSystem(companyID: c.id)
        let apps = engine.franchiseApplicants(companyID: c.id).count
        let row = GroupLinkRow(title: "\(chain?.name ?? c.name) franchise",
                               sub: "\(f["units"].array.count) \(f["units"].array.count == 1 ? "unit" : "units") · \(apps) applying · fee \(engine.currency(for: c).tidyShort(f["fee"].double)) · royalty \(Currency.percent(f["roy"].double, decimals: 0))",
                               trailing: engine.currency(for: c).tidyShort(f["income"].double) + " / wk", subTint: apps > 0 ? Theme.gain : Theme.ivoryFaint)
        if let chain {
            NavigationLink { ChainView(chainID: chain.id) } label: { row }.buttonStyle(.plain)
        } else {
            NavigationLink(value: CompanyRoute.companyAt(c.id, .chain)) { row }.buttonStyle(.plain)
        }
        // Applicants open the same talk as under Company > Chain: one record, one set of actions (offer, accept, walk away).
        let cur = engine.currency(for: c)
        ForEach(engine.franchiseApplicants(companyID: c.id)) { a in
            NavigationLink { FranchiseTalkView(companyID: c.id, applicantID: a.id) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                        Text("Applicant · \(engine.data.countries.city(a.cityID, preferring: c.countryCode)?.city.name ?? "") · \(a.experience) yr experience · own money \(cur.tidyShort(a.capital))")
                            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text("Talk  ›").font(.system(size: 12.5)).foregroundStyle(Theme.gold)
                }.padding(.vertical, 8).padding(.leading, Theme.Space.m).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private func brandRow(_ brand: String, _ cos: [Company]) -> some View {
        if cos.count == 1, let c = cos.first {
            NavigationLink(value: CompanyRoute.companyAt(c.id, .chain)) {
                GroupLinkRow(title: c.name, sub: "Franchisee of \(brand) · royalty \(Currency.percent(c.value("franchise")["roy"].double, decimals: 1)) · \(engine.cityName(c))")
            }.buttonStyle(.plain)
        } else {
            Button { openBrand = openBrand == brand ? nil : brand } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(brand).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text("\(cos.count) \(cos.count == 1 ? "unit" : "units") under this brand").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer()
                    Image(systemName: openBrand == brand ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }.padding(.vertical, 9).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if openBrand == brand {
                ForEach(cos) { c in
                    NavigationLink(value: CompanyRoute.companyAt(c.id, .chain)) {
                        GroupLinkRow(title: c.name, sub: engine.cityName(c))
                    }.buttonStyle(.plain).padding(.leading, Theme.Space.m)
                }
            }
        }
    }
}
