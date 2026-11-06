import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

private func roleLabel(_ id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }

/// What is wrong with one team member, from fields the engine keeps on them. Empty means nothing to act on.
enum StaffIssue {
    static func list(_ m: StaffMember) -> [String] {
        var out: [String] = []
        if m.noticeWeeks > 0 { out.append("on notice") }
        if let f = m.value("flag").isNull ? nil : m.str("flag"), let t = StaffProfile.problemText[f] { out.append(t) }
        if m.sickUntilWeek != nil { out.append("off sick") }
        if m.tiredness > 60 { out.append("tired") }
        let papers = StaffExtras.missing(m).count
        if papers > 0 { out.append("\(papers) papers missing") }
        if m.int("warn") > 0 { out.append("\(m.int("warn")) warning\(m.int("warn") == 1 ? "" : "s")") }
        return out
    }
    /// Only the ones that need the owner (a warning on file alone does not).
    static func needsAttention(_ m: StaffMember) -> Bool { list(m).contains { !$0.hasSuffix("warning") && !$0.hasSuffix("warnings") } }
}

/// The company's own staff: paperwork first, then people who need attention, then everyone else, grouped by role once the team is big.
/// A tap pushes the person's profile, where every action on them lives. The head count and the wage total are shown by the Team tab.
struct CompanyStaffRoster: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var pending: PendingAction?
    /// The worker whose profile page is pushed; the Team tab owns the push so it outlives this list.
    @Binding var profile: WorkerRef?

    var body: some View {
        let cur = engine.currency(for: company)
        let staff = company.staff
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = staff.filter { q.isEmpty || name($0).lowercased().contains(q) || roleLabel($0.role).lowercased().contains(q) }
        let attention = shown.filter(StaffIssue.needsAttention)
        let rest = shown.filter { !StaffIssue.needsAttention($0) }
        let big = staff.count > 8
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if staff.count > 12 { LedgerField(placeholder: "Search by name or role", text: $query) }
            paperwork
            if !attention.isEmpty {
                Text("Needs attention \u{00B7} \(attention.count)").textStyle(.label, tint: P.warn)
                ForEach(attention) { m in row(m, cur) }
            }
            if big {
                let groups = Dictionary(grouping: rest, by: { $0.role }).sorted { $0.value.count > $1.value.count }
                ForEach(groups, id: \.key) { role, members in
                    let open = expanded.contains(role) || !q.isEmpty
                    let pay: String = cur.tidyShort(members.reduce(0) { $0 + $1.monthlyWage }) + " a month"
                    Button {
                        Haptics.choose()
                        Motion.animate(Motion.quickAnimation) { if open { expanded.remove(role) } else { expanded.insert(role) } }
                    } label: {
                        CardRowLabel(title: roleLabel(role), subtitle: "\(members.count) \(members.count == 1 ? "person" : "people")", value: pay, open: open)
                    }.buttonStyle(PressableStyle())
                    if open { ForEach(members) { m in row(m, cur) } }
                }
            } else {
                ForEach(rest) { m in row(m, cur) }
            }
            if !q.isEmpty && shown.isEmpty { EmptyState(glyph: Glyph.search, title: "No one matches \"\(query)\"", centered: false) }
            layOffRow(cur)
        }
        .confirmAction($pending)
    }

    private func name(_ m: StaffMember) -> String { engine.state.people[m.id]?.name ?? roleLabel(m.role) }

    private func row(_ m: StaffMember, _ cur: Currency) -> some View {
        let issues: [String] = StaffIssue.list(m)
        let attention: Bool = StaffIssue.needsAttention(m)
        let note: String = issues.isEmpty ? "" : issues.joined(separator: " \u{00B7} ")
        let wage: String = cur.tidyShort(m.monthlyWage)
        let id: Int = m.id
        return Button { Haptics.tap(); profile = WorkerRef(id: id) } label: {
            ThinPersonRow(name: name(m), title: roleLabel(m.role), note: note, noteTint: attention ? P.warn : P.inkFaint, wage: wage, roleKey: m.role,
                          face: engine.state.people[m.id]?.faceKey)
        }.buttonStyle(PressableStyle())
    }

    /// Missing paperwork across the team, with one action that ticks it all. Nothing when every file is complete.
    @ViewBuilder private var paperwork: some View {
        let staff = company.staff
        let papers = staff.reduce(0) { $0 + StaffExtras.missing($1).count }
        if papers > 0 {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.medium, tint: P.warn)
                Text("\(papers) paperwork \(papers == 1 ? "item" : "items") missing. An inspection can fine you.").textStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.s)
                TeamAction(title: "Do all") {
                    var done = 0
                    for m in staff { done += store.act({ $0.completePaperwork(companyID: company.id, personID: m.id) }) ?? 0 }
                    let left = store.engine?.state.company(company.id).map { $0.staff.reduce(0) { $0 + StaffExtras.missing($1).count } } ?? papers
                    if done > 0 && left == 0 { Haptics.success(); store.show("Paperwork done: \(done) \(done == 1 ? "item" : "items") ticked.", tone: "good") }
                    else if done > 0 { Haptics.warning(); store.show("\(done) \(done == 1 ? "item" : "items") ticked; \(left) still missing.", tone: "warn") }
                    else { Haptics.warning(); store.show("Nothing could be ticked.", tone: "warn") }
                }
            }
            .padding(.vertical, Theme.Space.xs)
        }
    }

    /// Cutting costs: a quiet row at the end of the list whose menu picks how many of the weakest go; each choice asks first.
    @ViewBuilder private func layOffRow(_ cur: Currency) -> some View {
        let staff = company.staff
        if staff.count > 1 {
            Menu {
                ForEach([1, 2, 3, 5].filter { $0 < staff.count }, id: \.self) { n in
                    let p = engine.layoffPreview(companyID: company.id, count: n)
                    Button("\(n) \u{00B7} saves \(cur.tidyShort(p.savesPerMonth)) a month") { confirmLayOff(n, p, cur) }
                }
            } label: {
                LedgerRow(leading: .symbol("person.fill.badge.minus"), leadingTint: P.loss, title: "Lay off the weakest",
                          subtitle: "Cuts the wage bill; severance is paid now", chevron: true)
            }
            .overlay(alignment: .top) { Hairline() }
            .padding(.top, Theme.Space.s)
        }
    }

    private func confirmLayOff(_ n: Int, _ p: (names: [String], savesPerMonth: Double, severance: Double), _ cur: Currency) {
        pending = PendingAction(title: "Lay off \(n) \(n == 1 ? "person" : "people")?", message: "\(p.names.joined(separator: ", ")). Saves \(cur.tidyDisplay(p.savesPerMonth)) a month; severance of \(cur.tidyDisplay(p.severance)) is paid now and the mood of the rest drops.", button: "Lay off", destructive: true) {
            let ids = store.act { $0.layOffStaff(companyID: company.id, count: n) } ?? []
            Haptics.warning()
            store.show(ids.isEmpty ? "No one was let go." : "\(ids.count) \(ids.count == 1 ? "person" : "people") let go: \(cur.tidyDisplay(p.savesPerMonth)) a month saved, severance \(cur.tidyDisplay(p.severance)) paid. The rest are shaken.", tone: ids.isEmpty ? "warn" : "n")
        }
    }
}

/// A group header of a long list (a role with its head count and pay): a row on the inset tone that opens or closes the people under it.
struct CardRowLabel: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var subtitle: String
    var value: String
    var open: Bool

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.accent).rotationEffect(.degrees(open ? 90 : 0))
            VStack(alignment: .leading, spacing: 0) {
                Text(title.tidyText).textStyle(.headline)
                Text(subtitle.tidyText).textStyle(.caption)
            }
            Spacer(minLength: Theme.Space.s)
            Text(value).textStyle(.body, tint: P.inkSoft, numeric: true).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.inset))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
