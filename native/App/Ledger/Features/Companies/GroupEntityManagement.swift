import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Management tab of an entity page, scoped to ONE company (a chain: its flagship store; a holding: the holding): the owner, the general
/// manager and the assistant as thin rows, the executive posts hired for this company (managing director, department heads, regional
/// managers), "Who decides what" and the management posts still open. The popups are the ones the old Team tab used.
struct GroupEntityManagement: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var decide: DecideRef?

    var body: some View {
        let co: Company? = engine.state.company(entity.companyID)
        VStack(alignment: .leading, spacing: 14) {
            if let co {
                people(co)
                decides(co)
                openPosts(co)
            } else {
                Text("This company no longer exists.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            }
        }
        .centerSheet(item: $decide) { (d: DecideRef) -> AnyView in
            AnyView(DecidesSheet(companyID: d.companyID, kind: d.kind).environmentObject(store))
        }
    }

    // MARK: People

    @ViewBuilder private func people(_ co: Company) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANAGEMENT").capsLabel()
            CompanyManagement(engine: engine, company: co, showAll: true)
            CompanyTeamRoster(engine: engine, company: co)
            if entity.isChain && entity.members.count > 1 {
                Text("Showing the flagship store. Every other store has its own manager: open it from the chain's Overview.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Who decides what

    @ViewBuilder private func decides(_ co: Company) -> some View {
        let o: TeamOverview = engine.teamOverview()
        let alerts: [PayrollAlertInfo] = engine.payrollAlertInfos()
        if !entity.isHolding, let l = o.companies.first(where: { (x: TeamOverview.CompanyLine) -> Bool in x.id == co.id }) {
            let rows: [OverviewRowData] = decidesRows(l, co, alerts)
            OverviewTable(title: "Who decides what", rows: rows) {
                EmptyView()
            }
        }
    }

    private func decidesRows(_ l: TeamOverview.CompanyLine, _ co: Company, _ alerts: [PayrollAlertInfo]) -> [OverviewRowData] {
        let hasMgr: Bool = l.authority >= 0
        let lvl: Int = max(0, l.authority)
        let nobodyPays: Bool = alerts.contains { (a: PayrollAlertInfo) -> Bool in a.companyID == l.id }
        let buy: Double = co.value("auth")["buy"].double
        let limitText: String = "up to " + store.short(buy, in: co)
        let spend: String = !hasMgr || lvl == 0 ? "Ask me always" : lvl == 1 ? "Manager, \(limitText)" : "Manager decides alone"
        let hire: String = !hasMgr || lvl == 0 ? "You" : lvl == 1 ? "Manager, \(limitText)" : "Manager decides alone"
        let byRule: Bool = hasMgr && lvl >= 1
        let id: Int = l.id
        let leaving: String = l.managerLeaving ? " (leaving)" : ""
        let runsValue: String = l.delegated ? l.managedBy + leaving : "You"
        let runsNote: String = l.delegated ? (l.managerTitle ?? "manager").lowercased() : "appoint a manager"
        let runs = OverviewRowData(id: "run\(id)", glyph: Glyph.ovKey, title: "Runs it", value: runsValue, note: runsNote,
                                   noteTint: l.delegated ? Theme.ivoryFaint : Theme.caution, action: { decide = DecideRef(companyID: id, kind: .runs) })
        let payNote: String = nobodyPays ? "no accountant" : (byRule ? "rule set" : "your call")
        let payValue: String = byRule ? "\(l.managedBy), by their rule" : "You, every month"
        let payroll = OverviewRowData(id: "pay\(id)", glyph: Glyph.ovCoin, title: "Payroll", value: payValue, note: payNote,
                                      noteTint: nobodyPays ? Theme.caution : Theme.ivoryFaint, action: { decide = DecideRef(companyID: id, kind: .payroll) })
        let spending = OverviewRowData(id: "spend\(id)", glyph: Glyph.ovShield, title: "Spending", value: spend, note: "set limit",
                                       noteTint: Theme.gold, action: { decide = DecideRef(companyID: id, kind: .spending) })
        let hiring = OverviewRowData(id: "hire\(id)", glyph: Glyph.person, title: "Hiring", value: hire, note: hasMgr ? "change" : "delegate",
                                     noteTint: Theme.gold, action: { decide = DecideRef(companyID: id, kind: .hiring) })
        return [runs, payroll, hiring, spending]
    }

    // MARK: Open posts

    @ViewBuilder private func openPosts(_ co: Company) -> some View {
        let all: [TeamOverview.Vacancy] = engine.teamOverview().vacancies
        let mine: [TeamOverview.Vacancy] = all.filter { (v: TeamOverview.Vacancy) -> Bool in
            v.companyID == co.id || (entity.chainID != nil && v.chainID == entity.chainID)
        }
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("OPEN POSTS").capsLabel()
                Card(padding: 4, radius: Theme.Radius.hero) {
                    VStack(spacing: 0) {
                        ForEach(Array(mine.enumerated()), id: \.element.id) { (n: Int, v: TeamOverview.Vacancy) in
                            vacancyRow(v, first: n == 0)
                        }
                    }
                }
            }
        }
    }

    private func vacancyRow(_ v: TeamOverview.Vacancy, first: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(v.detail).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(v.needed ? "Needed now" : "Open").font(.system(size: 12, weight: .medium)).foregroundStyle(v.needed ? Theme.loss : Theme.gold)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.divider).frame(height: 1) } }
    }
}
