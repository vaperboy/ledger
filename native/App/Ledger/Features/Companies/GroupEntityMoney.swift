import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

struct GroupEntityMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var policyFor: PolicyTarget?

    private struct PolicyTarget: Identifiable { var id: Int }

    private var cos: [Company] {
        entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            profitBox
            ForEach(cos) { (c: Company) in
                if engine.isListed(companyID: c.id) {
                    PublicCompanyCard(engine: engine, company: c)
                } else if Shareholders.outside(c) > 0 {
                    dividendBox(c)
                }
            }
        }
        .centerSheet(item: $policyFor) { (t: PolicyTarget) in DividendPolicySheet(companyID: t.id).environmentObject(store) }
    }

    private var profitBox: some View {
        var month = 0.0
        var year = 0.0
        var revenue = 0.0
        for c in cos {
            let f = engine.financeOverview(companyID: c.id)
            month += f.monthProfit
            year += f.yearProfit
            revenue += f.monthRevenue
        }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Profit and loss").textStyle(.label, tint: Theme.inkFaint)
            FigureRow(items: [
                KeyFigures.Item(label: "Sales", value: store.short(revenue), sub: "this month"),
                KeyFigures.Item(label: "Profit", value: store.short(month), tint: Theme.change(month), sub: "this month"),
                KeyFigures.Item(label: "Profit", value: store.short(year), tint: Theme.change(year), sub: "this year"),
            ], columns: 3, size: .figure, combineCells: true)
            Text("Every cost and every sale goes through your own account. There is no separate company money.").textStyle(.caption, tint: Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dividendBox(_ c: Company) -> some View {
        let d = engine.lastDividendDecision(companyID: c.id)
        let chosen: String = engine.dividendPolicy(companyID: c.id)
        let last: String = d.map { (x: (week: Int, paid: Double, profit: Double)) -> String in
            (x.paid > 0 ? "Last payout \(store.short(x.paid, in: c))" : "Last quarter skipped") + " on profit \(store.short(x.profit, in: c))"
        } ?? "No dividend decided yet"
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Dividends \u{00B7} \(c.name)").textStyle(.label, tint: Theme.inkFaint)
            SharpTable {
                SettingsTableRow(title: "Dividend policy", value: Shareholders.policyNames[chosen] ?? chosen, opens: .sheet) { policyFor = PolicyTarget(id: c.id) }
            }
            Text(last).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2)
        }
    }
}

struct DividendPolicySheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    @State private var proposal: BoardProposal?

    var body: some View {
        let chosen: String = store.engine?.dividendPolicy(companyID: companyID) ?? "none"
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let proposal {
                BoardProposalSheet(proposal: proposal, onDone: { self.proposal = nil })
            } else {
                if let board = store.engine?.jvBoardCompany(companyID: companyID) {
                    Text("\(board.name) has co-owners, so a new policy is a proposal the owners vote on.").popupText(.caption)
                }
                ForEach(Shareholders.policies, id: \.self) { (p: String) in
                    ChoiceCard(title: Shareholders.policyNames[p] ?? p, subtitle: blurb(p), selected: chosen == p) { pick(p) }
                }
            }
        }
        .centerSheetTitle("Dividend policy")
    }

    private func blurb(_ p: String) -> String {
        switch p {
        case "none": return "Keep all profit in the company; no dividend."
        case "low": return "Once a quarter, a quarter of the quarter's profit goes to the owners."
        case "mid": return "Once a quarter, half of the quarter's profit goes to the owners."
        default: return "Once a quarter, most of the quarter's profit goes to the owners."
        }
    }

    private func pick(_ p: String) {
        let id: Int = companyID
        let name: String = Shareholders.policyNames[p] ?? p
        if let board = store.engine?.jvBoardCompany(companyID: id) {
            if p == store.engine?.dividendPolicy(companyID: id) { store.show("That is already the dividend policy."); return }
            proposal = BoardProposal(companyID: id, boardName: board.name, change: .policy(p), title: "Dividend policy: \(name.lowercased())", effect: blurb(p))
            return
        }
        store.settle(store.act { $0.setDividendPolicy(companyID: id, policy: p) }, "Dividend policy: \(name).", same: "That is already the dividend policy.")
    }
}
