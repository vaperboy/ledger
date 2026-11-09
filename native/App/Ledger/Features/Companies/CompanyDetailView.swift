import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum CompanySection: String, CaseIterable, Hashable {
    case overview = "Overview", projects = "Projects", staff = "Team", finances = "Stats", operations = "Manage"
    case salesMarket = "Sales"
    case marketing = "Marketing", customers = "Customers", market = "Market", setup = "Setup"
    case properties = "Properties", book = "Book"
    case energy = "Plant", salmon = "Fish", holding = "Holding", club = "Club"
    case chain = "Chain"
}

extension CompanySection {
    init?(key: String) {
        guard let s = CompanySection.allCases.first(where: { "\($0)" == key }) else { return nil }
        self = s
    }

    var shortTitle: String { rawValue }
}

/// The six sections of the company screen, in the fixed bar. Prices are set in Sales (on each item's page); Supply holds every supplier.
enum CompanyTab: String, CaseIterable, Hashable {
    case overview = "Overview", team = "Team", manage = "Manage", sales = "Sales", supply = "Supply", stats = "Stats"
    var id: String { rawValue.lowercased() }
}

/// The parts of Stats: the finance summary and its pages, how the company performs, and its customers.
enum StatsPart: String, CaseIterable, Hashable { case finances = "Finances", customers = "Customers" }

/// The parts of Sales: the sales table, and Projects for the companies that take projects (project businesses) only.
enum SalesPart: String, CaseIterable, Hashable { case sales = "Sales", projects = "Projects" }

enum OverviewPage: String, Hashable, Identifiable {
    case sales = "Sales", run = "Run the place", stats = "Money and stats", customers = "Customers", projects = "Projects"
    var id: String { rawValue }
}

