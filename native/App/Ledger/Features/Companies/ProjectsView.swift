import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Ventures tab: header with the running figures, then `SectionTabs` Running (a `SegmentedPill` for In progress, Timeline, Bids and
/// offers), Ideas and startups, Done. All figures come from `projectBoard` and `projectTimelines`; actions go through the engine
/// (see `ProjectsTabs.swift`). Every company's own Projects section stays reachable from the cards, tender details and the company list.
struct ProjectsView: View {
    /// The three segments of the merged Ventures screen. Running also holds the Timeline and the Bids and offers lists (`RunPart`).
    enum Part: String, CaseIterable, Hashable { case running = "Running", ideas = "Ideas and startups", finished = "Done" }
    enum RunPart: String, CaseIterable, Hashable { case now = "In progress", timeline = "Timeline", bids = "Bids and offers" }
    @EnvironmentObject var store: GameStore
    @State private var part: Part = .running
    @State private var runPart: RunPart = .now

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .projects) }, set: { store.setPath($0, for: .projects) })) {
            if let e = store.engine {
                let rows = e.state.companies.filter { $0.status.isLive }.compactMap { co in e.projectBoard(companyID: co.id).map { (co: co, board: $0) } }
                let lines = e.projectTimelines()
                let running = lines.filter { $0.kind == .job || $0.kind == .event || $0.kind == .development }
                page(e, rows, lines, running)
                .id(store.rootToken(.projects))
                .scrollDismissesKeyboard(.interactively)
                .ledgerBackground()
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { ReturnLine(tab: .projects) }
                .companyRouteDestinations()
                // Choosing Projects again: back to Running.
                .onAppear { if store.takeVenturesRequest() { part = .ideas } }
                .onChange(of: store.appRequest) { _, _ in if store.takeVenturesRequest() { part = .ideas } }
                .onChange(of: store.rootToken(.projects)) { _, _ in part = .running; runPart = .now }
            }
        }
    }

    /// The Running tab is the summary and is fixed when it fits (compacted first); the other tabs are lists and scroll.
    @ViewBuilder private func page(_ e: GameEngine, _ rows: ProjectRows, _ lines: [ProjectTimeline], _ running: [ProjectTimeline]) -> some View {
        if part == .running && runPart == .now {
            FixedScreen(overflowScrolls: true) { pageContent(e, rows, lines, running) }
        } else {
            ScrollScreen { pageContent(e, rows, lines, running) }
        }
    }

    @ViewBuilder private func pageContent(_ e: GameEngine, _ rows: ProjectRows, _ lines: [ProjectTimeline], _ running: [ProjectTimeline]) -> some View {
        header(e, running)
        SectionTabs(items: Part.allCases, title: { $0.rawValue }, selection: $part)
            // The page already has its margin: the row runs to the page edges instead of indenting twice.
            .padding(.horizontal, -Theme.Space.margin)
        switch part {
        case .running:
            SegmentedPill(items: RunPart.allCases, title: { $0.rawValue }, selection: $runPart)
            runContent(e, rows, lines, running)
        case .ideas: VenturesFeedApp(embedded: true)
        case .finished: ProjectsFinishedTab(engine: e, rows: rows)
        }
    }

    @ViewBuilder private func runContent(_ e: GameEngine, _ rows: ProjectRows, _ lines: [ProjectTimeline], _ running: [ProjectTimeline]) -> some View {
        switch runPart {
        case .now: ProjectsRunningTab(engine: e, rows: rows, running: running)
        case .timeline: ProjectsTimelineTab(engine: e, lines: lines)
        case .bids: ProjectsBidsTab(engine: e, rows: rows, openVentures: { part = .ideas })
        }
    }

    private func header(_ e: GameEngine, _ running: [ProjectTimeline]) -> some View {
        let home = e.homeCurrency
        let committed: Double = running.reduce(0) { acc, l in
            guard let co = e.state.company(l.companyID) else { return acc }
            return acc + l.value * e.currency(for: co).rate / max(home.rate, 0.000001)
        }
        // Portfolio first: what is running and the value committed to it, then the one action.
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            AppHeader(title: "Ventures") {
                Button("New project") { Haptics.tap(); part = .running; runPart = .bids }
                    .buttonStyle(SecondaryButtonStyle(size: .compact))
                    .accessibilityLabel("New project")
            }
            FigureRow(items: [
                KeyFigures.Item(label: "Running", value: running.isEmpty ? "None" : "\(running.count)"),
                KeyFigures.Item(label: "Committed", value: running.isEmpty ? "None" : store.short(committed)),
            ], columns: 2, combineCells: true)
        }
    }
}

/// A link to another screen: the house row with a chevron, no box.
struct ProjectCardRow: View {
    var title: String
    var sub: String = ""
    var body: some View {
        LedgerRow(title: title, subtitle: sub, chevron: true, lineLimit: 3)
    }
}
