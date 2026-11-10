import SwiftUI
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

struct TeamInitials: View {
    var name: String?
    var size: CGFloat = 42

    private var letters: String {
        guard let name else { return "" }
        let parts: [Substring] = name.split(separator: " ")
        let first: String = parts.first.map { String($0.prefix(1)) } ?? ""
        let last: String = parts.count > 1 ? (parts.last.map { String($0.prefix(1)) } ?? "") : ""
        return (first + last).uppercased()
    }

    var body: some View {
        if name == nil {
            IconCircle(glyph: Glyph.hire, size: size, tint: Theme.inkSoft)
        } else {
            ZStack {
                Circle().fill(Theme.accentWash)
                Text(letters)
                    .font(.serifTitle(size * 0.38)).foregroundStyle(Theme.accent)
                    .lineLimit(1).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                    .padding(.horizontal, size * 0.08)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

struct TeamBadge: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var tint: Color = Theme.inkSoft

    var body: some View {
        Text(text.tidyText)
            .textStyle(.caption, tint: tint, weight: .medium).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }
}

struct PersonCard: View {
    @Environment(\.outsidePalette) private var P
    var name: String?
    var role: String
    var scope: String
    var note: String = ""
    var noteTint: Color = Theme.inkFaint
    var wage: String? = nil
    var chevron = true
    var roleKey: String? = nil
    var face: String? = nil

    init(row: ManagementRow, chevron: Bool = true) {
        self.name = row.name; self.role = row.role; self.scope = row.scope
        self.note = row.line; self.noteTint = row.lineTint; self.wage = row.wage; self.chevron = chevron
        self.face = row.face
    }

    init(name: String?, role: String, scope: String, note: String = "", noteTint: Color = Theme.inkFaint, wage: String? = nil, chevron: Bool = true, roleKey: String? = nil, face: String? = nil) {
        self.name = name; self.role = role; self.scope = scope
        self.note = note; self.noteTint = noteTint; self.wage = wage; self.chevron = chevron; self.roleKey = roleKey
        self.face = face
    }

    @ViewBuilder private var portrait: some View {
        if name == nil {
            TeamInitials(name: nil)
        } else {
            ThumbnailView(kind: .person, key: roleKey ?? role, size: 42, initials: name, face: face)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            portrait
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text((name ?? "Vacant").tidyText).textStyle(.headline, tint: name == nil ? P.inkSoft : P.ink).lineLimit(1)
                Text((role + " \u{00B7} " + scope).tidyText).textStyle(.caption, tint: P.inkSoft).lineLimit(1)
                if !note.isEmpty {
                    Text(note.tidyText).textStyle(.caption, tint: noteTint)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if let wage {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(wage).textStyle(.headline, tint: P.ink, numeric: true).lineLimit(1)
                    Text("a month").textStyle(.caption, tint: P.inkFaint)
                }
            }
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint) }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct TeamGroup<Content: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).capsLabel()
                Spacer(minLength: Theme.Space.s)
                trailing()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
extension TeamGroup where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

struct TeamCardGroup<Content: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        TeamGroup(title: title, trailing: trailing) {
            Card(padding: Theme.Space.l, radius: Theme.Radius.medium) { content() }
        }
    }
}
extension TeamCardGroup where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

struct TeamAction: View {
    var title: String
    var tint: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: tint))
    }
}

struct CompanyTeamRoster: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var openSlot: SlotRef?
    @State private var candidates: [String: [Int]] = [:]

    struct SlotRef: Identifiable { var id: String }

    var body: some View {
        let slots = engine.teamSlots(companyID: company.id)
        if !CompanyManagement.showsRoster(company) && !slots.isEmpty {
            let cur = engine.currency(for: company)
            TeamGroup(title: "Management", trailing: {
                let open = slots.filter { $0.personID == nil }.count
                Text(open > 0 ? "\(open) vacant" : "all filled").textStyle(.caption, tint: open > 0 ? Theme.warn : Theme.inkFaint)
            }) {
                VStack(spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { (n: Int, slot: ManagerModel.TeamSlot) in
                        let row: ManagementRow = TeamSlotSheet.row(slot, company: company, engine: engine, cur: cur)
                        if n > 0 { PersonRowRule() }
                        Button { Haptics.tap(); openSlot = SlotRef(id: slot.id) } label: { PersonCard(row: row) }.buttonStyle(PressableStyle())
                    }
                }
            }
            .centerSheet(item: $openSlot, category: .detail, tone: .info) { ref in
                TeamSlotSheet(companyID: company.id, slotID: ref.id, candidates: Binding(get: { candidates[ref.id] ?? [] }, set: { candidates[ref.id] = $0 }))
                    .environmentObject(store)
            }
        }
    }
}

