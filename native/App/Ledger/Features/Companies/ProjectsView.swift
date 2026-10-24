import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Projects tab: time-bound work. "Work" lists what is due across your companies (tenders to bid on, jobs and developments by
/// next date, each opening its milestones) and one row per project company that opens that company's Projects section; "Ventures" holds startups, funds and stakes.
struct ProjectsView: View {
    enum Part: String, CaseIterable, Hashable { case work = "Work", ventures = "Ventures" }
    @EnvironmentObject var store: GameStore
    @State private var part: Part = .work
    @State private var search = ""

    @State private var showAll = false

    var body: some View {
        NavigationStack {
            if let e = store.engine {
                let rows = e.state.companies.filter { $0.status.isLive }.compactMap { co in e.projectBoard(companyID: co.id).map { (co: co, board: $0) } }
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text("Projects").font(.serifTitle(28))
                        SectionTabs(items: Part.allCases, title: { $0.rawValue }, selection: $part, badge: { $0 == .work ? openTenders(rows) : 0 }).padding(.horizontal, -Theme.Space.margin)
                        switch part {
                        case .work: work(e, rows)
                        case .ventures: VenturesContent()
                        }
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                    .frame(maxWidth: 900).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .ledgerBackground()
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
    }

    private func openTenders(_ rows: [(co: Company, board: ProjectBoard)]) -> Int {
        rows.reduce(0) { $0 + $1.board.tenders.filter { $0.qualifies && $0.myBid == nil }.count }
    }

    // MARK: Work

    @ViewBuilder private func work(_ e: GameEngine, _ rows: [(co: Company, board: ProjectBoard)]) -> some View {
        let week = e.state.week
        let q = search.trimmingCharacters(in: .whitespaces)
        let all = e.projectTimelines()
        let shown = q.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.companyName.localizedCaseInsensitiveContains(q) || $0.subtitle.localizedCaseInsensitiveContains(q) }
        func soonest(_ a: ProjectTimeline, _ b: ProjectTimeline) -> Bool { (a.dueWeek ?? Int.max) < (b.dueWeek ?? Int.max) }
        let needs = shown.filter { $0.delayed || ($0.kind == .tender && ($0.dueWeek ?? Int.max) - week <= 2) }.sorted(by: soonest)
        let tenders = shown.filter { $0.kind == .tender && !needs.contains($0) }.sorted(by: soonest)
        let underWay = shown.filter { $0.kind != .tender && !needs.contains($0) }.sorted(by: soonest)
        if rows.isEmpty {
            LedgerSection("Company projects and tenders") {
                Text("Project companies (builders, agencies, developers) list their jobs, tenders and developments here. None of your companies takes projects yet.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
            }
        } else {
            KeyFigures(items: [
                .init(label: "Project companies", value: "\(rows.count)"),
                .init(label: "On the go", value: "\(rows.reduce(0) { $0 + $1.board.jobs.count + $1.board.developments.count })", sub: "\(rows.reduce(0) { $0 + $1.board.queuedJobs.count }) waiting"),
                .init(label: "Tenders to bid", value: "\(openTenders(rows))", tint: openTenders(rows) > 0 ? Theme.gold : Theme.ivory),
            ])
            if all.count > 6 {
                TextField("Search projects and companies", text: $search).textFieldStyle(.plain).padding(.vertical, 8).overlay(alignment: .bottom) { Hairline() }
            }
            if all.isEmpty {
                LedgerSection("Under way") {
                    Text("Nothing is under way or open for tender. Requests come in through the week; marketing and a good name bring more. Check staff and equipment under each company's Operations if a firm cannot take work.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            } else if shown.isEmpty {
                Text("No project matches.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
            }
            if !needs.isEmpty {
                LedgerSection(title: "Needs you", trailing: { Text("\(needs.count)").font(.system(size: 12)).foregroundStyle(Theme.caution) }) {
                    VStack(spacing: 0) { ForEach(Array(needs.prefix(10).enumerated()), id: \.element.id) { n, l in if n > 0 { Hairline() }; ProjectTimelineRow(line: l, now: week) } }
                }
            }
            if !underWay.isEmpty {
                let cap = showAll ? underWay.count : 12
                LedgerSection(title: "Under way", trailing: { Text("by next date").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
                    VStack(spacing: 0) { ForEach(Array(underWay.prefix(cap).enumerated()), id: \.element.id) { n, l in if n > 0 { Hairline() }; ProjectTimelineRow(line: l, now: week) } }
                    if underWay.count > 12 {
                        Button(showAll ? "Show fewer" : "Show all \(underWay.count)") { showAll.toggle() }.font(.system(size: 12)).foregroundStyle(Theme.gold).buttonStyle(.plain).padding(.top, 6)
                    }
                }
            }
            if !tenders.isEmpty {
                LedgerSection(title: "Open tenders", trailing: { Text("\(tenders.count)").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
                    VStack(spacing: 0) { ForEach(Array(tenders.prefix(8).enumerated()), id: \.element.id) { n, l in if n > 0 { Hairline() }; ProjectTimelineRow(line: l, now: week) } }
                    if tenders.count > 8 { Text("The rest are in each company's Projects section.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 4) }
                }
            }
            LedgerSection("Project companies") {
                let list = rows.filter { q.isEmpty || $0.co.name.localizedCaseInsensitiveContains(q) }
                    .sorted { $0.board.outstandingPayments > $1.board.outstandingPayments }
                VStack(spacing: 0) {
                    if list.isEmpty { Text("No company matches.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(Array(list.enumerated()), id: \.element.co.id) { n, r in
                        if n > 0 { Hairline() }
                        Button { openProjects(r.co.id) } label: { row(r.co, r.board) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func openProjects(_ id: Int) {
        Haptics.tap()
        store.openCompany(id, section: .projects)
    }

    private func row(_ co: Company, _ b: ProjectBoard) -> some View {
        let open = b.tenders.filter { $0.qualifies && $0.myBid == nil }.count
        let line: String
        if b.isDeveloper {
            line = "\(b.developments.count) \(b.developments.count == 1 ? "development" : "developments") · \(b.finishedCount) finished"
        } else {
            line = "\(b.jobs.count) on the go · \(b.queuedJobs.count) waiting · \(open) \(open == 1 ? "tender" : "tenders") open"
        }
        return HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(co.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(line).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !b.isDeveloper && b.outstandingPayments > 0 {
                Text(store.short(b.outstandingPayments, in: co)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
