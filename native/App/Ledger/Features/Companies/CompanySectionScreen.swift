import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

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
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .appScreen(title: section.rawValue, subtitle: co.name)
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ co: Company, _ e: GameEngine) -> some View {
        switch section {
        case .setup:
            CompanySetupScreen(engine: e, company: co)
        case .book: CompanyFinanceBook(engine: e, company: co)
        case .energy: CompanyEnergy(engine: e, company: co)
        case .salmon: CompanySalmon(engine: e, company: co)
        case .club: CompanyClub(engine: e, company: co)
        case .chain: EntityExpansionView(companyID: co.id)
        default: EmptyView()
        }
    }
}

struct CompanyMorePages: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var pages: [CompanySection]
    var ruled = false
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let available: [CompanySection] = CompanyDetailView.availableSections(company, engine)
        let list: [CompanySection] = pages.filter { available.contains($0) }
        if !list.isEmpty {
            if ruled {
                rows(list)
            } else {
                PageGroup("More for this business") { rows(list) }
            }
        }
    }

    @ViewBuilder private func rows(_ list: [CompanySection]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element) { (n: Int, s: CompanySection) in
            if ruled || n > 0 { RowRule() }
            LedgerRow(leading: .glyph(Glyph.opsBox), leadingTint: P.inkSoft, title: s.rawValue,
                      identifier: "company-page-\(s)") { store.openCompany(company.id, section: s) }
        }
    }

}

struct CompanyProjectsPage: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let lines: [ProjectTimeline] = engine.projectTimelines().filter { $0.companyID == company.id }
        let running: [ProjectTimeline] = lines.filter { $0.kind == .job || $0.kind == .event || $0.kind == .development }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if engine.projectBoard(companyID: company.id) != nil {
                if running.isEmpty {
                    Card(padding: 12, radius: Theme.Radius.row) {
                        Text("Nothing running at the moment.").textStyle(.caption, tint: Theme.inkFaint)
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
                Text(l.title.tidyText).textStyle(.headline).lineLimit(2)
                if !sub.isEmpty { Text(sub.tidyText).textStyle(.caption).lineLimit(2) }
                if let p = l.progress { RateBar(label: "Progress", fraction: p) }
            }
        }
    }
}
