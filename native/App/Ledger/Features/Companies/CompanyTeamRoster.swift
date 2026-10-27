import SwiftUI
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// The management posts above the manager (managing director, department heads, regional manager).
/// In Company > Team these posts are rows of the one management list in `CompanyManagement`, so this standalone list only shows
/// where that list does not (a holding, which has no store manager). Each row opens `TeamSlotSheet` for hire, authority and release.
/// Chain and group posts are the same kind of rows seen from the chain and from Group (see ExecutivePosts).
/// What a candidate says about themselves on the CV: age, what they claim to have done (never the real figure), and what they say they can do.
enum CandidateClaims {
    static func line(_ engine: GameEngine, _ p: Person, extra: String = "") -> String {
        var parts = ["Age \(p.age)"]
        if let y = engine.claimedExperienceYears(personID: p.id) { let n = Int(y.rounded()); parts.append("Claims \(n) \(n == 1 ? "year" : "years")") }
        parts.append("says \(StaffProfile.band(p.claimedSkill).lowercased())")
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: " · ")
    }
}


// MARK: Person cards (new look)

/// The initials of a name in a round outlined holder: the face of every person card. A vacant post shows the plus icon instead.
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
            IconCircle(glyph: Glyph.hire, size: size, tint: Theme.ivoryMuted)
        } else {
            Text(letters)
                .font(.serifTitle(size * 0.38)).foregroundStyle(Theme.gold)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}

/// A small outlined badge: the role or the scope (store, company, chain, region, group) of a person.
struct TeamBadge: View {
    var text: String
    var tint: Color = Theme.ivoryMuted

    var body: some View {
        Text(text.tidyText)
            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(tint).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
    }
}

/// One person of this company as a bordered card: initials circle, name, role and scope badges, a note, the monthly wage and a chevron.
/// Used for the management posts and for the staff, so a person looks the same everywhere. A vacant post says "Vacant".
struct PersonCard: View {
    var name: String?
    var role: String
    var scope: String
    var note: String = ""
    var noteTint: Color = Theme.ivoryFaint
    var wage: String? = nil
    var chevron = true
    /// The engine role id, for the picture; the displayed role is used when it is not given.
    var roleKey: String? = nil
    /// Portrait traits of an employee (see FaceSheet) and the company id they work for; the initials show when nil or the sheet is missing.
    var face: FaceTraits? = nil
    var faceGroup: String = ""

    /// The card of a management row, so the management lists keep their data and take the new look.
    init(row: ManagementRow, chevron: Bool = true) {
        self.name = row.name; self.role = row.role; self.scope = row.scope
        self.note = row.line; self.noteTint = row.lineTint; self.wage = row.wage; self.chevron = chevron
        self.face = row.face; self.faceGroup = row.faceGroup
    }

    init(name: String?, role: String, scope: String, note: String = "", noteTint: Color = Theme.ivoryFaint, wage: String? = nil, chevron: Bool = true, roleKey: String? = nil, face: FaceTraits? = nil, faceGroup: String = "") {
        self.name = name; self.role = role; self.scope = scope
        self.note = note; self.noteTint = noteTint; self.wage = wage; self.chevron = chevron; self.roleKey = roleKey
        self.face = face; self.faceGroup = faceGroup
    }