struct TeamSlotSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var slotID: String
    @Binding var candidates: [Int]
    @State private var pending: PendingAction?

    static func scope(_ slot: ManagerModel.TeamSlot, company: Company) -> String {
        switch slot.key { case "ceo": return company.type == "hold" ? "group" : "company"; case "reg": return "region"; default: return "company" }
    }

    static func budget(of slot: ManagerModel.TeamSlot) -> Budget { Budget(rawValue: min(2, max(0, slot.level))) ?? .tight }

    static func row(_ slot: ManagerModel.TeamSlot, company: Company, engine: GameEngine, cur: Currency) -> ManagementRow {
        let person = slot.personID.flatMap { engine.state.people[$0] }
        let line: String
        if person == nil { line = slot.detail }
        else if slot.key == "ceo" { line = "Budget \u{00B7} " + budget(of: slot).title }
        else { line = "Since \(GameCalendar.dateString(week: slot.since, dayOffset: 0))" }
        return ManagementRow(name: person?.name, role: slot.title, scope: scope(slot, company: company), line: line, wage: person == nil ? nil : cur.tidyShort(slot.monthlyWage),
                             face: person?.faceKey)
    }

    var body: some View {
        PeopleSheet(title: "Management post") {
            if let e = store.engine, let co = e.state.company(companyID), let slot = e.teamSlots(companyID: companyID).first(where: { $0.id == slotID }) {
                let cur = e.currency(for: co)
                let head: ManagementRow = Self.row(slot, company: co, engine: e, cur: cur)
                PersonCard(row: head, chevron: false)
                if let pid = slot.personID, let p = e.state.people[pid] { filled(slot, p, co, cur) } else { vacant(slot, co, cur, e) }
            } else {
                Text("This post no longer exists.").popupText(.body)
            }
        }
        .confirmAction($pending)
    }

    @ViewBuilder private func filled(_ slot: ManagerModel.TeamSlot, _ p: Person, _ co: Company, _ cur: Currency) -> some View {
        LedgerSection("Who") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                FlatRow(label: p.name, value: "\(cur.tidyShort(slot.monthlyWage)) a month", rule: false)
                Text("In the post since \(GameCalendar.dateString(week: slot.since, dayOffset: 0)).").popupText(.caption)
                Text(slot.detail.tidyMoney).popupText(.caption)
            }
        }
        if slot.key == "ceo" {
            let budget: Budget = Self.budget(of: slot)
            let name: String = p.name
            LedgerSection("Budget") {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    BudgetChip(budget: budget)
                    BudgetPicker(budget: budget, name: name.split(separator: " ").first.map(String.init) ?? name) { (b: Budget) in
                        store.settle(store.act { $0.setTeamBudget(companyID: co.id, budget: b) }, "\(name): budget \(b.title.lowercased()).", same: "That budget is set already.")
                    }
                }
            }
        }
        Button("Let \(p.name.split(separator: " ").first.map(String.init) ?? "them") go…") {
            pending = PendingAction(title: "Let \(p.name) go?",
                                    message: "Cost: about one month of pay (\(cur.tidyShort(slot.monthlyWage))) plus employer costs as severance, paid now. Their work goes back to the manager (or to you).",
                                    button: "Let go", destructive: true, tone: .danger, icon: "person.fill.xmark") {
                let ok = store.act { $0.releaseTeam(companyID: co.id, key: slot.key, regionalID: slot.regionalID) } ?? false
                Haptics.warning()
                store.show(ok ? "\(p.name) has left. Severance is paid." : "They had already left.", tone: ok ? "n" : "warn")
            }
        }
        .buttonStyle(TertiaryButtonStyle(size: .compact, tint: Theme.loss))
    }

    @ViewBuilder private func vacant(_ slot: ManagerModel.TeamSlot, _ co: Company, _ cur: Currency, _ e: GameEngine) -> some View {
        let fee = ManagerModel.searchFee(currency: cur)
        LedgerSection("Vacant") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(slot.detail.tidyMoney).popupText(.subtitle)
                Button(candidates.isEmpty ? "Executive search · \(cur.tidyShort(fee))" : "Search again · \(cur.tidyShort(fee))") {
                    pending = PendingAction(title: "Pay for an executive search?",
                                            message: "Cost: \(cur.tidyShort(fee)), not refunded. Benefit: a shortlist for \(slot.title.lowercased()). Risk: none may suit.",
                                            button: "Search for \(cur.tidyShort(fee))", amount: fee, currency: cur, tone: .info, icon: "magnifyingglass") {
                        if let list = store.act({ $0.searchTeam(companyID: co.id, key: slot.key) }) ?? nil {
                            candidates = list.map { $0.id }; Haptics.tap()
                            store.show((list.isEmpty ? "The search found no one." : "\(list.count) candidates found.") + " Search paid: \(cur.tidyShort(fee)).", tone: list.isEmpty ? "warn" : "n")
                        } else { Haptics.warning(); store.show("Not enough cash for the search (\(cur.tidyShort(fee))).", tone: "warn") }
                    }
                }.buttonStyle(TertiaryButtonStyle(size: .compact))
            }
        }
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Run a search to see candidates." : "Everyone on the shortlist has taken another job. Search again.") { p in
            let request = HireRequest(post: .team(key: slot.key), companyID: co.id, personID: p.id, roleTitle: slot.title, onHired: { candidates = [] })
            CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(e, p), market: e.goingRate(for: .team(key: slot.key), companyID: co.id), request: request)
        }
    }
}
