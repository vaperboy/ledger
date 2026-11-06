import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Projects tab (new look): header, then underline tabs. Running (cards), Timeline (weeks chart), Bids and offers (open tenders and
/// things to start), Finished, Ventures. All figures come from `projectBoard` and `projectTimelines`; actions go through the engine
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
        ProjectUnderlineTabs(items: Part.allCases, title: { $0.rawValue }, selection: $part, count: { $0 == .running ? running.count : 0 })
        switch part {
        case .running:
            ProjectUnderlineTabs(items: RunPart.allCases, title: { $0.rawValue }, selection: $runPart)
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
        let sub = running.isEmpty ? "Nothing running" : "\(running.count) running · \(store.short(committed)) committed"
        return HStack(spacing: Theme.Space.m) {
            IconCircle(glyph: Glyph.projects, size: 44)
            AppHeader(title: "Ventures", subtitle: sub) {
                SmallOutlineButton(title: "New project") { part = .running; runPart = .bids }
            }
        }
    }
}

/// Text tabs with a champagne underline on the chosen one and a hairline under the row (ProjectsA).
struct ProjectUnderlineTabs<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var count: (T) -> Int = { _ in 0 }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                let n = count(item)
                Button { if !on { Haptics.choose(); selection = item } } label: {
                    Text(title(item) + (n > 0 ? " \(n)" : ""))
                        .font(.system(size: 13.5)).lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.Space.s).padding(.bottom, 1)
                        .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// A simple tappable card line with a chevron, for links to other screens.
struct ProjectCardRow: View {
    var title: String
    var sub: String = ""
    var body: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.tidyText).textStyle(.body, tint: Theme.ink, weight: .medium)
                if !sub.isEmpty { Text(sub.tidyText).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