    /// The picture of the role while the post is filled; the initials circle until art exists; the plus icon for a vacant post.
    @ViewBuilder private var face: some View {
        if name == nil {
            TeamInitials(name: nil)
        } else {
            ThumbnailView(kind: .person, key: roleKey ?? role, size: 42, initials: name, face: face, faceGroup: faceGroup)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            face
            VStack(alignment: .leading, spacing: 4) {
                Text(name ?? "Vacant").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(name == nil ? Theme.ivoryMuted : Theme.ivory).lineLimit(1)
                HStack(spacing: 5) {
                    TeamBadge(text: role, tint: Theme.gold)
                    TeamBadge(text: scope)
                }
                if !note.isEmpty {
                    Text(note.tidyText).font(.system(size: 12)).foregroundStyle(noteTint)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            if let wage {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(wage).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text("a month").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            if chevron { GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A titled group of cards: a small champagne label with a note at the right, then the cards with a gap, no rule.
struct TeamGroup<Content: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).capsLabel()
                Spacer(minLength: 8)
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

/// A titled group whose content sits in one bordered card (targets, perks, contracts): the new-look `LedgerSection`.
struct TeamCardGroup<Content: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        TeamGroup(title: title, trailing: trailing) {
            Card(padding: 14, radius: Theme.Radius.row) { content() }
        }
    }
}
extension TeamCardGroup where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// A small outlined action inside a card, in the tint of what it does (champagne, red for letting go). Never filled.
struct TeamAction: View {
    var title: String
    var tint: Color = Theme.gold
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(tint).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(tint.opacity(0.7), lineWidth: 1))
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Text(open > 0 ? "\(open) vacant" : "all filled").font(.system(size: 11.5)).foregroundStyle(open > 0 ? Theme.caution : Theme.ivoryFaint)
            }) {
                ForEach(slots) { slot in
                    let row: ManagementRow = TeamSlotSheet.row(slot, company: company, engine: engine, cur: cur)
                    Button { Haptics.tap(); openSlot = SlotRef(id: slot.id) } label: { PersonCard(row: row) }.buttonStyle(.plain)
                }
            }
            .sheet(item: $openSlot) { ref in
                TeamSlotSheet(companyID: company.id, slotID: ref.id, candidates: Binding(get: { candidates[ref.id] ?? [] }, set: { candidates[ref.id] = $0 }))
                    .environmentObject(store)
            }
        }
    }
}

