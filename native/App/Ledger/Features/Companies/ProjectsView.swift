import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Projects tab: time-bound work across your companies (jobs, tenders, developments) and your ventures (startups, private equity).
/// A company row opens that company's Projects section; the ventures are the same content as under Money, Invest.
struct ProjectsView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        NavigationStack {
            if let e = store.engine {
                let rows = e.state.companies.filter { $0.status.isLive }.compactMap { co in e.projectBoard(companyID: co.id).map { (co: co, board: $0) } }
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text("Projects").font(.serifTitle(28))
                        LedgerSection("Company projects and tenders") {
                            if rows.isEmpty {
                                Text("Project companies (builders, agencies, developers) list their jobs, tenders and developments here.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.co.id) { n, r in
                                    if n > 0 { Hairline() }
                                    Button { openProjects(r.co.id) } label: { row(r.co, r.board) }.buttonStyle(.plain)
                                }
                            }
                        }
                        VenturesContent()
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
