import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Every screen a company has. The raw values are the titles shown on screen; the CASE NAMES are the keys the engine and deep links use
/// ("operations", "staff", "finances" ...: see `init?(key:)`) and never change.
///
/// The Company hub (`CompanyDetailView`) lists six of them, in the order of the Company Management mockup: Overview, People (`staff`),
/// Operations, Sales & Market, Stats & Information (`finances`) and Projects. Everything else is a screen reached from one of those:
/// Marketing, Customers and Market from Sales & Market; Plant, Fish, Club, Chain and Properties from Operations; Book from Stats &
/// Information; Holding from People; Setup from the Overview while the company is being set up.
enum CompanySection: String, CaseIterable, Hashable {
    case overview = "Overview", projects = "Projects", staff = "People", finances = "Stats & Information", operations = "Operations"
    case salesMarket = "Sales & Market"
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

    /// The six rows of the Company hub, in the order of the mockup.
    static let hubRows: [CompanySection] = [.overview, .staff, .operations, .salesMarket, .finances, .projects]

    /// The line under a hub row's title (the mockup's wording).
    var hubNote: String {
        switch self {
        case .overview: return "Key figures and alerts"
        case .staff: return "Team and management"
        case .operations: return "Premises, equipment, inventory"
        case .salesMarket: return "Customers, pricing, marketing"
        case .finances: return "Performance, finances, documents"
        case .projects: return "Ongoing projects and milestones"
        default: return ""
        }
    }

    var hubGlyph: String {
        switch self {
        case .overview: return Glyph.stats
        case .staff: return Glyph.team
        case .operations: return Glyph.opsWrench
        case .salesMarket: return Glyph.market
        case .finances: return Glyph.reports
        case .projects: return Glyph.projects
        default: return Glyph.chevron
        }
    }

    /// The accessibility id of the hub row (`company-hub-<id>`).
    var hubID: String {
        switch self {
        case .staff: return "people"
        case .finances: return "stats"
        case .salesMarket: return "sales"
        default: return "\(self)"
        }
    }

    /// A short title for a link chip ("People ›") where the full title would not fit.
    var shortTitle: String { self == .finances ? "Stats" : rawValue }
}

/// The Company hub: the company at a glance (cash first, then profit and margin) and the six sections of the Company Management
/// mockup, each a screen of its own that is pushed on the stack, so Back always returns to the hub (or to wherever a link came from).
struct CompanyDetailView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let form: String = co.form == .limited ? "Ltd" : "Sole trader"
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let context = contextLine(co, e) {
                        Text(context).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    header(co, e)
                    VStack(spacing: 8) {
                        ForEach(Self.rows(co, e), id: \.row) { r in
                            Button { Haptics.tap(); store.openCompany(co.id, section: r.target) } label: {
                                CardRow(glyph: r.row.hubGlyph, title: r.row.rawValue, subtitle: r.row.hubNote, value: value(r.row, co, e))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("company-hub-\(r.row.hubID)")
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: co.name, subtitle: "\(e.tradeName(co)) · \(e.cityName(co)) · \(form)".tidyText)
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    /// Cash big, then profit and margin over twelve months. A company still being set up shows its cash and what is left to do.
    private func header(_ co: Company, _ e: GameEngine) -> some View {
        let h = e.companyHealth(co)
        let live: Bool = co.status == .open
        let margin: String = h.marginTTM.map { String(format: "%.1f%%", $0 * 100) } ?? "–"
        let cells: [StatStrip.Cell] = [
            .init(label: "Profit · 12 months", value: (h.profitTTM < 0 ? "−" : "") + store.short(abs(h.profitTTM), in: co), tint: h.profitTTM < 0 ? Theme.loss : Theme.ivory),
            .init(label: "Margin", value: margin),
        ]
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Cash").capsLabel()
                    Spacer(minLength: 8)
                    if live { HealthChip(label: h.label) } else { StatusChip(company: co) }
                }
                Text(store.money(co.cash, in: co)).font(.hero(34)).foregroundStyle(co.cash < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                if live { StatStrip(cells: cells) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A figure at the end of a row where there is an honest one: how many people work here, how many projects are running.
    private func value(_ row: CompanySection, _ co: Company, _ e: GameEngine) -> String {
        guard co.status.isLive else { return "" }
        switch row {
        case .staff: return co.staff.isEmpty ? "" : co.staff.count.peopleText
        case .projects:
            let n: Int = e.projectTimelines().filter { $0.companyID == co.id && ($0.kind == .job || $0.kind == .event || $0.kind == .development) }.count
            return n == 0 ? "" : "\(n) running"
        default: return ""
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

    // MARK: Which rows and screens a company has

    /// The hub rows this company has, each with the screen it opens. A holding has its management under People (no staff list), a
    /// football club has its own page under Operations, a company still being set up has no operations yet. Projects is for every company.
    static func rows(_ co: Company, _ e: GameEngine) -> [(row: CompanySection, target: CompanySection)] {
        let a = availableSections(co, e)
        var out: [(row: CompanySection, target: CompanySection)] = [(.overview, .overview)]
        if a.contains(.staff) { out.append((.staff, .staff)) } else if a.contains(.holding) { out.append((.staff, .holding)) }
        if a.contains(.operations) { out.append((.operations, .operations)) } else if a.contains(.club) { out.append((.operations, .club)) }
        if a.contains(.operations) { out.append((.salesMarket, .salesMarket)) }
        out.append((.finances, .finances))
        out.append((.projects, .projects))
        return out
    }

    /// The screen a link actually opens: one the company has, else its Overview. A holding has no staff list (its management is its own page).
    static func resolve(_ want: CompanySection, _ co: Company, _ e: GameEngine) -> CompanySection {
        let a = availableSections(co, e)
        switch want {
        case .overview, .projects: return want
        case .salesMarket: return a.contains(.operations) ? want : .overview
        case .staff where !a.contains(.staff) && a.contains(.holding): return .holding
        default: return a.contains(want) ? want : .overview
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