struct CompanyDetailView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var part: String? = nil
    @State private var segment: CompanyTab
    @State private var statsPart: StatsPart = .finances
    @State private var salesPart: SalesPart = .sales
    @State private var moneyPart: CompanyMoneyPart = .summary
    @State private var opsPart: OpsPart = .setup
    @State private var heldOpsPart: OpsPart = .setup
    @State private var appliedPart = false

    init(companyID: Int, initial: CompanyTab? = nil, part: String? = nil) {
        self.companyID = companyID
        self.part = part
        _segment = State(initialValue: initial ?? .overview)
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), co.status == .setup {
            ScrollView {
                CompanySetupScreen(engine: e, company: co)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: "Setup", subtitle: co.name) { StatusChip(company: co) }
        } else if let e = store.engine, let co = e.state.company(companyID) {
            let tabs: [CompanyTab] = Self.tabs(co, e)
            let pagerSelection: Binding<CompanyTab> = Binding(get: { tabs.contains(segment) ? segment : CompanyTab.overview }, set: { segment = $0 })
            VStack(spacing: 0) {
                SegmentedPill(items: tabs, title: { $0.rawValue }, selection: $segment, identifier: { "company-tab-\($0.id)" })
                    .coachAnchor(.companyTabs)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xxs).padding(.bottom, Theme.Space.s)
                SegmentPager(items: tabs, selection: pagerSelection) { (t: CompanyTab) in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.l) {
                            content(t, co, e)
                        }
                        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.l)
                        .frame(maxWidth: 1100).frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                }
                .coachTopStrip(.companyPage, height: 150)
            }
            .appScreen(title: co.name, subtitle: ([e.tradeName(co), e.cityName(co)] + [contextLine(co, e)].compactMap { $0 }).joined(separator: " \u{00B7} ").tidyText) {
                HStack(spacing: Theme.Space.s) {
                    if co.status == .open { HealthChip(label: e.companyHealth(co).label) } else { StatusChip(company: co) }
                    ThumbnailView(kind: .trade, key: co.type, size: 36)
                }
            }
            .onAppear { applyPart(tabs) }
            .navigationDestination(isPresented: Binding(get: { opsPart != .setup }, set: { if !$0 { opsPart = .setup } })) {
                OpsPageDestination(part: opsPart == .setup ? heldOpsPart : opsPart, companyID: companyID)
            }
            .onChange(of: opsPart) { (_: OpsPart, new: OpsPart) in if new != .setup { heldOpsPart = new } }
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ tab: CompanyTab, _ co: Company, _ e: GameEngine) -> some View {
        let a: [CompanySection] = Self.availableSections(co, e)
        switch tab {
        case .overview:
            CompanyOverview(engine: e, company: co,
                            openPage: { (p: OverviewPage) in openPage(p, co, e) },
                            openTab: { (t: CompanyTab) in Motion.animate(Motion.quickAnimation) { segment = t } },
                            openOps: { (p: OpsPart) in opsPart = p },
                            openMoney: { (m: CompanyMoneyPart) in moneyPart = m; statsPart = .finances; Motion.animate(Motion.quickAnimation) { segment = .stats } })
            if JointVenturePartnersCard.applies(co, e) {
                if store.levelOpen(.jointVentures) { JointVenturePartnersCard(engine: e, company: co) } else { LevelLockCard(feature: .jointVentures) }
            }
        case .team:
            if a.contains(.staff) { CompanyTeam(engine: e, company: co) } else { CompanyHolding(engine: e, company: co) }
        case .manage:
            if a.contains(.operations) {
                CompanyOperations(engine: e, company: co, part: $opsPart)
            } else {
                CompanyClub(engine: e, company: co)
            }
        case .sales:
            salesContent(co, e)
        case .supply:
            CompanySupply(engine: e, company: co)
        case .stats:
            // A holding company sells to no one: no Customers part.
            let parts: [StatsPart] = co.type == "hold" ? [.finances] : StatsPart.allCases
            if parts.count > 1 {
                SegmentedPill(items: parts, title: { $0.rawValue }, selection: $statsPart, identifier: { "stats-part-\($0.rawValue.lowercased())" })
            }
            switch statsPart {
            case .finances:
                CompanyMoney(engine: e, company: co, part: $moneyPart)
                CompanyMorePages(engine: e, company: co, pages: [.book])
            case .customers:
                CompanyCustomers(engine: e, company: co)
            }
        }
    }

    /// Where the Overview's rows go: a section of the bar, in place.
    private func openPage(_ p: OverviewPage, _ co: Company, _ e: GameEngine) {
        switch p {
        case .sales: salesPart = .sales; show(.sales)
        case .run: show(.manage)
        case .stats: statsPart = .finances; show(.stats)
        case .customers: statsPart = .customers; show(.stats)
        case .projects: salesPart = .projects; show(.sales)
        }
    }

    private func show(_ t: CompanyTab) { Motion.animate(Motion.quickAnimation) { segment = t } }

    /// Sales: the items with their prices; project businesses also get a Projects part (nobody else has projects of their own).
    @ViewBuilder private func salesContent(_ co: Company, _ e: GameEngine) -> some View {
        if Self.hasProjects(co, e) {
            SegmentedPill(items: SalesPart.allCases, title: { $0.rawValue }, selection: $salesPart, identifier: { "sales-part-" + $0.rawValue.lowercased() })
            if salesPart == .projects {
                CompanyProjectsPage(engine: e, company: co)
            } else {
                CompanySales(engine: e, company: co)
            }
        } else {
            CompanySales(engine: e, company: co)
        }
    }

    /// Opens on the part a link asked for, once (the screen appears again when a page pushed from it is closed).
    private func applyPart(_ tabs: [CompanyTab]) {
        guard !appliedPart else { return }
        appliedPart = true
        guard let part else { return }
        if let t = CompanyTab(rawValue: part), tabs.contains(t) { segment = t; return }
        if let p = OverviewPage(rawValue: part) {
            if p == .customers { statsPart = .customers } else if p == .projects { salesPart = .projects }
            return
        }
        if let m = CompanyMoneyPart(rawValue: part) { moneyPart = m }
        if let o = OpsPart(rawValue: part) { opsPart = o }
        if let sp = StatsPart(rawValue: part) { statsPart = sp }
    }

    private func contextLine(_ co: Company, _ e: GameEngine) -> String? {
        var parts: [String] = []
        if let ch = e.chainOf(companyID: co.id) { parts.append("Store of " + (ch["name"].string.isEmpty ? "your chain" : ch["name"].string)) }
        if co.holdingID != 0, let h = e.state.company(co.holdingID) { parts.append("Under " + h.name) }
        let runner: String = CompanyRunner.of(co, e).short
        if !runner.isEmpty { parts.append(runner) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// The sections of the bar this company has. A holding has its management under Team (no staff list), a football club its own page
    /// under Manage, a company still being set up has neither Manage nor Sales yet. Supply is for every company that sells.
    static func tabs(_ co: Company, _ e: GameEngine) -> [CompanyTab] {
        let a = availableSections(co, e)
        var out: [CompanyTab] = [.overview]
        if a.contains(.staff) || a.contains(.holding) { out.append(.team) }
        if a.contains(.operations) || a.contains(.club) { out.append(.manage) }
        if a.contains(.operations) { out.append(.sales); out.append(.supply) }
        out.append(.stats)
        return out
    }

    static func isLeaf(_ s: CompanySection) -> Bool {
        switch s {
        case .market, .setup, .book, .energy, .salmon, .club, .chain: return true
        default: return false
        }
    }

    /// The section of the bar an old section key opens, or nil for a page of its own (`isLeaf`) that is pushed instead.
    static func tab(for section: CompanySection, _ co: Company, _ e: GameEngine) -> CompanyTab? {
        let a = availableSections(co, e)
        switch section {
        case .overview: return .overview
        case .staff, .holding: return (a.contains(.staff) || a.contains(.holding)) ? .team : .overview
        case .operations, .properties: return (a.contains(.operations) || a.contains(.club)) ? .manage : .overview
        case .club: return a.contains(.operations) ? nil : (a.contains(.club) ? .manage : .overview)
        case .salesMarket, .projects, .marketing: return a.contains(.operations) ? .sales : .overview
        case .finances, .customers: return .stats
        default: return nil
        }
    }

    static func landing(_ section: CompanySection) -> String? {
        switch section {
        case .customers: return OverviewPage.customers.rawValue
        case .finances: return OverviewPage.stats.rawValue
        case .operations: return OverviewPage.run.rawValue
        case .marketing: return OverviewPage.sales.rawValue
        case .projects: return OverviewPage.projects.rawValue
        default: return nil
        }
    }

    static func hasProjects(_ co: Company, _ e: GameEngine) -> Bool {
        availableSections(co, e).contains(.projects)
    }

    static func availableSections(_ co: Company, _ e: GameEngine) -> [CompanySection] {
        let family = e.tradeInfo(companyID: co.id)?.family
        var own: [CompanySection] = family == "rent" ? [.properties] : family == "fin" ? [.book] : family == "project" ? [.projects] : []
        switch co.type {
        case "power", "oilgas": own = [.energy]
        case "salmon": own = [.salmon]
        case "hold": own = [.holding]
        case "club": own = [.club]
        default: break
        }
        if co.status == .setup { return own + [.setup, .overview, .finances] }
        if co.type == "hold" || co.type == "club" { return [.overview] + own + [.finances] }
        let extra: Set<CompanySection> = [.projects, .properties, .book, .energy, .salmon, .holding, .club, .chain, .salesMarket]
        var list = CompanySection.allCases.filter { $0 != .setup && !extra.contains($0) }
        if !own.isEmpty { list.insert(contentsOf: own, at: 1) }
        return list
    }
}
