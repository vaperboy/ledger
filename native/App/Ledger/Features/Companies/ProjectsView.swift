import SwiftUI
import GameCore
import Businesses
import Simulation

struct ProjectsView: View {
    enum Part: String, CaseIterable, Hashable { case projects = "Projects", portfolio = "Portfolio", bids = "Bids", finished = "Done" }

    private struct Prompt {
        var text: String
        var button: String?
        var run: (() -> Void)?
    }

    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @State private var part: Part = .projects
    @State private var developFor: DevelopRef?
    @State private var foundOpen = false

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .projects) }, set: { store.setPath($0, for: .projects) })) {
            if let e = store.engine {
                let rows: ProjectRows = e.state.companies.filter { $0.status.isLive }.compactMap { co in e.projectBoard(companyID: co.id).map { (co: co, board: $0) } }
                ScrollScreen { content(e, rows) }
                    .id(store.rootToken(.projects))
                    .scrollDismissesKeyboard(.interactively)
                    .ledgerBackground()
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .top, spacing: 0) { ReturnLine(tab: .projects) }
                    .companyRouteDestinations()
                    .centerSheet(item: $developFor, title: "", category: .medium, tone: .investment) { (d: DevelopRef) in DevelopSheet(companyID: d.id) }
                    .centerSheet(isPresented: $foundOpen, title: "", category: .medium, tone: .investment) { FoundStartupSheet() }
                    .onAppear { if store.takeVenturesRequest() { part = .portfolio } }
                    .onChange(of: store.appRequest) { _, _ in if store.takeVenturesRequest() { part = .portfolio } }
                    .onChange(of: store.rootToken(.projects)) { _, _ in part = .projects }
            }
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ rows: ProjectRows) -> some View {
        let active: [ActiveVenture] = VentureBoard.active(e, store)
        let options: [VentureOption] = VentureBoard.options(e, store, rows)
        AppHeader(title: "Ventures", subtitle: "Projects, builds and new ventures")
        SectionTabs(items: Part.allCases, title: { (p: Part) -> String in p.rawValue }, selection: $part)
            .padding(.horizontal, -Theme.Space.margin)
        switch part {
        case .projects:
            hero(e, active, prompt: prompt(e, active, options, rows))
            VenturesActiveSection(active: active, hasCompanies: e.state.companies.contains { (c: Company) -> Bool in c.status.isLive && c.type != "hold" },
                                  openDevelopment: { (id: Int) in developFor = DevelopRef(id: id) })
            VenturesStartSection(options: options, open: open, newCompany: { store.push(.newCompany) })
        case .portfolio: VenturesHome()
        case .bids: ProjectsBidsTab(engine: e, rows: rows)
        case .finished: ProjectsFinishedTab(engine: e, rows: rows)
        }
    }

    private func open(_ o: VentureOption) {
        switch o.action {
        case .route(let r): store.push(r)
        case .develop(let id): developFor = DevelopRef(id: id)
        case .found: ent.run(.ventures, "Found a startup") { foundOpen = true }
        }
    }

    private func hero(_ e: GameEngine, _ active: [ActiveVenture], prompt: Prompt?) -> some View {
        let late: Int = active.filter { (v: ActiveVenture) -> Bool in v.late }.count
        let soon: Int = active.filter { (v: ActiveVenture) -> Bool in !v.late && (v.weeksLeft ?? Int.max) <= 2 }.count
        let committed: Double = committedValue(e)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Committed to running work").textStyle(.label, tint: Theme.inkFaint)
                Text(active.isEmpty ? "Nothing yet" : store.short(committed)).textStyle(.display, tint: active.isEmpty ? Theme.inkSoft : nil)
                    .lineLimit(2).minimumScaleFactor(0.8)
                HStack(spacing: Theme.Space.m) {
                    Text(active.isEmpty ? "No project is running" : "\(active.count) running").textStyle(.caption, tint: Theme.inkSoft)
                    if soon > 0 { Chip(text: "\(soon) due soon", tint: Theme.warn) }
                    if late > 0 { Chip(text: "\(late) late", tint: Theme.loss) }
                }
            }
            .accessibilityElement(children: .combine)
            if let prompt { promptCard(prompt) }
        }
    }

    private func promptCard(_ p: Prompt) -> some View {
        Button { Haptics.tap(); p.run?() } label: {
            HStack(spacing: Theme.Space.m) {
                Capsule().fill(Theme.accent).frame(width: 3).frame(maxHeight: .infinity).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Next").textStyle(.label)
                    Text(p.text).textStyle(.headline).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let button = p.button { Text(button).textStyle(.body, tint: Theme.accent, weight: .semibold) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if p.run != nil { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Space.l)
            .glassSurface(raised: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(p.run == nil)
        .accessibilityIdentifier("ventures-next")
    }

    private func committedValue(_ e: GameEngine) -> Double {
        let home = e.homeCurrency
        let lines: [ProjectTimeline] = e.projectTimelines().filter { $0.kind == .job || $0.kind == .event || $0.kind == .development }
        return lines.reduce(0) { (acc: Double, l: ProjectTimeline) -> Double in
            guard let co = e.state.company(l.companyID) else { return acc }
            return acc + l.value * e.currency(for: co).rate / max(home.rate, 0.000001)
        }
    }

    private func prompt(_ e: GameEngine, _ active: [ActiveVenture], _ options: [VentureOption], _ rows: ProjectRows) -> Prompt? {
        if let v = active.first(where: { (a: ActiveVenture) -> Bool in a.late }) {
            return Prompt(text: v.title + " is running late.", button: "See what is holding it up", run: { store.push(.companyAt(v.companyID, .projects)) })
        }
        let closing: Int = rows.reduce(0) { (n: Int, r: (co: Company, board: ProjectBoard)) -> Int in
            n + r.board.tenders.filter { (t: ProjectBoard.TenderRow) -> Bool in t.qualifies && t.myBid == nil && t.weeksToBid <= 1 }.count
        }
        if closing > 0 {
            return Prompt(text: closing == 1 ? "A tender closes within a week." : "\(closing) tenders close within a week.", button: "See the tenders", run: { part = .bids })
        }
        if active.isEmpty, options.contains(where: { (o: VentureOption) -> Bool in o.rank == 0 }) {
            return Prompt(text: "Nothing is running. Pick something to start below.", button: nil, run: nil)
        }
        return nil
    }
}
