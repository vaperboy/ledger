import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Projects tab: time-bound work. "Work" lists what is due across your companies (tenders to bid on, jobs and developments by
/// deadline) and one row per project company that opens that company's Projects section; "Ventures" holds startups, funds and stakes.
struct ProjectsView: View {
    enum Part: String, CaseIterable, Hashable { case work = "Work", ventures = "Ventures" }
    @EnvironmentObject var store: GameStore
    @State private var part: Part = .work
    @State private var path: [CompanyRoute] = []
    @State private var search = ""

    private struct Item: Identifiable {
        var id: String
        var co: Company
        var title: String
        var detail: String
        var progress: Double?
        var week: Int?          // deadline / award / completion week
        var urgent: Bool
        var kind: String
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                .companyRouteDestinations()
                .routeRequests(for: .projects, path: $path)
                .returnBar(for: .projects)
            }
        }
    }

    private func openTenders(_ rows: [(co: Company, board: ProjectBoard)]) -> Int {
        rows.reduce(0) { $0 + $1.board.tenders.filter { $0.qualifies && $0.myBid == nil }.count }
    }

    // MARK: Work

    @ViewBuilder private func work(_ e: GameEngine, _ rows: [(co: Company, board: ProjectBoard)]) -> some View {
        let week = e.state.week
        let items = items(rows)
        let q = search.trimmingCharacters(in: .whitespaces)
        let shown = q.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.co.name.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q) }
        let due = shown.filter { $0.week != nil }.sorted { ($0.week ?? 0) < ($1.week ?? 0) }
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
            if items.count > 6 {
                TextField("Search projects and companies", text: $search).textFieldStyle(.plain).padding(.vertical, 8).overlay(alignment: .bottom) { Hairline() }
            }
            let needs = shown.filter { $0.urgent }
            if !needs.isEmpty {
                LedgerSection(title: "Needs you", trailing: { Text("\(needs.count)").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
                    VStack(spacing: 0) { ForEach(Array(needs.prefix(10).enumerated()), id: \.element.id) { n, i in if n > 0 { Hairline() }; itemRow(i, week) } }
                }
            }
            if !due.isEmpty {
                LedgerSection(title: "By deadline", trailing: { Text("\(due.count) with a date").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
                    VStack(spacing: 0) { ForEach(Array(due.prefix(12).enumerated()), id: \.element.id) { n, i in if n > 0 { Hairline() }; itemRow(i, week) } }
                    if due.count > 12 { Text("The rest is in each company's Projects section.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 4) }
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

    private func items(_ rows: [(co: Company, board: ProjectBoard)]) -> [Item] {
        var out: [Item] = []
        for r in rows {
            let co = r.co, b = r.board
            for t in b.tenders where t.qualifies && t.myBid == nil {
                out.append(Item(id: "t\(co.id)-\(t.id)", co: co, title: t.title, detail: "Tender · \(t.buyer) · worth \(store.short(t.worth, in: co)) · bid costs \(store.short(t.bidCost, in: co))",
                                progress: nil, week: t.awardWeek, urgent: t.weeksToBid <= 2, kind: "tender"))
            }
            for t in b.myTenders where t.outcome == nil {
                out.append(Item(id: "m\(co.id)-\(t.id)", co: co, title: t.title, detail: "Your bid is in · decided in week \(t.awardWeek)", progress: nil, week: t.awardWeek, urgent: false, kind: "bid"))
            }
            for j in b.jobs {
                out.append(Item(id: "j\(co.id)-\(j.id)", co: co, title: j.title, detail: "\(j.client) · \(store.short(j.value, in: co))" + (j.held ? " · on hold" : ""),
                                progress: j.progress, week: j.dueWeek, urgent: j.held, kind: "job"))
            }
            for d in b.developments {
                out.append(Item(id: "d\(co.id)-\(d.id)", co: co, title: d.name, detail: "\(d.stage) · \(d.sold) of \(d.units) sold" + (d.delayWeeks > 0 ? " · \(d.delayWeeks) wk late" : ""),
                                progress: nil, week: d.weeksLeft > 0 ? store.engine.map { $0.state.week + d.weeksLeft } : nil, urgent: d.delayWeeks > 0, kind: "dev"))
            }
        }
        return out
    }

    private func itemRow(_ i: Item, _ now: Int) -> some View {
        Button { openProjects(i.co.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(i.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text("\(i.co.name) · \(i.detail)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(2)
                    if let p = i.progress { ProgressView(value: min(1, max(0, p))).tint(Theme.gold) }
                }
                Spacer(minLength: 8)
                if let w = i.week {
                    let left = w - now
                    Text(left <= 0 ? "due" : left == 1 ? "1 wk" : "\(left) wk").font(.system(size: 12).monospacedDigit()).foregroundStyle(left <= 2 ? Theme.caution : Theme.ivoryMuted)
                }
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }.padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("open-project-company")
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
