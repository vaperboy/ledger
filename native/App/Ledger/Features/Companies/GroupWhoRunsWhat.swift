import SwiftUI
import GameCore
import Simulation

/// "Who runs what" on the Group tab: one thin row per company with who runs it day to day, their title, how far they may decide, a gold
/// flag when they passed requests up to you, and the monthly wages. A row opens that company's team.
struct GroupWhoRunsWhat: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let overview: TeamOverview = engine.teamOverview()
        let lines: [TeamOverview.CompanyLine] = overview.companies.filter { (l: TeamOverview.CompanyLine) -> Bool in !l.isHolding }
        if !lines.isEmpty {
            LedgerSection("Who runs what") {
                VStack(spacing: Theme.Space.s) {
                    ForEach(lines) { (l: TeamOverview.CompanyLine) in
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

    private func row(_ l: TeamOverview.CompanyLine, passedUp: Int) -> some View {
        let face: String? = engine.state.company(l.id)?.managerID.flatMap { (id: Int) -> String? in engine.state.people[id]?.faceKey }
        let flag: String = passedUp > 0 ? " \u{00B7} \(passedUp) passed up to you" : ""
        let wages: String? = l.monthlyWages > 0 ? store.short(l.monthlyWages) + "/mo" : nil
        return Button { Haptics.tap(); store.openCompany(l.id, section: .staff) } label: {
            ThinPersonRow(name: l.managedBy, title: l.managerTitle ?? "Owner",
                          note: l.name + " \u{00B7} " + authority(l) + flag,
                          noteTint: passedUp > 0 ? Theme.gold : Theme.ivoryFaint,
                          wage: wages, roleKey: l.managerTitle, face: face)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("group-who-\(l.id)")
    }
}
