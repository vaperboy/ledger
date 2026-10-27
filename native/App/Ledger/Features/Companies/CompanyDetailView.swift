import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum CompanySection: String, CaseIterable, Hashable {
    case overview = "Overview", projects = "Projects", staff = "Team", finances = "Finances", operations = "Operations", marketing = "Marketing", customers = "Customers", market = "Market", setup = "Setup"
    /// Only for rental companies (CompanyProperties) and for insurers, banks and funds (CompanyFinanceBook).
    case properties = "Properties", book = "Book"
    // Shown only for the trades that have them (energy, salmon farm, holding company, football club)
    case energy = "Plant", salmon = "Fish", holding = "Holding", club = "Club"
    /// Chain, franchise and supply between your own companies (CompanyChain.swift)
    case chain = "Chain"
}

extension CompanySection {
    /// The engine names sections by key ("operations", "staff", "finances", ...): the case name, not the title shown on the tab.
    init?(key: String) {
        guard let s = CompanySection.allCases.first(where: { "\($0)" == key }) else { return nil }
        self = s
    }
}

/// One company. Overview answers "how is it doing, why, and what to change"; the other sections are where the changes are made.
struct CompanyDetailView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    /// The section to open on (set by the route, never by global state, so it cannot carry over to another company).
    var initialSection: CompanySection? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var section: CompanySection = .overview
    /// The part of Finances on show; other sections can send the player straight to one (the setup checklist, the overview).
    @State private var moneyPart: CompanyMoneyPart = .summary

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if section == .overview, let context = contextLine(co, e) {
                        Text(context).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    switch section {
                    case .overview: CompanyOverview(engine: e, company: co, section: $section, moneyPart: $moneyPart)
                    case .projects: CompanyProjects(engine: e, company: co)
                    case .staff: CompanyTeam(engine: e, company: co)
                    case .finances: CompanyMoney(engine: e, company: co, part: $moneyPart)
                    case .operations: CompanyOperations(engine: e, company: co)
                    case .marketing: CompanyMarketing(engine: e, company: co)
                    case .customers: CompanyCustomers(engine: e, company: co)
                    case .market: CompanyMarket(engine: e, company: co)
                    case .setup: CompanySetupSection(engine: e, company: co, section: $section, moneyPart: $moneyPart)
                    case .properties: CompanyProperties(engine: e, company: co)
                    case .book: CompanyFinanceBook(engine: e, company: co)
                    case .energy: CompanyEnergy(engine: e, company: co)
                    case .salmon: CompanySalmon(engine: e, company: co)
                    case .holding: CompanyHolding(engine: e, company: co)
                    case .club: CompanyClub(engine: e, company: co)
                    case .chain: CompanyChain(engine: e, company: co)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .ledgerBackground()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { frameHeader(co, e) }
            .onAppear {
                if co.status == .setup { section = .setup }
                if let want = initialSection {
                    let available = Self.availableSections(co, e)
                    // A holding has no staff list: its management lives in its own section.
                    let target = (want == .staff && !available.contains(.staff) && available.contains(.holding)) ? .holding : want
                    if available.contains(target) { section = target }
                }
            }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    /// The pinned frame: round back button, serif company name, grey subtitle with the status dot, and the fixed underline tab row
    /// (Overview, Team, Finances, Operations and a More menu for everything else).
    private func frameHeader(_ co: Company, _ e: GameEngine) -> some View {
        let form: String = co.form == .limited ? "Ltd" : "Sole trader"
        let subtitle: String = "\(e.tradeName(co)) · \(e.cityName(co)) · \(form)"
        let live: Bool = co.status == .open
        let statusText: String = live ? e.companyHealth(co).label : statusWord(co)
        let dot: Color = live ? HealthChip.tint(statusText) : (co.status == .setup ? Theme.caution : (co.status == .bust ? Theme.loss : Theme.ivoryMuted))
        let primary: [CompanySection]? = co.status == .setup ? nil : [.overview, .staff, .finances, .operations]
        return VStack(spacing: 0) {
            ReturnLine(tab: store.tab)
            HStack(spacing: 12) {
                RoundBackButton { dismiss() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(co.name).font(.serifTitle(26)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        Text(subtitle.tidyText).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                        Circle().fill(dot).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(statusText).font(.system(size: 12.5)).foregroundStyle(dot).lineLimit(1).fixedSize()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 8)
            SectionTabs(items: Self.availableSections(co, e), primary: primary, title: { $0.rawValue }, selection: $section)
        }
        .background(Theme.page)
    }

    private func statusWord(_ co: Company) -> String {
        switch co.status {
        case .setup: return "Setting up"
        case .closed: return "Closed"
        case .sold: return "Sold"
        case .bust: return "Bankrupt"
        default: return co.status.rawValue.capitalized
        }
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
        let extra: Set<CompanySection> = [.projects, .properties, .book, .energy, .salmon, .holding, .club, .chain]
        var list = CompanySection.allCases.filter { $0 != .setup && !extra.contains($0) }
        if !own.isEmpty { list.insert(contentsOf: own, at: 1) }
        if CompanyChain.isRelevant(co, e) { list.append(.chain) }
        return list
    }
}

