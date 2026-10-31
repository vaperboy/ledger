import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Projects tab (new look): header, then underline tabs. Running (cards), Timeline (weeks chart), Bids and offers (open tenders and
/// things to start), Finished, Ventures. All figures come from `projectBoard` and `projectTimelines`; actions go through the engine
/// (see `ProjectsTabs.swift`). Every company's own Projects section stays reachable from the cards, tender details and the company list.
struct ProjectsView: View {
    enum Part: String, CaseIterable, Hashable { case running = "Running", timeline = "Timeline", bids = "Bids and offers", finished = "Finished", ventures = "Ventures" }
    @EnvironmentObject var store: GameStore
    @State private var part: Part = .running

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .projects) }, set: { store.setPath($0, for: .projects) })) {
            if let e = store.engine {
                let rows = e.state.companies.filter { $0.status.isLive }.compactMap { co in e.projectBoard(companyID: co.id).map { (co: co, board: $0) } }
                let lines = e.projectTimelines()
                let running = lines.filter { $0.kind == .job || $0.kind == .event || $0.kind == .development }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(e, running)
                        ProjectUnderlineTabs(items: Part.allCases, title: { $0.rawValue }, selection: $part, count: { $0 == .running ? running.count : 0 })
                        switch part {
                        case .running: ProjectsRunningTab(engine: e, rows: rows, running: running)
                        case .timeline: ProjectsTimelineTab(engine: e, lines: lines)
                        case .bids: ProjectsBidsTab(engine: e, rows: rows, openVentures: { part = .ventures })
                        case .finished: ProjectsFinishedTab(engine: e, rows: rows)
                        case .ventures:
                            VenturesContent()
                            Button { Haptics.tap(); store.openApp(.ventures) } label: {
                                ProjectCardRow(title: "Open Ventures in Phone", sub: "The same startups, funds and stakes, as an app.")
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 40)
                    .frame(maxWidth: 900).frame(maxWidth: .infinity)
                }
                .id(store.rootToken(.projects))
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .ledgerBackground()
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { ReturnLine(tab: .projects) }
                .companyRouteDestinations()
                // Choosing Projects again: back to Running.
                .onChange(of: store.rootToken(.projects)) { _, _ in part = .running }
            }
        }
    }

    private func header(_ e: GameEngine, _ running: [ProjectTimeline]) -> some View {
        let home = e.homeCurrency
        let committed: Double = running.reduce(0) { acc, l in
            guard let co = e.state.company(l.companyID) else { return acc }
            return acc + l.value * e.currency(for: co).rate / max(home.rate, 0.000001)
        }
        let sub = running.isEmpty ? "Nothing running" : "\(running.count) running · \(store.short(committed)) committed"
        return HStack(spacing: 12) {
            IconCircle(glyph: Glyph.projects, size: 44)
            AppHeader(title: "Projects", subtitle: sub) {
                SmallOutlineButton(title: "New project") { part = .bids }
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
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                let n = count(item)
                Button { if !on { Haptics.choose(); selection = item } } label: {
                    Text(title(item) + (n > 0 ? " \(n)" : ""))
                        .font(.system(size: 13.5)).lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
                        .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.bottom, 1)
                        .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.tidyText).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                if !sub.isEmpty { Text(sub.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
