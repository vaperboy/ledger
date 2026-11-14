import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

private func roleLabel(_ id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }

enum StaffIssue {
    static func list(_ m: StaffMember) -> [String] {
        var out: [String] = []
        if m.noticeWeeks > 0 { out.append("on notice") }
        if let f = m.value("flag").isNull ? nil : m.str("flag"), let t = StaffProfile.problemText[f] { out.append(t) }
        if m.sickUntilWeek != nil { out.append("off sick") }
        if m.tiredness > 60 { out.append("tired") }
        if m.int("warn") > 0 { out.append("\(m.int("warn")) warning\(m.int("warn") == 1 ? "" : "s")") }
        return out
    }
    static func needsAttention(_ m: StaffMember) -> Bool { list(m).contains { !$0.hasSuffix("warning") && !$0.hasSuffix("warnings") } }
}

struct CompanyStaffRoster: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var pending: PendingAction?

    private var moods: [Int: String] {
        let cid: Int = company.id
        return store.memo("team-moods-\(cid)") { (e: GameEngine) -> [Int: String] in
            var out: [Int: String] = [:]
            for m in e.state.company(cid)?.staff ?? [] { if let w = e.workerProfile(companyID: cid, employeeID: m.id) { out[m.id] = w.mood } }
            return out
        } ?? [:]
    }

    var body: some View {
        let cur = engine.currency(for: company)
        let staff = company.staff
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = staff.filter { q.isEmpty || name($0).lowercased().contains(q) || roleLabel($0.role).lowercased().contains(q) }
        let attention = shown.filter(StaffIssue.needsAttention)
        let rest = shown.filter { !StaffIssue.needsAttention($0) }
        let big = staff.count > 8
        let mood: [Int: String] = moods
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if staff.count > 12 { LedgerField(placeholder: "Search by name or role", text: $query) }
            if !attention.isEmpty {
                group("To check \u{00B7} \(attention.count)", tint: P.caution) { rows(attention, cur, mood) }
            }
            if big {
                group(attention.isEmpty ? "People" : "Everyone else") {
                    let groups = Dictionary(grouping: rest, by: { $0.role }).sorted { $0.value.count > $1.value.count }
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.key) { (n: Int, g: (key: String, value: [StaffMember])) in
                            if n > 0 { Hairline() }
                            roleGroup(g.key, g.value, cur, mood, open: expanded.contains(g.key) || !q.isEmpty)
                        }
                    }
                }
            } else if !rest.isEmpty {
                group(attention.isEmpty ? "People" : "Everyone else") { rows(rest, cur, mood) }
            }
            if !q.isEmpty && shown.isEmpty { EmptyState(glyph: Glyph.search, title: "No one matches \"\(query)\"", centered: false) }
            layOffRow(cur)
        }
        .confirmAction($pending)
    }

    private func group<C: View>(_ title: String, tint: Color? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).textStyle(.label, tint: tint ?? P.inkFaint)
            content()
        }
    }

    private func rows(_ list: [StaffMember], _ cur: Currency, _ mood: [Int: String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, m: StaffMember) in
                if n > 0 { PersonRowRule() }
                row(m, cur, mood[m.id])
            }
        }
    }

    @ViewBuilder private func roleGroup(_ role: String, _ members: [StaffMember], _ cur: Currency, _ mood: [Int: String], open: Bool) -> some View {
        let pay: String = cur.tidyShort(members.reduce(0) { $0 + $1.monthlyWage })
        Button {
            Haptics.choose()
            Motion.animate(Motion.quickAnimation) { if open { expanded.remove(role) } else { expanded.insert(role) } }
        } label: {
            CardRowLabel(title: roleLabel(role), subtitle: "\(members.count) \(members.count == 1 ? "person" : "people")", value: pay, open: open)
        }.buttonStyle(PressableStyle())
        if open {
            rows(members, cur, mood).padding(.leading, Theme.Space.l)
        }
    }

    private func name(_ m: StaffMember) -> String { engine.state.people[m.id]?.name ?? roleLabel(m.role) }

    private func row(_ m: StaffMember, _ cur: Currency, _ mood: String?) -> some View {
        let attention: Bool = StaffIssue.needsAttention(m)
        let wage: String = cur.tidyShort(m.monthlyWage)
        let id: Int = m.id
        let cid: Int = company.id
        return Button { Haptics.tap(); store.workerPopup = WorkerPopupRef(id: id, companyID: cid) } label: {
            SlimWorkerRow(name: name(m), role: roleLabel(m.role), wage: wage, face: engine.state.people[m.id]?.faceKey, roleKey: m.role,
                          mood: mood, attention: attention, onNotice: m.noticeWeeks > 0)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("team-worker-\(id)")
    }

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
        }
    }

    private func confirmLayOff(_ n: Int, _ p: (names: [String], savesPerMonth: Double, severance: Double), _ cur: Currency) {
        pending = PendingAction(title: "Lay off \(n) \(n == 1 ? "person" : "people")?", message: "\(p.names.joined(separator: ", ")). Saves \(cur.tidyDisplay(p.savesPerMonth)) a month; severance of \(cur.tidyDisplay(p.severance)) is paid now and the mood of the rest drops.", button: "Lay off", destructive: true, tone: .danger, icon: "person.fill.badge.minus") {
            let ids = store.act { $0.layOffStaff(companyID: company.id, count: n) } ?? []
            Haptics.warning()
            store.show(ids.isEmpty ? "No one was let go." : "\(ids.count) \(ids.count == 1 ? "person" : "people") let go: \(cur.tidyDisplay(p.savesPerMonth)) a month saved, severance \(cur.tidyDisplay(p.severance)) paid. The rest are shaken.", tone: ids.isEmpty ? "warn" : "n")
        }
    }
}

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
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
