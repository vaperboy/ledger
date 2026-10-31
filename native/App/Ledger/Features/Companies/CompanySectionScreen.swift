import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A page of a company that is its own screen, pushed on top of the company screen: Marketing, Customers, Market, Setup, and a trade's
/// own page (Plant, Fish, Club, Chain, Book). The five sections of the company itself (Overview, Team, Manage, Sales, Stats) are not
/// here: they are the fixed bar of `CompanyDetailView`.
struct CompanySectionScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var section: CompanySection
    @State private var moneyPart: CompanyMoneyPart = .summary

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    content(co, e)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .appScreen(title: section.rawValue, subtitle: co.name)
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ co: Company, _ e: GameEngine) -> some View {
        switch section {
        case .setup:
            CompanySetupSection(engine: e, company: co,
                                section: Binding<CompanySection>(get: { .setup }, set: { store.openCompany(companyID, section: $0) }),
                                moneyPart: $moneyPart)
        case .marketing: CompanyMarketing(engine: e, company: co)
        case .customers: CompanyCustomers(engine: e, company: co)
        case .market: CompanyMarket(engine: e, company: co)
        case .book: CompanyFinanceBook(engine: e, company: co)
        case .energy: CompanyEnergy(engine: e, company: co)
        case .salmon: CompanySalmon(engine: e, company: co)
        case .club: CompanyClub(engine: e, company: co)
        case .chain: CompanyChain(engine: e, company: co)
        default: EmptyView()
        }
    }
}

/// Pages of the trade that have no section of their own (Plant, Fish, Club, Chain, Book): rows on the section they belong to.
struct CompanyMorePages: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var pages: [CompanySection]

    var body: some View {
        let available: [CompanySection] = CompanyDetailView.availableSections(company, engine)
        let list: [CompanySection] = pages.filter { available.contains($0) }
        if !list.isEmpty {
            OverviewSettingsCard(heading: "More for this business") {
                ForEach(list, id: \.self) { (s: CompanySection) in
                    SettingsTableRow(title: s.rawValue, note: Self.note(s), value: "", glyph: Glyph.opsBox) { store.openCompany(company.id, section: s) }
                }
            }
        }
    }

    private static func note(_ s: CompanySection) -> String {
        switch s {
        case .energy: return "Plant, output and sales of power"
        case .salmon: return "Pens, feed and harvest"
        case .club: return "Squad, matches and club finances"
        case .chain: return "Stores, franchise and supply between your companies"
        case .book: return "Policies, loans and funds"
        default: return ""
        }
    }
}

/// Projects of one company, for every company: the last block of Sales. A project business shows its running jobs and developments with
/// their stages and its order book (jobs, tenders, developments); any other business has no projects of its own, and says so.
struct CompanyProjectsPage: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let lines: [ProjectTimeline] = engine.projectTimelines().filter { $0.companyID == company.id }
        let running: [ProjectTimeline] = lines.filter { $0.kind == .job || $0.kind == .event || $0.kind == .development }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Projects").capsLabel()
            if engine.projectBoard(companyID: company.id) == nil {
                Card(padding: 14, radius: Theme.Radius.card) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No projects").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("\(company.name) does not run projects. Jobs, tenders and developments belong to project businesses such as builders, developers and event firms. Your own investments and startups are under Projects in the tab bar.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                if running.isEmpty {
                    Card(padding: 12, radius: Theme.Radius.row) {
                        Text("Nothing running at the moment.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                ForEach(running) { (l: ProjectTimeline) in row(l) }
                CompanyProjects(engine: engine, company: company)
            }
        }
    }

    private func row(_ l: ProjectTimeline) -> some View {
        let stage: String = l.stages.first(where: { $0.state == .current })?.name ?? ""
        let due: String = l.dueWeek.map { "due " + GameCalendar.dateString(week: $0, dayOffset: 0) } ?? ""
        let sub: String = [l.subtitle, stage, due].filter { !$0.isEmpty }.joined(separator: " · ")
        return Card(padding: 12, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 6) {
                Text(l.title.tidyText).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                if !sub.isEmpty { Text(sub.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(2) }
                if let p = l.progress { RateBar(label: "Progress", fraction: p) }
            }
        }
    }
}