/// One management post of a company: who holds it, what they may decide, pay and release; or, when vacant, the search and the shortlist.
struct TeamSlotSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var slotID: String
    @Binding var candidates: [Int]
    @State private var pending: PendingAction?

    static func scope(_ slot: ManagerModel.TeamSlot, company: Company) -> String {
        switch slot.key { case "ceo": return company.type == "hold" ? "group" : "company"; case "reg": return "region"; default: return "company" }
    }

    /// The row used in the management list (here and in CompanyManagement).
    static func row(_ slot: ManagerModel.TeamSlot, company: Company, engine: GameEngine, cur: Currency) -> ManagementRow {
        let person = slot.personID.flatMap { engine.state.people[$0] }
        let line: String
        if person == nil { line = slot.detail }
        else if slot.key == "ceo" { line = "\(AuthorityWords.label(slot.level))\(slot.level == 1 ? " · spends up to \(cur.tidyShort(slot.buy))" : "")" }
        else { line = "Since \(GameCalendar.dateString(week: slot.since, dayOffset: 0))" }
        return ManagementRow(name: person?.name, role: slot.title, scope: scope(slot, company: company), line: line, wage: person == nil ? nil : cur.tidyShort(slot.monthlyWage),
                             face: person.map { FaceTraits.of($0, countryCode: company.countryCode) }, faceGroup: "\(company.id)")
    }

    var body: some View {
        PeopleSheet(title: "Management post") {
            if let e = store.engine, let co = e.state.company(companyID), let slot = e.teamSlots(companyID: companyID).first(where: { $0.id == slotID }) {
                let cur = e.currency(for: co)
                let head: ManagementRow = Self.row(slot, company: co, engine: e, cur: cur)
                PersonCard(row: head, chevron: false)
                if let pid = slot.personID, let p = e.state.people[pid] { filled(slot, p, co, cur) } else { vacant(slot, co, cur, e) }
            } else {
                Text("This post no longer exists.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .confirmAction($pending)
    }

    @ViewBuilder private func filled(_ slot: ManagerModel.TeamSlot, _ p: Person, _ co: Company, _ cur: Currency) -> some View {
        LedgerSection("Who") {
            VStack(alignment: .leading, spacing: 6) {
                FlatRow(label: p.name, value: "\(cur.tidyShort(slot.monthlyWage)) a month", rule: false)
                Text("In the post since \(GameCalendar.dateString(week: slot.since, dayOffset: 0)).").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                Text(slot.detail.tidyMoney).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        if slot.key == "ceo" {
            LedgerSection("Decides") {
                VStack(alignment: .leading, spacing: 10) {
                    AuthorityLevelPicker(level: slot.level) { l in
                        store.settle(store.act { $0.setTeamAuthority(companyID: co.id, level: l) }, "\(p.name) now \(GameEngine.authorityText(level: l)).", same: "\(p.name) already works that way.")
                    }
                    if slot.level == 1 {
                        HStack {
                            Text("Spends up to").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                            Spacer()
                            Menu {
                                ForEach([25000.0, 50000, 100000, 250000, 500000], id: \.self) { v in
                                    Button(cur.tidyShort(cur.scaledPrice(v))) {
                                        store.settle(store.act { $0.setTeamAuthority(companyID: co.id, buy: cur.scaledPrice(v)) }, "Above \(cur.tidyShort(cur.scaledPrice(v))) it comes to you.", same: "That limit is already set.")
                                    }
                                }
                            } label: { Text(cur.tidyShort(slot.buy)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.gold) }
                        }
                    }
                }
            }
        }
        Button("Let \(p.name.split(separator: " ").first.map(String.init) ?? "them") go…") {
            pending = PendingAction(title: "Let \(p.name) go?",
                                    message: "Cost: about one month of pay (\(cur.tidyShort(slot.monthlyWage))) plus employer costs as severance, paid now. Their work goes back to the manager (or to you).",
                                    button: "Let go", destructive: true) {
                let ok = store.act { $0.releaseTeam(companyID: co.id, key: slot.key, regionalID: slot.regionalID) } ?? false
                if ok { Haptics.warning() }
                if !ok { Haptics.warning() }
                store.show(ok ? "\(p.name) has left. Severance is paid." : "They had already left.", tone: ok ? "n" : "warn")
            }
        }
        .buttonStyle(QuietButtonStyle(tint: Theme.loss))
    }

    @ViewBuilder private func vacant(_ slot: ManagerModel.TeamSlot, _ co: Company, _ cur: Currency, _ e: GameEngine) -> some View {
        let fee = ManagerModel.searchFee(currency: cur)
        LedgerSection("Vacant") {
            VStack(alignment: .leading, spacing: 10) {
                Text(slot.detail.tidyMoney).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                Button(candidates.isEmpty ? "Executive search · \(cur.tidyShort(fee))" : "Search again · \(cur.tidyShort(fee))") {
                    pending = PendingAction(title: "Pay for an executive search?",
                                            message: "Cost: \(cur.tidyShort(fee)), not refunded. Benefit: a shortlist for \(slot.title.lowercased()). Risk: none may suit.",
                                            button: "Search for \(cur.tidyShort(fee))", amount: fee, currency: cur) {
                        if let list = store.act({ $0.searchTeam(companyID: co.id, key: slot.key) }) ?? nil {
                            candidates = list.map { $0.id }; Haptics.tap()
                            store.show((list.isEmpty ? "The search found no one." : "\(list.count) candidates found.") + " Search paid: \(cur.tidyShort(fee)).", tone: list.isEmpty ? "warn" : "n")
                        } else { Haptics.warning(); store.show("Not enough cash for the search (\(cur.tidyShort(fee))).", tone: "warn") }
                    }
                }.buttonStyle(QuietButtonStyle())
            }
        }
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Run a search to see candidates." : "Everyone on the shortlist has taken another job. Search again.") { p in
            CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(e, p), market: e.goingRate(for: .team(key: slot.key), companyID: co.id), factors: [0.9, 1.0, 1.15, 1.3]) { wage in
                let r = store.act { $0.hireTeam(companyID: co.id, key: slot.key, personID: p.id, monthlyWage: wage) }
                let fb = HireFeedback.from(r, name: p.name, role: slot.title)
                if fb.isHired { candidates = []; store.show(fb.text, tone: "good") }
                return fb
            }
        }
    }
}
