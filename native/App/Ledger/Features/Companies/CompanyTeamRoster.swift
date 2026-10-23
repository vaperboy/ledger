import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The management posts above the manager (managing director, department heads, regional manager).
/// In Company > Team these posts are rows of the one management list in `CompanyManagement`, so this standalone list only shows
/// where that list does not (a holding, which has no store manager). Each row opens `TeamSlotSheet` for hire, authority and release.
/// Chain and group posts are the same kind of rows seen from the chain and from Group (see ExecutivePosts).
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
            LedgerSection(title: "Management", trailing: {
                Text("\(slots.filter { $0.personID != nil }.count) of \(slots.count) filled").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { n, slot in
                        if n > 0 { Hairline() }
                        Button { Haptics.tap(); openSlot = SlotRef(id: slot.id) } label: { TeamSlotSheet.row(slot, company: company, engine: engine, cur: cur) }.buttonStyle(.plain)
                    }
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
        return ManagementRow(name: person?.name, role: slot.title, scope: scope(slot, company: company), line: line, wage: person == nil ? nil : cur.tidyShort(slot.monthlyWage))
    }

    var body: some View {
        PeopleSheet(title: "Management post") {
            if let e = store.engine, let co = e.state.company(companyID), let slot = e.teamSlots(companyID: companyID).first(where: { $0.id == slotID }) {
                let cur = e.currency(for: co)
                VStack(alignment: .leading, spacing: 4) {
                    Text(slot.title).font(.serifTitle(22)).foregroundStyle(Theme.ivory)
                    RoleScopeBadge(role: co.name, scope: Self.scope(slot, company: co))
                }
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
                Text(slot.detail).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        if slot.key == "ceo" {
            LedgerSection("Decides") {
                VStack(alignment: .leading, spacing: 10) {
                    AuthorityLevelPicker(level: slot.level) { l in
                        store.act { $0.setTeamAuthority(companyID: co.id, level: l) }
                        store.show("\(p.name) now \(GameEngine.authorityText(level: l)).", tone: "n")
                    }
                    if slot.level == 1 {
                        HStack {
                            Text("Spends up to").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                            Spacer()
                            Menu {
                                ForEach([25000.0, 50000, 100000, 250000, 500000], id: \.self) { v in
                                    Button(cur.tidyShort(cur.scaledPrice(v))) {
                                        store.act { $0.setTeamAuthority(companyID: co.id, buy: cur.scaledPrice(v)) }
                                        store.show("Above \(cur.tidyShort(cur.scaledPrice(v))) it comes to you.", tone: "n")
                                    }
                                }
                            } label: { Text(cur.tidyShort(slot.buy)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.gold) }
                        }
                    }
                }
            }
        }
        Button("Let \(p.name.split(separator: " ").first.map(String.init) ?? "them") go") {
            pending = PendingAction(title: "Let \(p.name) go?",
                                    message: "Cost: about one month of pay plus employer costs as severance, paid now. Their work goes back to the manager (or to you).",
                                    button: "Let go", destructive: true) {
                let ok = store.act { $0.releaseTeam(companyID: co.id, key: slot.key, regionalID: slot.regionalID) } ?? false
                if ok { Haptics.warning() }
                store.show(ok ? "\(p.name) has left. Severance is paid." : "They had already left.", tone: ok ? "n" : "warn")
            }
        }
        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.loss).buttonStyle(.plain)
    }

    @ViewBuilder private func vacant(_ slot: ManagerModel.TeamSlot, _ co: Company, _ cur: Currency, _ e: GameEngine) -> some View {
        let fee = cur.scaledPrice(15000)
        LedgerSection("Vacant") {
            VStack(alignment: .leading, spacing: 10) {
                Text(slot.detail).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                Button(candidates.isEmpty ? "Executive search · \(cur.tidyShort(fee))" : "Search again · \(cur.tidyShort(fee))") {
                    pending = PendingAction(title: "Pay for an executive search?",
                                            message: "Cost: \(cur.tidyShort(fee)), not refunded. Benefit: a shortlist for \(slot.title.lowercased()). Risk: none may suit.",
                                            button: "Search for \(cur.tidyShort(fee))", amount: fee, currency: cur) {
                        if let list = store.act({ $0.searchTeam(companyID: co.id, key: slot.key) }) ?? nil {
                            candidates = list.map { $0.id }; Haptics.tap()
                            store.show((list.isEmpty ? "The search found no one." : "\(list.count) candidates found.") + " Search paid: \(cur.tidyShort(fee)).", tone: list.isEmpty ? "warn" : "n")
                        } else { store.show("Not enough cash for the search.", tone: "warn") }
                    }
                }.buttonStyle(QuietButtonStyle())
            }
        }
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Run a search to see candidates." : "Everyone on the shortlist has taken another job. Search again.") { p in
            CandidateHireRow(person: p, currency: cur) { wage in
                let r = store.act { $0.hireTeam(companyID: co.id, key: slot.key, personID: p.id, monthlyWage: wage) }
                let fb = HireFeedback.from(r, name: p.name, role: slot.title)
                if fb.isHired { candidates = []; store.show(fb.text, tone: "good") }
                return fb
            }
        }
    }
}
