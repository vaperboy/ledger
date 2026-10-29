import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Small flat sections of a company that belong to no bigger screen: customer complaints, developing something new, (giving up premises and changing the
/// accountant moved to Workplace and Insurance and advisers). Placed at the end of Operations. Ivory Ledger rows, no boxes.
struct CompanyOtherSections: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            complaints
            development
        }
    }

    // MARK: Complaints

    @ViewBuilder private var complaints: some View {
        let open = engine.openComplaints(companyID: company.id)
        if !open.isEmpty {
            LedgerSection(title: "Complaints", trailing: { Text("answer within two weeks").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                ForEach(Array(open.enumerated()), id: \.offset) { n, c in
                    VStack(alignment: .leading, spacing: 6) {
                        if n > 0 { Hairline() }
                        Text(c["who"].string).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("\u{201C}\(c["t"].string)\u{201D}").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        HStack {
                            Button("Refund") { answer(c, .refund) }
                            Button("Apologise") { answer(c, .sorry) }
                            Button("Ignore") { answer(c, .ignore) }
                        }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }
    }

    private func answer(_ c: JSONValue, _ a: Satisfaction.Answer) {
        let r = store.act { $0.answerComplaint(companyID: company.id, complaintID: c["id"].int, answer: a) }
        switch (a, r ?? nil) {
        case (.refund, _): store.show("Refunded. The customer is satisfied.", tone: "good")
        case (.sorry, true?): store.show("They accepted the apology.", tone: "good")
        case (.sorry, _): store.show("They are still unhappy.", tone: "warn")
        default: store.show("Ignored. Expect a bad review.", tone: "warn")
        }
    }

    // MARK: Development

    @ViewBuilder private var development: some View {
        let list = engine.developmentProjects(companyID: company.id)
        if !list.isEmpty, company.status == .open {
            let cur = engine.currency(for: company)
            let run = Development.running(company)
            LedgerSection(title: "Develop something new", trailing: {
                if let run { Text("\(max(0, run.weeksLeft - engine.state.week).weeksText) to go").font(.system(size: 11)).foregroundStyle(Theme.caution) }
            }) {
                if let run, let p = list.first(where: { $0.project.id == run.project }) {
                    FlatRow(label: p.project.name, value: cur.tidyShort(run.cost), sub: "Spent. The team's skill and your quality decide how well it works.", rule: false)
                } else {
                    ForEach(Array(list.enumerated()), id: \.offset) { n, x in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x.project.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text("\(x.project.text) · \(x.project.weeks) weeks · \(cur.tidyShort(x.cost))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Button("Start") { start(x.project) }.buttonStyle(QuietButtonStyle())
                        }
                        if n < list.count - 1 { Hairline() }
                    }
                }
                let live = Development.finished(company)
                if !live.isEmpty {
                    Text("Working now: " + live.map { "\($0["n"].string) (\(Int(($0["mag"].double * 100).rounded()))%)" }.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func start(_ p: Development.Project) {
        switch store.act({ $0.startDevelopment(companyID: company.id, project: p.id) }) {
        case .ok?: Haptics.success(); store.show("Development started.", tone: "good")
        case .notEnoughCash?: store.show("Not enough cash in the company.", tone: "warn")
        case .busy?: store.show("One project at a time.", tone: "warn")
        default: store.show("Not possible right now.", tone: "warn")
        }
    }
}

/// Places in a chain that are short of a role, with a sister store that has one to spare.
struct ChainStaffShortages: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var chainID: Int

    var body: some View {
        let list = engine.staffShortages(chainID: chainID)
        if !list.isEmpty {
            LedgerSection("Short of staff") {
                ForEach(Array(list.prefix(6).enumerated()), id: \.offset) { n, x in
                    if n > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(engine.state.company(x.storeID)?.name ?? "Store").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text("Needs a \(x.role)" + (x.spareAtStoreID.flatMap { engine.state.company($0)?.name }.map { " · \($0) has one spare" } ?? "")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        if let from = x.spareAtStoreID {
                            Button("Move one") { if store.act({ $0.lendWorker(from: from, to: x.storeID, role: x.role) }) == true { Haptics.success() } }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
        }
    }
}
