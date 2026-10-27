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

    struct Item: Identifiable {
        enum Target { case board(String), chain(Int), company(Int, CompanySection), none }
        var id: String
        var title: String
        var sub: String
        var tint: Color
        var target: Target
    }

    var items: [Item] {
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
            MoreBlock(title: "Needs you", card: false, trailing: { RedBubble(count: list.count, size: .small) }) {
                ForEach(list.prefix(8)) { it in row(it) }
                if list.count > 8 { Text("And \(list.count - 8) more under Structure and Board.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            }
        }
    }

    private func card(_ it: Item) -> some View {
        let linked: Bool
        switch it.target { case .none: linked = false; default: linked = true }
        return CardRow(glyph: Glyph.warning, title: it.title, subtitle: it.sub, chevron: linked)
    }

    @ViewBuilder private func row(_ it: Item) -> some View {
        switch it.target {
        case .board(let key): NavigationLink { BoardView(key: key) } label: { card(it) }.buttonStyle(.plain)
        case .chain(let id): NavigationLink { ChainView(chainID: id) } label: { card(it) }.buttonStyle(.plain)
        case .company(let id, let sec): NavigationLink(value: CompanyRoute.companyAt(id, sec)) { card(it) }.buttonStyle(.plain)
        case .none: card(it)
        }
    }
}


/// Ownership and structure: holdings and the companies under them, chains and their stores, franchises you run and units you hold
/// under someone's brand, and the companies that stand alone. Summaries scale with the group; each row opens the holding, chain or company.
struct GroupStructureOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    /// Which sections to draw (the More menu shows one at a time). All by default.
    enum Part: CaseIterable { case figures, holdings, chains, franchises, standAlone, dividends }
    var parts: Set<Part> = Set(Part.allCases)
    @State private var openBrand: String?
    @State private var aloneQuery = ""
    @State private var aloneAll = false

    var body: some View {
        let live: [Company] = engine.state.companies.filter { $0.status.isLive && $0.type != "hold" }
        let holdings: [Company] = engine.holdingCompanies
        let chains: [Chains.Summary] = engine.chainSummaries
        let franchisors: [Company] = live.filter { engine.isFranchisor(companyID: $0.id) }
        let franchised: [Company] = live.filter { !$0.value("franchise").isNull }
        let alone: [Company] = live.filter { $0.value("chain").isNull && $0.value("franchise").isNull && $0.holdingID == 0 && !engine.isFranchisor(companyID: $0.id) }
        VStack(alignment: .leading, spacing: 16) {
            if parts.contains(.figures) { figuresSection(live, holdings: holdings, chains: chains, franchisors: franchisors, franchised: franchised, alone: alone) }
            if parts.contains(.holdings) { holdingsSection(holdings, live: live) }
            if parts.contains(.chains) { chainsSection(chains) }
            if parts.contains(.franchises) { franchiseSection(franchisors, franchised, chains: chains) }
            if parts.contains(.standAlone) { standAloneSection(alone) }
            if parts.contains(.dividends) { dividendsAndTax(live) }
        }
    }

    // MARK: Small pieces

    private func countNote(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).padding(.horizontal, 2)
    }

    // MARK: Figures

    private func figuresSection(_ live: [Company], holdings: [Company], chains: [Chains.Summary], franchisors: [Company], franchised: [Company], alone: [Company]) -> some View {
        let units: Int = franchisors.reduce(0) { $0 + engine.franchiseSystem(companyID: $1.id)["units"].array.count }
        let cityCount: Int = Set(live.map { $0.cityID }).count
        let storeCount: Int = chains.reduce(0) { $0 + $1.stores.count }
        let items: [KeyFigures.Item] = [
            .init(label: "Companies", value: "\(live.count)", sub: "\(cityCount) \(cityCount == 1 ? "city" : "cities")"),
            .init(label: "Holdings", value: "\(holdings.count)", sub: "\(live.filter { $0.holdingID != 0 }.count) held"),
            .init(label: "Chains", value: "\(chains.count)", sub: "\(storeCount) \(storeCount == 1 ? "store" : "stores")"),
            .init(label: "Franchised out", value: "\(units)", sub: "run by others"),
            .init(label: "Franchise you hold", value: "\(franchised.count)", sub: "under a brand"),
            .init(label: "Stand alone", value: "\(alone.count)", sub: "no group link"),
        ]
        return MoreBlock("Structure") {
            VStack(alignment: .leading, spacing: 8) {
                FigureStrip(items: items, columns: 3)
                if live.isEmpty { Text("Start a company to build a group.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
            }
        }
    }

    // MARK: Dividends and group tax

    private func dividendSub(_ c: Company) -> String {
        let cur: Currency = engine.currency(for: c)
        let d = engine.lastDividendDecision(companyID: c.id)
        let t = engine.groupTaxContribution(companyID: c.id)
        let net: (_ v: (out: Double, in: Double)) -> Double = { $0.in - $0.out }
        let first: String = d.map { ($0.paid > 0 ? "Last quarter paid \(cur.tidyShort($0.paid))" : "Last quarter skipped") + " on profit \(cur.tidyShort($0.profit))" } ?? "No dividend decided yet"
        let second: String = t.map { " · group tax this year \(cur.tidyShort(net($0.thisYear))), last year \(cur.tidyShort(net($0.lastYear)))" } ?? ""
        return first + second
    }

    /// Last quarter's dividend decision and the group-tax position, per company, for the companies that have either. Read-only; each row opens the company's Finances.
    @ViewBuilder private func dividendsAndTax(_ live: [Company]) -> some View {
        let rows: [Company] = live.filter { engine.lastDividendDecision(companyID: $0.id) != nil || engine.groupTaxContribution(companyID: $0.id) != nil }
        if !rows.isEmpty {
            MoreBlock(title: "Dividends and group tax", card: false, trailing: { countNote(rows.count) }) {
                ForEach(rows.prefix(8)) { c in
                    NavigationLink(value: CompanyRoute.companyAt(c.id, .finances)) {
                        CardRow(glyph: Glyph.reports, title: c.name, subtitle: dividendSub(c))
                    }.buttonStyle(.plain)
                }
                if rows.count > 8 { footnote("The rest are in each company's Finances.") }
                footnote("Group tax is what came in (+) or went out (−) between group companies. The policy is set in the company's owners.")
            }
        }
    }

    // MARK: Stand alone

    private func aloneRows(_ alone: [Company]) -> [(co: Company, h: CompanyHealth)] {
        let q: String = aloneQuery.trimmingCharacters(in: .whitespaces)
        return alone.map { (co: $0, h: engine.companyHealth($0)) }
            .filter { q.isEmpty || $0.co.name.localizedCaseInsensitiveContains(q) || engine.cityName($0.co).localizedCaseInsensitiveContains(q) || engine.tradeName($0.co).localizedCaseInsensitiveContains(q) }
            .sorted { $0.h.profitTTM < $1.h.profitTTM }
    }

    private var aloneSearch: some View {
        Card(padding: 10, radius: Theme.Radius.table) {
            HStack(spacing: 8) {
                GlyphView(glyph: Glyph.search, size: 16, weight: 1.5, tint: Theme.ivoryFaint)
                TextField("Name, city or trade", text: $aloneQuery).textFieldStyle(.plain).font(.system(size: 13.5))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
    }

    private func aloneRow(_ co: Company, _ h: CompanyHealth) -> some View {
        let sub: String = "\(engine.tradeName(co)) · \(engine.cityName(co)) · \(h.label) · value \(store.short(h.value, in: co))"
        return NavigationLink(value: CompanyRoute.company(co.id)) {
            CardRow(glyph: Glyph.home, title: co.name, subtitle: sub, value: store.short(h.profitTTM, in: co) + " / yr", valueTint: h.profitTTM < 0 ? Theme.loss : Theme.ivory)
        }.buttonStyle(.plain)
    }

    /// Companies that belong to no chain, franchise or holding: key figures per company, opened in place (Back returns here).
    @ViewBuilder private func standAloneSection(_ alone: [Company]) -> some View {
        if !alone.isEmpty {
            let q: String = aloneQuery.trimmingCharacters(in: .whitespaces)
            let rows = aloneRows(alone)
            let cap: Int = aloneAll || !q.isEmpty ? rows.count : 8
            MoreBlock(title: "Stand alone", card: false, trailing: { countNote(alone.count) }) {
                if alone.count > 8 { aloneSearch }
                if rows.isEmpty { Text("No company matches.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                ForEach(rows.prefix(cap), id: \.co.id) { r in aloneRow(r.co, r.h) }
                if rows.count > 8 && q.isEmpty {
                    QuietButton(title: aloneAll ? "Show fewer" : "Show all \(rows.count)") { aloneAll.toggle() }
                }
                footnote("Profit is the last twelve months. Comparisons across all companies stay under Company.")
            }
        }
    }

    // MARK: Holdings

    private func holdingSub(_ subs: [Company]) -> String {
        if subs.isEmpty { return "No companies under it yet" }
        let names: String = subs.prefix(3).map { $0.name }.joined(separator: ", ")
        return "\(subs.count) \(subs.count == 1 ? "company" : "companies"): " + names + (subs.count > 3 ? "…" : "")
    }

    @ViewBuilder private func holdingsSection(_ holdings: [Company], live: [Company]) -> some View {
        let free = engine.companiesForHolding
        if !holdings.isEmpty || !free.isEmpty {
            MoreBlock(title: "Holding companies", card: false, trailing: { countNote(holdings.count) }) {
                ForEach(holdings) { h in
                    let subs: [Company] = live.filter { $0.holdingID == h.id }
                    NavigationLink(value: CompanyRoute.companyAt(h.id, .holding)) {
                        CardRow(glyph: Glyph.bank, title: h.name, subtitle: holdingSub(subs),
                                value: store.short(Valuation.companyValue(h, state: engine.state, trades: engine.data.catalog), in: h))
                    }.buttonStyle(.plain)
                }
                if !holdings.isEmpty && !free.isEmpty {
                    footnote("\(free.count) limited \(free.count == 1 ? "company is" : "companies are") still owned by you directly. Put them under a holding on its page.")
                }
                if holdings.isEmpty {
                    NavigationLink { NewHoldingView() } label: {
                        CardRow(glyph: Glyph.hire, title: "Set up a holding company", subtitle: "Dividends into it are taxed far lower; companies it owns 90% of share profits and losses for tax.")
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Chains

    private func chainSub(_ s: Chains.Summary) -> String {
        let cities: Int = Set(s.stores.map { $0.cityName }).count
        let losing: Int = s.stores.filter { $0.status == .open && $0.profit < 0 }.count
        let base: String = "\(s.stores.count) \(s.stores.count == 1 ? "store" : "stores") in \(cities) \(cities == 1 ? "city" : "cities") · \(s.reach.label)"
        let units: String = s.franchiseUnits > 0 ? " · \(s.franchiseUnits) franchise units" : ""
        let bad: String = losing > 0 ? " · \(losing) losing money" : ""
        return base + units + bad
    }

    @ViewBuilder private func chainsSection(_ chains: [Chains.Summary]) -> some View {
        let loose = engine.looseStoreGroups
        if !chains.isEmpty || !loose.isEmpty {
            MoreBlock(title: "Chains", card: false, trailing: { countNote(chains.count) }) {
                ForEach(chains) { s in
                    NavigationLink { ChainView(chainID: s.id) } label: {
                        CardRow(glyph: Glyph.group, title: s.name, subtitle: chainSub(s), value: engine.homeCurrency.tidyShort(s.profit) + " / mo", valueTint: s.profit < 0 ? Theme.loss : Theme.ivory)
                    }.buttonStyle(.plain)
                }
                ForEach(loose) { g in
                    if let id = g.companyIDs.first {
                        NavigationLink(value: CompanyRoute.companyAt(id, .chain)) {
                            CardRow(glyph: Glyph.home, title: g.name, subtitle: "\(g.companyIDs.count) \(engine.data.catalog[g.tradeID]?.name.lowercased() ?? "stores") under one name · register them as a chain")
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Franchises

    @ViewBuilder private func franchiseSection(_ franchisors: [Company], _ franchised: [Company], chains: [Chains.Summary]) -> some View {
        let brands = engine.franchiseBrands()
        let byBrand: [String: [Company]] = Dictionary(grouping: franchised) { $0.value("franchise")["brandName"].string }
        let brandNames: [String] = byBrand.keys.sorted()
        if !franchisors.isEmpty || !franchised.isEmpty || !brands.isEmpty {
            MoreBlock("Franchises", card: false) {
                if !franchisors.isEmpty { groupLabel("Your concept, run by others") }
                ForEach(franchisors) { c in franchisorRow(c, chain: chains.first { $0.stores.contains { $0.id == c.id } }) }
                if !franchised.isEmpty { groupLabel("You as franchisee") }
                ForEach(brandNames, id: \.self) { b in brandRow(b, byBrand[b] ?? []) }
                if !brands.isEmpty {
                    NavigationLink { FranchisesView() } label: {
                        CardRow(glyph: Glyph.hire, title: "Join a franchise", subtitle: "A known brand, their rules, a fee · \(brands.count) \(brands.count == 1 ? "brand takes" : "brands take") franchisees")
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func franchisorCard(_ c: Company, chain: Chains.Summary?) -> some View {
        let f = engine.franchiseSystem(companyID: c.id)
        let apps: Int = engine.franchiseApplicants(companyID: c.id).count
        let unitCount: Int = f["units"].array.count
        let cur: Currency = engine.currency(for: c)
        let sub: String = "\(unitCount) \(unitCount == 1 ? "unit" : "units") · \(apps) applying · fee \(cur.tidyShort(f["fee"].double)) · royalty \(Currency.percent(f["roy"].double, decimals: 0))"
        return CardRow(glyph: Glyph.group, title: "\(chain?.name ?? c.name) franchise", subtitle: sub, value: cur.tidyShort(f["income"].double) + " / wk")
    }

    @ViewBuilder private func franchisorRow(_ c: Company, chain: Chains.Summary?) -> some View {
        if let chain {
            NavigationLink { ChainView(chainID: chain.id) } label: { franchisorCard(c, chain: chain) }.buttonStyle(.plain)
        } else {
            NavigationLink(value: CompanyRoute.companyAt(c.id, .chain)) { franchisorCard(c, chain: nil) }.buttonStyle(.plain)
        }
        // Applicants open the same talk as under Company > Chain: one record, one set of actions (offer, accept, walk away).
        let cur: Currency = engine.currency(for: c)
        ForEach(engine.franchiseApplicants(companyID: c.id)) { a in
            NavigationLink { FranchiseTalkView(companyID: c.id, applicantID: a.id) } label: {
                CardRow(glyph: Glyph.person, title: a.name,
                        subtitle: "Applicant · \(engine.data.countries.city(a.cityID, preferring: c.countryCode)?.city.name ?? "") · \(a.experience) yr experience · own money \(cur.tidyShort(a.capital))",
                        value: "Talk")
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private func brandRow(_ brand: String, _ cos: [Company]) -> some View {
        if cos.count == 1, let c = cos.first {
            NavigationLink(value: CompanyRoute.companyAt(c.id, .chain)) {
                CardRow(glyph: Glyph.home, title: c.name, subtitle: "Franchisee of \(brand) · royalty \(Currency.percent(c.value("franchise")["roy"].double, decimals: 1)) · \(engine.cityName(c))")
            }.buttonStyle(.plain)
        } else {
            Button { openBrand = openBrand == brand ? nil : brand } label: {
                CardRow(glyph: Glyph.group, title: brand, subtitle: "\(cos.count) \(cos.count == 1 ? "unit" : "units") under this brand", value: openBrand == brand ? "Hide" : "Show", chevron: false)
            }.buttonStyle(.plain)
            if openBrand == brand {
                ForEach(cos) { c in
                    NavigationLink(value: CompanyRoute.companyAt(c.id, .chain)) {
                        CardRow(glyph: Glyph.home, title: c.name, subtitle: engine.cityName(c))
                    }.buttonStyle(.plain).padding(.leading, Theme.Space.m)
                }
            }
        }
    }
}
