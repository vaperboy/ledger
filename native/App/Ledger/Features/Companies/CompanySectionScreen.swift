import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// One screen of a company, pushed from the Company hub (or by a link): Overview, People, Operations, Sales & Market, Stats & Information,
/// Projects, and the pages that belong under them (Marketing, Customers, Market, a trade's own page, Setup).
///
/// Rule for every company screen: moving between sections is a NAVIGATION STEP. There is no in-place section switch: a section is
/// pushed on the stack, so the round Back button always reverses exactly one step (back to the hub, or to the screen a link came from).
/// A link from inside one section to another (Overview to People, Operations to People) pushes that section on top; a link to a
/// section that is already on the stack goes back to it (see `GameStore.collapse`).
struct CompanySectionScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var section: CompanySection
    /// The part of the screen to open on (the title of a `CompanyMoneyPart` or `OpsPart`), when a link asked for one.
    var part: String? = nil
    @State private var moneyPart: CompanyMoneyPart = .summary
    @State private var opsPart: OpsPart = .setup
    @State private var appliedPart = false
    /// The Finances part a section asked for just before it asked to be switched to Finances (the Overview's "Ownership" link).
    @State private var outgoingPart: String?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let sec = CompanyDetailView.resolve(section, co, e)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    content(sec, co, e)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .appScreen(title: sec.rawValue, subtitle: co.name)
            .overlay(alignment: .topTrailing) { navigationProbes(co.id, sec) }
            .onAppear { applyPart() }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ sec: CompanySection, _ co: Company, _ e: GameEngine) -> some View {
        switch sec {
        case .overview:
            if co.status == .setup {
                CompanySetupSection(engine: e, company: co, section: sectionBinding(.overview), moneyPart: moneyBinding)
            }
            CompanyOverview(engine: e, company: co, section: sectionBinding(.overview), moneyPart: moneyBinding)
        case .setup:
            CompanySetupSection(engine: e, company: co, section: sectionBinding(.setup), moneyPart: moneyBinding)
        case .staff: CompanyTeam(engine: e, company: co)
        case .holding: CompanyHolding(engine: e, company: co)
        case .operations:
            CompanyOperations(engine: e, company: co, part: $opsPart)
            morePages([.energy, .salmon, .club, .chain], co, e, heading: "More for this business")
        case .salesMarket: CompanyOperations(engine: e, company: co, part: $opsPart, mode: .sales)
        case .marketing: CompanyMarketing(engine: e, company: co)
        case .customers: CompanyCustomers(engine: e, company: co)
        case .market: CompanyMarket(engine: e, company: co)
        case .finances:
            CompanyMoney(engine: e, company: co, part: $moneyPart)
            morePages([.book], co, e, heading: "More for this business")
        case .projects: CompanyProjectsPage(engine: e, company: co)
        case .properties: CompanyProperties(engine: e, company: co)
        case .book: CompanyFinanceBook(engine: e, company: co)
        case .energy: CompanyEnergy(engine: e, company: co)
        case .salmon: CompanySalmon(engine: e, company: co)
        case .club: CompanyClub(engine: e, company: co)
        case .chain: CompanyChain(engine: e, company: co)
        }
    }

    /// Test-only: two near-invisible controls in a game started with `-showcase` that make this screen link to its own company, exactly as
    /// the app's real links do (`GameStore.openCompany`), so the UI tests can check that such a link never stacks a second copy.
    /// Compiled into debug builds only.
    @ViewBuilder private func navigationProbes(_ id: Int, _ sec: CompanySection) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showcase") {
            HStack(spacing: 0) {
                Button("") { store.openCompany(id) }.frame(width: 24, height: 24).accessibilityIdentifier("probe-link-company")
                Button("") { store.openCompany(id, section: sec) }.frame(width: 24, height: 24).accessibilityIdentifier("probe-link-same-screen")
            }
            .opacity(0.02)
        }
        #endif
    }

    /// Opens on the part a link asked for, once (the screen appears again when a page pushed from it is closed).
    private func applyPart() {
        guard !appliedPart else { return }
        appliedPart = true
        guard let part else { return }
        if let m = CompanyMoneyPart(rawValue: part) { moneyPart = m }
        if let o = OpsPart(rawValue: part) { opsPart = o }
    }

    /// The `section` the shared Overview and Setup views change to jump elsewhere: here it is a push of that section, never an in-place switch.
    private func sectionBinding(_ current: CompanySection) -> Binding<CompanySection> {
        Binding<CompanySection>(
            get: { current },
            set: { new in
                guard new != current else { return }
                let asked: String? = new == .finances ? outgoingPart : nil
                outgoingPart = nil
                store.openCompany(companyID, section: new, part: asked)
            })
    }

    private var moneyBinding: Binding<CompanyMoneyPart> {
        Binding<CompanyMoneyPart>(get: { moneyPart }, set: { moneyPart = $0; outgoingPart = $0.rawValue })
    }

    /// Pages of the trade that have no row of their own in the hub (Plant, Fish, Club, Chain, Book): rows on the screen they belong to.
    @ViewBuilder private func morePages(_ pages: [CompanySection], _ co: Company, _ e: GameEngine, heading: String) -> some View {
        let available: [CompanySection] = CompanyDetailView.availableSections(co, e)
        let list: [CompanySection] = pages.filter { available.contains($0) }
        if !list.isEmpty {
            OverviewSettingsCard(heading: heading) {
                ForEach(list, id: \.self) { (s: CompanySection) in
                    SettingsTableRow(title: s.rawValue, note: Self.note(s), value: "", glyph: Glyph.opsBox) { store.openCompany(co.id, section: s) }
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

/// Projects of one company, for every company. A project business shows its running jobs and developments with their stages and its order
/// book (jobs, tenders, developments); any other business has no projects of its own, and says so.
struct CompanyProjectsPage: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let lines: [ProjectTimeline] = engine.projectTimelines().filter { $0.companyID == company.id }
        let running: [ProjectTimeline] = lines.filter { $0.kind == .job || $0.kind == .event || $0.kind == .development }
        if engine.projectBoard(companyID: company.id) == nil {
            Card(padding: 14, radius: Theme.Radius.card) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No projects").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text("\(company.name) does not run projects. Jobs, tenders and developments belong to project businesses such as builders, developers and event firms. Your own investments and startups are under Projects in the tab bar.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Running").capsLabel()
                if running.isEmpty {
                    Card(padding: 12, radius: Theme.Radius.row) {
                        Text("Nothing running at the moment.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                ForEach(running) { (l: ProjectTimeline) in row(l) }
            }
            CompanyProjects(engine: engine, company: company)
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
