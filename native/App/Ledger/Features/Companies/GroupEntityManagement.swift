import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Management tab of an entity page. A chain or group is picked company by company at the top (a compact chip row); below it come that
/// company's posts: the owner, the general manager (appointed by the owner), the assistant and the executive posts, and the posts still open.
struct GroupEntityManagement: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var picked: Int?

    private var liveMembers: [Company] {
        entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
    }

    var body: some View {
        let members: [Company] = liveMembers
        let chosen: Int = picked ?? entity.companyID
        let co: Company? = members.first { (c: Company) -> Bool in c.id == chosen } ?? engine.state.company(entity.companyID)
        VStack(alignment: .leading, spacing: 12) {
            if members.count > 1 { picker(members, selected: co?.id ?? chosen) }
            if let co {
                header(co)
                people(co)
                approvalNote(co)
                ApplicantsLinkRow(engine: engine, companyID: co.id)
                openPosts(co)
            } else {
                Text("This company no longer exists.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Picker

    private func picker(_ members: [Company], selected: Int) -> some View {
        WrapRow(spacing: 6) {
            ForEach(members) { (c: Company) in
                pickChip(c, on: c.id == selected)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pickChip(_ c: Company, on: Bool) -> some View {
        let id: Int = c.id
        return Button { Haptics.choose(); picked = id } label: {
            Text(c.name).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
                .lineLimit(1)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(Capsule().fill(on ? Theme.gold.opacity(0.16) : Theme.surface))
                .overlay(Capsule().strokeBorder(on ? Theme.gold : Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: Header

    /// Across the group: how many managers, how many companies you still run yourself, the group office; for this company: who takes
    /// the complaints, payroll and re-hiring and who decides first. Under it, what your stakes in other groups are worth.
    private func header(_ co: Company) -> some View {
        let gm: GroupManagement = engine.groupManagement()
        let line: DelegationLine? = engine.delegationLines().first { (d: DelegationLine) -> Bool in d.id == co.id }
        let stakes: Double = GroupStakes.stakesValue(engine.state)
        let office: String = gm.groupOfficeEstablished ? "Group office set up" : "No group office"
        let count: String = "\(gm.managerCount) manager\(gm.managerCount == 1 ? "" : "s") \u{00B7} you run \(gm.runByYou.count) yourself \u{00B7} " + office
        return Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 4) {
                Text(count).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                if let line {
                    Text("Complaints: \(line.complaints) \u{00B7} Payroll: \(line.payroll) \u{00B7} Re-hiring: \(line.rehire)")
                        .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    Text("Highest rank here: \(line.top)").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                }
                if stakes > 0 {
                    Text("Stakes in other groups: " + store.short(stakes)).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: People

    @ViewBuilder private func people(_ co: Company) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANAGEMENT").capsLabel()
            CompanyManagement(engine: engine, company: co, showAll: true)
            CompanyTeamRoster(engine: engine, company: co)
        }
    }

    // MARK: Who may appoint

    /// The owner appoints the general manager. The assistant is the general manager's own helper, so with a manager in place the hire needs the
    /// role above (you) to confirm; the manager's proposals reach you in the Inbox.
    @ViewBuilder private func approvalNote(_ co: Company) -> some View {
        let asst: AppointmentAuthority = engine.appointmentAuthority(companyID: co.id, role: "assistant manager")
        let gm: AppointmentAuthority = engine.appointmentAuthority(companyID: co.id, role: "general manager")
        VStack(alignment: .leading, spacing: 3) {
            Text(gm.reason).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            if let above = asst.needsConfirmationFrom {
                Text(above == .ceo ? "Assistant manager: needs confirmation from the CEO" : "Assistant manager: needs your confirmation")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
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
                            OpenPostRow(engine: engine, vacancy: v, first: n == 0)
                        }
                    }
                }
            }
        }
    }
}
