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
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if members.count > 1 { picker(members, selected: co?.id ?? chosen) }
            if let co {
                header(co)
                chainOfCommand(co)
                people(co)
                approvalNote(co)
                ApplicantsLinkRow(engine: engine, companyID: co.id)
                openPosts(co)
            } else {
                Text("This company no longer exists.").textStyle(.body, tint: Theme.inkFaint)
            }
        }
    }

    // MARK: Picker

    private func picker(_ members: [Company], selected: Int) -> some View {
        WrapRow(spacing: Theme.Space.s) {
            ForEach(members) { (c: Company) in
                pickChip(c, on: c.id == selected)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pickChip(_ c: Company, on: Bool) -> some View {
        let id: Int = c.id
        return Button { Haptics.choose(); picked = id } label: {
            Text(c.name).textStyle(.body, tint: on ? Theme.ink : Theme.inkFaint, weight: on ? .semibold : .regular)
                .lineLimit(1)
                .padding(.horizontal, Theme.Space.m).frame(minHeight: 44)
                .background(Capsule().fill(on ? Theme.accentWash : Theme.surface))
                .contentShape(Capsule())
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
        return Card(padding: Theme.Space.m, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(count).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                if let line {
                    Text(delegationSentence(line, co))
                        .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("management-delegation")
                    Text("Highest rank here: \(line.top)").textStyle(.caption, tint: Theme.inkFaint)
                }
                if stakes > 0 {
                    Text("Stakes in other groups: " + store.short(stakes)).textStyle(.caption, tint: Theme.inkFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Complaints go to Sam. Payroll is approved by the accountant. Hiring is approved by you."
    private func delegationSentence(_ line: DelegationLine, _ co: Company) -> String {
        let runner: String? = engine.groupManagement().lines.first(where: { (l: GroupManagement.Line) -> Bool in l.id == co.id })?.runner?.name
        func who(_ role: String) -> String {
            switch role {
            case "Manager": return runner ?? "the manager"
            case "You", "You (a reminder)": return "you"
            case "Staff": return "the staff"
            default: return "the " + role.lowercased()
            }
        }
        return "Complaints go to \(who(line.complaints)). Payroll is approved by \(who(line.payroll)). Hiring is approved by \(who(line.rehire))."
    }

    // MARK: Chain of command

    /// Everyone between you and the company, top first: you, then the bosses above the runner, then the runner, each with what they may decide.
    private func rungs(_ co: Company) -> [GroupManagement.Rung] {
        guard let line = engine.groupManagement().lines.first(where: { (l: GroupManagement.Line) -> Bool in l.id == co.id }) else { return [] }
        var out: [GroupManagement.Rung] = Array(line.above.reversed())
        if let r = line.runner { out.append(r) }
        return out
    }

    private func commandRow(name: String, title: String, authority: String?, personID: Int?) -> some View {
        let person: Person? = personID.flatMap { (id: Int) -> Person? in engine.state.people[id] }
        return HStack(spacing: Theme.Space.m) {
            StructureAvatar(name: name, role: person?.role, face: person?.faceKey, size: 36)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(name).textStyle(.headline).lineLimit(1)
                Text(title).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            if let authority { AcctPill(text: authority, tone: .neutral) }
        }
        .padding(.vertical, Theme.Space.s).padding(.horizontal, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func chainOfCommand(_ co: Company) -> some View {
        let list: [GroupManagement.Rung] = rungs(co)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("CHAIN OF COMMAND").capsLabel()
            Card(padding: Theme.Space.xs, radius: Theme.Radius.hero) {
                VStack(spacing: 0) {
                    commandRow(name: engine.state.player.name, title: "Owner", authority: nil, personID: nil)
                    ForEach(list) { (r: GroupManagement.Rung) in
                        Hairline()
                        commandRow(name: r.name, title: r.title, authority: r.authorityText, personID: r.personID)
                    }
                    if list.isEmpty {
                        Hairline()
                        Text("Nobody manages \(co.name): you run it yourself.").textStyle(.caption, tint: Theme.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Space.s)
                    }
                }
            }
        }
        .accessibilityIdentifier("management-chain-of-command")
    }

    // MARK: People

    @ViewBuilder private func people(_ co: Company) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("MANAGEMENT").capsLabel()
            CompanyManagement(engine: engine, company: co, showAll: true)
            CompanyTeamRoster(engine: engine, company: co)
        }
    }

    // MARK: Who may appoint

    /// With a manager in place, hiring the assistant needs the role above to confirm.
    @ViewBuilder private func approvalNote(_ co: Company) -> some View {
        if let above = engine.appointmentAuthority(companyID: co.id, role: "assistant manager").needsConfirmationFrom {
            Text(above == .ceo ? "Assistant manager: needs confirmation from the CEO" : "Assistant manager: needs your confirmation")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Open posts

    @ViewBuilder private func openPosts(_ co: Company) -> some View {
        let all: [TeamOverview.Vacancy] = (store.teamOverviewNow ?? engine.teamOverview()).vacancies
        let mine: [TeamOverview.Vacancy] = all.filter { (v: TeamOverview.Vacancy) -> Bool in
            v.companyID == co.id || (entity.chainID != nil && v.chainID == entity.chainID)
        }
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("OPEN POSTS").capsLabel()
                Card(padding: Theme.Space.xs, radius: Theme.Radius.hero) {
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
