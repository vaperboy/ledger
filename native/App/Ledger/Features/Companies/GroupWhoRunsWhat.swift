import SwiftUI
import GameCore
import Simulation

/// "Who runs what" on the Group tab: one thin row per company with who runs it day to day, their title, how far they may decide, a gold
/// flag when they passed requests up to you, and the monthly wages. A row opens that company's team.
struct GroupWhoRunsWhat: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let overview: TeamOverview = (store.teamOverviewNow ?? engine.teamOverview())
        let lines: [TeamOverview.CompanyLine] = overview.companies.filter { (l: TeamOverview.CompanyLine) -> Bool in !l.isHolding }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Who runs what").textStyle(.label, tint: Theme.inkFaint)
                    Spacer(minLength: Theme.Space.s)
                    Text("Wages a month").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { (n: Int, l: TeamOverview.CompanyLine) in
                        if n > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                        row(l, passedUp: overview.issues.filter { (i: TeamOverview.Issue) -> Bool in i.companyID == l.id && i.beyondAuthority }.count)
                    }
                }
            }
        }
    }

    /// "Within limits" / "Asks you first" / "Full control" for a manager, else nothing to say about authority.
    private func authority(_ l: TeamOverview.CompanyLine) -> String {
        switch l.authority {
        case 0: return "Asks you first"
        case 1: return "Within your limits"
        case 2: return "Full control"
        default: return "No manager"
        }
    }

    /// One company: its name, who runs it and how far they may decide; the wages at the right. Opens the company's team.
    private func row(_ l: TeamOverview.CompanyLine, passedUp: Int) -> some View {
        let face: String? = engine.state.company(l.id)?.managerID.flatMap { (id: Int) -> String? in engine.state.people[id]?.faceKey }
        let who: String = l.managedBy + " \u{00B7} " + (l.managerTitle ?? "Owner")
        let note: String = passedUp > 0 ? "\(passedUp) passed up to you" : authority(l)
        return LedgerRow(leading: .thumb(ThumbSpec(kind: .person, key: l.managerTitle ?? "owner", initials: l.managedBy, face: face)),
                         title: l.name, subtitle: who + " \u{00B7} " + note,
                         value: l.monthlyWages > 0 ? store.short(l.monthlyWages) : "", lineLimit: 2,
                         identifier: "group-who-\(l.id)", action: { store.openCompany(l.id, section: .staff) })
    }
}
