import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Every page a company has. The CASE NAMES are the keys the engine and deep links use ("operations", "staff", "finances" ...: see
/// `init?(key:)`) and never change; the raw values are the titles shown on screen.
///
/// The company screen (`CompanyDetailView`) shows five of them as its fixed section bar: Overview, Team (`staff`), Manage (`operations`),
/// Sales (`salesMarket`) and Stats (`finances`). `projects` is the last block of Sales, `holding` is the Team page of a holding company
/// and `properties` is Premises inside Manage. `customers` is a part of Stats. The rest are pages pushed on top (Pricing, Marketing, Setup,
/// Plant, Fish, Club, Chain, Book): see `isLeaf`. A link to `market` opens the company's page in the Market app.
enum CompanySection: String, CaseIterable, Hashable {
    case overview = "Overview", projects = "Projects", staff = "Team", finances = "Stats", operations = "Manage"
    case salesMarket = "Sales"
    case marketing = "Marketing", customers = "Customers", market = "Market", setup = "Setup"
    /// Only for rental companies (CompanyProperties) and for insurers, banks and funds (CompanyFinanceBook).
    case properties = "Properties", book = "Book"
    // Shown only for the trades that have them (energy, salmon farm, holding company, football club)
    case energy = "Plant", salmon = "Fish", holding = "Holding", club = "Club"
    /// Chain, franchise and supply between your own companies (CompanyChain.swift)
    case chain = "Chain"
}

extension CompanySection {
    /// The engine names sections by key ("operations", "staff", "finances", ...): the case name, not the title shown on screen.
    init?(key: String) {
        guard let s = CompanySection.allCases.first(where: { "\($0)" == key }) else { return nil }
        self = s
    }

    /// A short title for a link chip ("Team ›").
    var shortTitle: String { rawValue }
}

/// The five sections of the company screen, in the fixed bar.
enum CompanyTab: String, CaseIterable, Hashable {
    case overview = "Overview", team = "Team", manage = "Manage", sales = "Sales", stats = "Stats"
    var id: String { rawValue.lowercased() }
}

/// The parts of Stats: the finance summary and its pages, how the company performs, and its customers.
enum StatsPart: String, CaseIterable, Hashable { case finances = "Finances", customers = "Customers" }

/// The parts of Sales: the sales table, and Projects for the companies that take projects (project businesses) only.
enum SalesPart: String, CaseIterable, Hashable { case sales = "Sales", projects = "Projects" }

/// One company: Overview first (cash, what needs you, who runs it) under a fixed bar of five sections: Overview | Team | Manage | Sales |
/// Stats. Switching section is in place (the bar never scrolls and there is no "More"); one Back leaves the company. Pages inside a
/// section (premises, suppliers, marketing, customers ...) are pushed screens with their own Back.
struct CompanyDetailView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    /// The part of a section to open on (the title of a `CompanyMoneyPart` or `OpsPart`), when a link asked for one.
    var part: String? = nil
    @State private var segment: CompanyTab
    @State private var statsPart: StatsPart = .finances
    @State private var salesPart: SalesPart = .sales
    @State private var moneyPart: CompanyMoneyPart = .summary
    @State private var opsPart: OpsPart = .setup
    /// The last opened Manage or Sales page, kept while it slides away.
    @State private var heldOpsPart: OpsPart = .setup
    @State private var appliedPart = false

    init(companyID: Int, initial: CompanyTab? = nil, part: String? = nil) {
        self.companyID = companyID
        self.part = part
        _segment = State(initialValue: initial ?? .overview)
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), co.status == .setup {
            // Setting up: one fixed screen with what is missing and the two apps that fix it. Stats and tabs come when it opens.
            ScrollView {
                CompanySetupScreen(engine: e, company: co)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: "Setup", subtitle: co.name) { StatusChip(company: co) }
        } else if let e = store.engine, let co = e.state.company(companyID) {
            let form: String = co.form == .limited ? "Ltd" : "Sole trader"
            let tabs: [CompanyTab] = Self.tabs(co, e)
            let pagerSelection: Binding<CompanyTab> = Binding(get: { tabs.contains(segment) ? segment : CompanyTab.overview }, set: { segment = $0 })
            VStack(spacing: 0) {
                SegmentedPill(items: tabs, title: { $0.rawValue }, selection: $segment, identifier: { "company-tab-\($0.id)" })
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
            }
            // One metadata line: trade, city and form, then where it sits in the group and who runs it.
            .appScreen(title: co.name, subtitle: ([e.tradeName(co), e.cityName(co), form] + [contextLine(co, e)].compactMap { $0 }).joined(separator: " · ").tidyText) {
                if co.status == .open { HealthChip(label: e.companyHealth(co).label) } else { StatusChip(company: co) }
            }
            .onAppear { applyPart(tabs) }
            // One destination for the pages Manage and Sales open (licences, suppliers, equipment, develop ...): both sections live in the pager at once.
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
            CompanyOverview(engine: e, company: co, section: sectionBinding(co, e), moneyPart: $moneyPart, openOps: { (p: OpsPart) in opsPart = p })
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

    /// Sales & Market: the sales table; project businesses also get a Projects part (nobody else has projects of their own).
    @ViewBuilder private func salesContent(_ co: Company, _ e: GameEngine) -> some View {
        if Self.hasProjects(co, e) {
            SegmentedPill(items: SalesPart.allCases, title: { $0.rawValue }, selection: $salesPart, identifier: { "sales-part-" + $0.rawValue.lowercased() })
            if salesPart == .projects {
                CompanyProjectsPage(engine: e, company: co)
            } else {
                CompanySales(engine: e, company: co, part: $opsPart)
            }
        } else {
            CompanySales(engine: e, company: co, part: $opsPart)
        }
    }

    /// Opens on the part a link asked for, once (the screen appears again when a page pushed from it is closed).
    private func applyPart(_ tabs: [CompanyTab]) {
        guard !appliedPart else { return }
        appliedPart = true
        guard let part else { return }
        if let m = CompanyMoneyPart(rawValue: part) { moneyPart = m }
        if let o = OpsPart(rawValue: part) { opsPart = o }
        if let sp = StatsPart(rawValue: part) { statsPart = sp }
    }

    /// The `section` the shared Overview and Setup views change to jump elsewhere: a section of this screen switches the bar in place; a
    /// page of its own (Marketing, Customers ...) is pushed.
    private func sectionBinding(_ co: Company, _ e: GameEngine) -> Binding<CompanySection> {
        Binding<CompanySection>(
            get: { .overview },
            set: { new in
                if let t = Self.tab(for: new, co, e) {
                    if t == .stats { statsPart = new == .customers ? .customers : .finances }
                    Motion.animate(Motion.quickAnimation) { segment = t }
                } else {
                    store.openCompany(companyID, section: new)
                }
            })
    }

    /// Where the company sits in the group: its chain, its holding, and who runs it day to day.
    private func contextLine(_ co: Company, _ e: GameEngine) -> String? {
        var parts: [String] = []
        if let ch = e.chainOf(companyID: co.id) { parts.append("Store of " + (ch["name"].string.isEmpty ? "your chain" : ch["name"].string)) }
        if co.holdingID != 0, let h = e.state.company(co.holdingID) { parts.append("Under " + h.name) }
        let runner: String = CompanyRunner.of(co, e).short
        if !runner.isEmpty { parts.append(runner) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Which sections and pages a company has

    /// The sections of the bar this company has. A holding has its management under Team (no staff list), a football club its own page
    /// under Manage, a company still being set up has neither Manage nor Sales yet.
    static func tabs(_ co: Company, _ e: GameEngine) -> [CompanyTab] {
        let a = availableSections(co, e)
        var out: [CompanyTab] = [.overview]
        if a.contains(.staff) || a.contains(.holding) { out.append(.team) }
        if a.contains(.operations) || a.contains(.club) { out.append(.manage) }
        if a.contains(.operations) { out.append(.sales) }
        out.append(.stats)
        return out
    }

    /// A page that is its own pushed screen, not a section of the bar.
    static func isLeaf(_ s: CompanySection) -> Bool {
        switch s {
        case .market, .setup, .book, .energy, .salmon, .club, .chain: return true
        default: return false
        }
    }

    /// The section of the bar an old section key opens, or nil for a page of its own (`isLeaf`) that is pushed instead.
    /// Old keys still resolve: staff and holding to Team; operations and properties to Manage; salesMarket and projects to Sales; finances to Stats.
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

    /// True for the companies that take projects (project businesses): the only ones with a Projects part under Sales.
    static func hasProjects(_ co: Company, _ e: GameEngine) -> Bool {
        availableSections(co, e).contains(.projects)
    }

    /// The sections this company has (by family, status and type). Shared with the Overview so links only point at real sections.
    static func availableSections(_ co: Company, _ e: GameEngine) -> [CompanySection] {
        let family = e.tradeInfo(companyID: co.id)?.family
        // Each family with a model of its own has a section of its own.
        var own: [CompanySection] = family == "rent" ? [.properties] : family == "fin" ? [.book] : family == "project" ? [.projects] : []
        switch co.type {
        case "power", "oilgas": own = [.energy]
        case "salmon": own = [.salmon]
        case "hold": own = [.holding]
        case "club": own = [.club]
        default: break
        }
        if co.status == .setup { return own + [.setup, .overview, .finances] }
        // A holding and a football club have no shop floor: no staff list, price, marketing or opening hours.
        if co.type == "hold" || co.type == "club" { return [.overview] + own + [.finances] }
        let extra: Set<CompanySection> = [.projects, .properties, .book, .energy, .salmon, .holding, .club, .chain, .salesMarket]
        var list = CompanySection.allCases.filter { $0 != .setup && !extra.contains($0) }
        if !own.isEmpty { list.insert(contentsOf: own, at: 1) }
        return list
    }
}
