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
/// and `properties` is Premises inside Manage. The rest are pages pushed on top (Marketing, Customers, Market, Setup, Plant, Fish, Club,
/// Chain, Book): see `isLeaf`.
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

/// The parts of Stats: the finance summary and its pages, then how the company performs and what stands out.
enum StatsPart: String, CaseIterable, Hashable { case finances = "Finances", performance = "Performance", insights = "Insights" }

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
    @State private var moneyPart: CompanyMoneyPart = .summary
    @State private var opsPart: OpsPart = .setup
    @State private var appliedPart = false

    init(companyID: Int, initial: CompanyTab? = nil, part: String? = nil) {
        self.companyID = companyID
        self.part = part
        _segment = State(initialValue: initial ?? .overview)
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let form: String = co.form == .limited ? "Ltd" : "Sole trader"
            let tabs: [CompanyTab] = Self.tabs(co, e)
            let current: CompanyTab = tabs.contains(segment) ? segment : .overview
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if let context = contextLine(co, e) {
                        Text(context).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                    }
                    SegmentedPill(items: tabs, title: { $0.rawValue }, selection: $segment, identifier: { "company-tab-\($0.id)" })
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, 2).padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        content(current, co, e)
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.xs).padding(.bottom, 40)
                    .frame(maxWidth: 1100).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .appScreen(title: co.name, subtitle: "\(e.tradeName(co)) · \(e.cityName(co)) · \(form)".tidyText) {
                if co.status == .open { HealthChip(label: e.companyHealth(co).label) } else { StatusChip(company: co) }
            }
            .onAppear { applyPart(tabs) }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ tab: CompanyTab, _ co: Company, _ e: GameEngine) -> some View {
        let a: [CompanySection] = Self.availableSections(co, e)
        switch tab {
        case .overview:
            if co.status == .setup {
                CompanySetupSection(engine: e, company: co, section: sectionBinding(co, e), moneyPart: $moneyPart)
            }
            CompanyOverview(engine: e, company: co, section: sectionBinding(co, e), moneyPart: $moneyPart)
        case .team:
            if a.contains(.staff) { CompanyTeam(engine: e, company: co) } else { CompanyHolding(engine: e, company: co) }
        case .manage:
            if a.contains(.operations) {
                CompanyOperations(engine: e, company: co, part: $opsPart)
                CompanyMorePages(engine: e, company: co, pages: [.energy, .salmon, .club, .chain])
            } else {
                CompanyClub(engine: e, company: co)
            }
        case .sales:
            CompanyOperations(engine: e, company: co, part: $opsPart, mode: .sales)
            CompanyProjectsPage(engine: e, company: co)
        case .stats:
            SegmentedPill(items: StatsPart.allCases, title: { $0.rawValue }, selection: $statsPart, identifier: { "stats-part-\($0.rawValue.lowercased())" })
            switch statsPart {
            case .finances:
                CompanyMoney(engine: e, company: co, part: $moneyPart)
                CompanyMorePages(engine: e, company: co, pages: [.book])
            case .performance:
                CompanyOverview(engine: e, company: co, section: sectionBinding(co, e), moneyPart: $moneyPart, mode: .performance)
            case .insights:
                CompanyOverview(engine: e, company: co, section: sectionBinding(co, e), moneyPart: $moneyPart, mode: .insights)
            }
        }
    }

    /// Opens on the part a link asked for, once (the screen appears again when a page pushed from it is closed).
    private func applyPart(_ tabs: [CompanyTab]) {
        guard !appliedPart else { return }
        appliedPart = true
        guard let part else { return }
        if let m = CompanyMoneyPart(rawValue: part) { moneyPart = m }
        if let o = OpsPart(rawValue: part) { opsPart = o }
    }

    /// The `section` the shared Overview and Setup views change to jump elsewhere: a section of this screen switches the bar in place; a
    /// page of its own (Marketing, Customers ...) is pushed.
    private func sectionBinding(_ co: Company, _ e: GameEngine) -> Binding<CompanySection> {
        Binding<CompanySection>(
            get: { .overview },
            set: { new in
                if let t = Self.tab(for: new, co, e) {
                    if t == .stats { statsPart = .finances }
                    withAnimation(.snappy(duration: 0.2)) { segment = t }
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
        if let boss = e.decisionChain(companyID: co.id).first {
            parts.append("Run by \(boss.name), \(GameEngine.bossTitle(boss.kind, trade: e.tradeInfo(companyID: co.id)).lowercased())")
        } else if co.status == .open && co.type != "hold" {
            parts.append(co.ownerHours > 0 ? "Run by you" : "No one runs it")
        }
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
        case .marketing, .customers, .market, .setup, .book, .energy, .salmon, .club, .chain: return true
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
        case .salesMarket, .projects: return a.contains(.operations) ? .sales : .overview
        case .finances: return .stats
        default: return nil
        }
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
        if CompanyChain.isRelevant(co, e) { list.append(.chain) }
        return list
    }
}
