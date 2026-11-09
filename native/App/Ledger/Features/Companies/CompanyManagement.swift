import SwiftUI
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// Who runs the company, as one management list at the top of Company > Team: the store manager, the assistant manager and the
/// management posts above the manager (managing director, department heads, regional manager), each a row with a role + scope badge.
/// A row opens its sheet, where hiring, the budget, pay and letting go happen. Original: the Manager, Assistant and Team pages
/// of the company headquarters (ui/company/people.js, headquarters.js, features/people/owner_hours_clients_assistants.js, manager_duties.js).
struct CompanyManagement: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    /// Group > entity > Management: every post is listed (open ones too) and the people above the manager (chain, region, group) show.
    var showAll: Bool = false
    @State private var sheet: Sheet?
    @State private var showVacant = false
    // Shortlists live here, not in the sheets, so a paid search survives closing a sheet.
    @State private var managerCands: [Int] = []
    @State private var assistantCands: [Int] = []
    @State private var slotCands: [String: [Int]] = [:]

    enum Sheet: Identifiable, Hashable {
        case manager, assistant, slot(String)
        var id: String { switch self { case .manager: return "m"; case .assistant: return "a"; case .slot(let s): return "s:" + s } }
    }

    /// This list includes the posts above the manager; `CompanyTeamRoster` shows them on its own only where this list is not shown (a holding).
    static func showsRoster(_ co: Company) -> Bool { co.type != "hold" && co.type != "club" }

    static func scoreWord(_ s: Int) -> String { s >= 80 ? "excellent" : s >= 65 ? "good" : s >= 50 ? "acceptable" : s >= 35 ? "weak" : "poor" }

    var body: some View {
        thinList
        .centerSheet(item: $sheet, category: .detail, tone: .info) { s in
            Group {
                switch s {
                case .manager: ManagerSheet(companyID: company.id, candidates: $managerCands)
                case .assistant: AssistantSheet(companyID: company.id, candidates: $assistantCands)
                case .slot(let id): TeamSlotSheet(companyID: company.id, slotID: id, candidates: Binding(get: { slotCands[id] ?? [] }, set: { slotCands[id] = $0 }))
                }
            }
            .environmentObject(store)
        }
    }

    // MARK: The thin list of the Team tab

    private func isOpenPost(_ n: OrgNode) -> Bool { n.row.name == nil && n.sheet != nil }

    /// The owner, the manager (always, open or not) and the filled posts; open assistant and team posts wait behind "Other posts".
    private func thinNodes(_ cur: Currency) -> (shown: [OrgNode], hidden: [OrgNode]) {
        var shown: [OrgNode] = []
        var hidden: [OrgNode] = []
        for n in orgNodes(cur) {
            if n.id.hasPrefix("b:") && !showAll { continue }
            if showAll || n.id == "you" || n.id == "m" || !isOpenPost(n) { shown.append(n) } else { hidden.append(n) }
        }
        return (shown, hidden)
    }

    @ViewBuilder private var thinList: some View {
        let cur: Currency = engine.currency(for: company)
        let nodes = thinNodes(cur)
        let rows: [OrgNode] = nodes.shown + (showVacant ? nodes.hidden : [])
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { (n: Int, node: OrgNode) -> AnyView in
                AnyView(VStack(spacing: 0) {
                    if n > 0 { PersonRowRule() }
                    thinRow(node)
                })
            }
            if !nodes.hidden.isEmpty {
                Button { Haptics.tap(); Motion.animate(Motion.quickAnimation) { showVacant.toggle() } } label: {
                    Text(showVacant ? "Hide other posts" : "Other posts (\(nodes.hidden.count) open) \u{203A}")
                        .textStyle(.caption, tint: Theme.accent).frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 44)
                }.buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder private func thinRow(_ node: OrgNode) -> some View {
        let r: ManagementRow = node.row
        let open: Bool = r.name == nil
        let tinted: Bool = r.lineTint != Theme.ivoryFaint
        if node.isOwner {
            HStack(spacing: 8) {
                ThinPersonRow(name: r.name, title: "Owner", note: (node.works == true) ? "works here" : "", chevron: false, roleKey: "owner")
                if let works = node.works, let toggle = node.toggleWorks { ownerToggle(works, toggle) }
            }
        } else if let target = node.sheet {
            Button { Haptics.tap(); sheet = target } label: {
                ThinPersonRow(name: r.name, title: r.role, note: open ? "" : (tinted ? r.line : ""), noteTint: r.lineTint, wage: r.wage, cue: open ? "Appoint" : nil, chevron: !open, roleKey: r.role, face: r.face)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("mgmt-row-" + node.id)
        } else {
            ThinPersonRow(name: r.name, title: r.role, chevron: false, roleKey: r.role, face: r.face)
        }
    }

    private func ownerToggle(_ works: Bool, _ toggle: @escaping () -> Void) -> some View {
        Button { toggle() } label: {
            HStack(spacing: Theme.Space.xs) {
                LedgerGlyph(glyph: works ? Glyph.check : Glyph.close, size: Theme.Icon.small, tint: works ? Theme.gain : Theme.inkFaint)
                Text(works ? "Works here" : "Not here").textStyle(.caption, tint: works ? Theme.ink : Theme.inkSoft, weight: .medium)
            }
            .padding(.horizontal, Theme.Space.s).frame(minHeight: 44)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(works ? "You work here. Tap to step out." : "You do not work here. Tap to step in.")
    }

    // MARK: The strip, top (the owner) to bottom (the posts under the manager)

    /// One step of the strip: who stands there, what they may decide, and the sheet it opens (none for the owner and for posts above the company).
    fileprivate struct OrgNode: Identifiable {
        var id: String
        var glyph: String
        var row: ManagementRow
        var level: Int?
        var sheet: Sheet?
        var isOwner = false
        /// The owner's card only: whether the player works here (nil where a manager runs the place), and the switch.
        var works: Bool? = nil
        var toggleWorks: (() -> Void)? = nil
    }

    /// Who stands above this company's own management (chain, region, group), nearest the manager first.
    private var chainAbove: [ManagerModel.Boss] {
        engine.decisionChain(companyID: company.id).filter { $0.kind != "mgr" && $0.kind != "mdir" || ($0.kind == "mdir" && company.holdingID != 0) }
    }

    private static func scope(_ kind: String) -> String {
        switch kind {
        case "region": return "region"
        case "chainmgr", "ceo56": return "chain"
        default: return "group"
        }
    }

    private func orgNodes(_ cur: Currency) -> [OrgNode] {
        var out: [OrgNode] = []
        let youLine: String = OwnerHours.works(company) ? "Runs it day to day." : "Final say on anything above the budget you set."
        let canWork: Bool = company.managerID == nil && company.type != "hold"
        let working: Bool = OwnerHours.works(company)
        let cid: Int = company.id
        let toggle: () -> Void = {
            Haptics.tap()
            store.settle(store.act { $0.setWorksHere(companyID: cid, works: !working) }, working ? "You no longer work here." : "You work here again.")
        }
        out.append(OrgNode(id: "you", glyph: Glyph.person, row: ManagementRow(name: engine.state.player.name, role: "Owner", scope: "company", line: youLine), level: nil, sheet: nil, isOwner: true,
                           works: canWork ? working : nil, toggleWorks: canWork ? toggle : nil))
        for b in chainAbove.reversed() {
            let title: String = GameEngine.bossTitle(b.kind, trade: nil)
            let budget: Budget = Budget(rawValue: min(2, max(0, b.level))) ?? .tight
            let row = ManagementRow(name: b.name, role: title, scope: Self.scope(b.kind), line: "Budget \u{00B7} " + budget.title, wage: nil,
                                    face: engine.state.people[b.personID]?.faceKey)
            out.append(OrgNode(id: "b:" + b.kind + ":\(b.personID)", glyph: Glyph.group, row: row, level: b.level, sheet: nil))
        }
        let mgrLevel: Int? = company.managerID != nil ? ManagerModel.budget(of: company).rawValue : nil
        out.append(OrgNode(id: "m", glyph: Glyph.person, row: managerRow(cur), level: mgrLevel, sheet: .manager))
        out.append(OrgNode(id: "a", glyph: Glyph.people, row: assistantRow(cur), level: nil, sheet: .assistant))
        for slot in engine.teamSlots(companyID: company.id) {
            let row: ManagementRow = TeamSlotSheet.row(slot, company: company, engine: engine, cur: cur)
            out.append(OrgNode(id: "s:" + slot.id, glyph: Glyph.team, row: row, level: slot.personID != nil ? slot.level : nil, sheet: .slot(slot.id)))
        }
        return out
    }

    private func managerRow(_ cur: Currency) -> ManagementRow {
        let title = engine.tradeInfo(companyID: company.id).map { ManagerModel.title($0) } ?? "Manager"
        guard let mid = company.managerID, let m = engine.state.people[mid] else {
            return ManagementRow(name: nil, role: title, scope: "store",
                                 line: OwnerHours.works(company) ? "You run it yourself. Hire one to step back." : "No one runs it day to day. Hire one.",
                                 lineTint: OwnerHours.works(company) ? Theme.ivoryFaint : Theme.caution, wage: nil)
        }
        let notice = company.value("mgrNotice")
        if !notice.isNull {
            return ManagementRow(name: m.name, role: title, scope: "store", line: "Leaves on \(GameCalendar.dateString(week: notice["w"].int, dayOffset: 0)). Find a successor.",
                                 lineTint: Theme.loss, wage: cur.tidyShort(company.managerMonthlyWage), face: m.faceKey)
        }
        var line = ""
        if let card = engine.managerScorecard(companyID: company.id) { line += "scorecard: \(Self.scoreWord(card.score))" }
        line += (line.isEmpty ? "" : " · ") + "budget \(ManagerModel.budget(of: company).title.lowercased())"
        if company.managerProfitBonus > 0 { line += " · \(Int(saturating: (company.managerProfitBonus * 100).rounded()))% profit share" }
        let weak = (engine.managerScorecard(companyID: company.id)?.score ?? 100) < 35
        return ManagementRow(name: m.name, role: title, scope: "store", line: line, lineTint: weak ? Theme.caution : Theme.ivoryFaint, wage: cur.tidyShort(company.managerMonthlyWage), face: m.faceKey)
    }

    private func assistantRow(_ cur: Currency) -> ManagementRow {
        let a = company.value("asst")
        guard a["npc"].int != 0, let n = engine.state.people[a["npc"].int] else {
            return ManagementRow(name: nil, role: "Assistant manager", scope: "store",
                                 line: "Optional: takes up to two jobs off \(company.managerID == nil ? "your" : "the manager's") plate.", wage: nil)
        }
        let jobs = a["duties"].array.compactMap { d in ManagerModel.assistantDuties.first { $0.key == d.string }?.title.lowercased() }
        return ManagementRow(name: n.name, role: "Assistant manager", scope: "store",
                             line: jobs.isEmpty ? "No jobs picked yet: pick up to two." : "Looks after " + jobs.joined(separator: " and "),
                             lineTint: jobs.isEmpty ? Theme.caution : Theme.ivoryFaint, wage: cur.tidyShort(a["wage"].double), face: n.faceKey)
    }
}

/// What a manager candidate says about themselves, in words, the paid trial week and the reference check (the engine's interview model).
/// No skill figure or band is shown: a trial week gives observations from a simulated week, a reference check says whether the CV holds.
struct ManagerCandidateChecks: View {
    @EnvironmentObject var store: GameStore
    var person: Person
    var companyID: Int
    var currency: Currency
    @State private var trialSeen: [String] = []
    @State private var said: [String: Double] = [:]

    /// How a checked skill compares with what the CV claimed, in words.
    private func comparison(_ key: String) -> String {
        let claimed: Double = person.value("q")[key].double
        let real: Double = person.value("stats")[key].double
        if real < claimed - 12 { return "weaker than the CV says" }
        if real > claimed + 12 { return "stronger than the CV says" }
        return "as the CV says"
    }

    /// What the candidate said when asked about a skill (this session's answer, else the one on record); nil when not asked yet.
    private func answer(_ key: String) -> Double? {
        if let v = said[key] { return v }
        let recorded = person.value("q")[key]
        return recorded.isNull ? nil : recorded.double
    }

    /// Three questions per candidate.
    private var questionsLeft: Int { max(0, 3 - ManagerModel.skillKeys.filter { answer($0.key) != nil }.count) }

    private func words(_ v: Double) -> String { v >= 80 ? "very strong" : v >= 65 ? "strong" : v >= 50 ? "solid" : v >= 35 ? "modest" : "weak" }

    private func ask(_ key: String, _ label: String) {
        let r: Double? = store.act { $0.interviewManager(personID: person.id, skill: key) } ?? nil
        if let r { said[key] = r; Haptics.tap() } else { Haptics.warning(); store.show("No questions left for this candidate.", tone: "warn") }
    }

    private var seenLines: [String] {
        let kept: [String] = person.value("trialObs").array.map { $0.string }
        return trialSeen.isEmpty ? kept : trialSeen
    }

    var body: some View {
        let checked = person.flag("ref")
        let fee = currency.scaledPrice(2500)
        VStack(alignment: .leading, spacing: 4) {
            if !person.str("resume").isEmpty { Text(person.str("resume")).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(ManagerModel.skillKeys.enumerated()), id: \.offset) { _, k in
                if let v = answer(k.key) {
                    Text("\(k.label): " + (checked ? comparison(k.key) : "says they are \(words(v))")).textStyle(.caption, tint: Theme.ink)
                }
            }
            ForEach(seenLines, id: \.self) { line in
                Text(line).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            WrapRow {
                ForEach(Array(ManagerModel.skillKeys.enumerated()), id: \.offset) { _, k in
                    if answer(k.key) == nil && questionsLeft > 0 {
                        Button("Ask: \(k.label)") { ask(k.key, k.label) }.buttonStyle(TertiaryButtonStyle(size: .compact))
                    }
                }
                if seenLines.isEmpty {
                    Button("Trial week") {
                        let r: [WorkLog.Observation]? = store.act { $0.startTrialWeek(personID: person.id, companyID: companyID) } ?? nil
                        if let r { trialSeen = r.map { $0.text }; Haptics.success(); store.show("The trial week is done: see how their work went.", tone: "n") }
                        else { Haptics.warning(); store.show("Could not arrange a trial week: it was done already, or the company lacks the cash for a week's wage.", tone: "warn") }
                    }.buttonStyle(TertiaryButtonStyle(size: .compact))
                }
                if !checked {
                    Button("References \u{00B7} \(currency.tidyShort(fee))") {
                        let ok = store.act { $0.checkManagerReferences(personID: person.id, companyID: companyID) } ?? false
                        if !ok { Haptics.warning() }
                        store.show(ok ? "References are in: you can see whether the CV holds. Paid \(currency.tidyShort(fee))." : "Not enough cash for the reference check (\(currency.tidyShort(fee))).", tone: ok ? "n" : "warn")
                    }.buttonStyle(TertiaryButtonStyle(size: .compact))
                } else {
                    Text("References checked").textStyle(.caption, tint: Theme.gain)
                }
            }
        }
    }
}

// MARK: - The assistant manager

/// The assistant manager's sheet: their two jobs and letting them go; or the job ad and the shortlist.
struct AssistantSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @Binding var candidates: [Int]
    @State private var pending: PendingAction?

    var body: some View {
        PeopleSheet(title: "Assistant manager") {
            if let e = store.engine, let co = e.state.company(companyID) {
                let cur = e.currency(for: co)
                let a = co.value("asst")
                if a["npc"].int != 0, let n = e.state.people[a["npc"].int] { manage(co, a, n, cur) } else { hire(e, co, cur) }
            } else {
                Text("This company no longer exists.").popupText(.body)
            }
        }
        .confirmAction($pending)
    }

    @ViewBuilder private func manage(_ co: Company, _ a: JSONValue, _ n: Person, _ cur: Currency) -> some View {
        let asstNote: String = "\(co.name) · works a full week and takes jobs off \(co.managerID == nil ? "your" : "the manager's") plate. They advise; you decide."
        PersonCard(name: n.name, role: "Assistant manager", scope: "store", note: asstNote, wage: cur.tidyShort(a["wage"].double), chevron: false, roleKey: "assistant-manager", face: n.faceKey)
        let picked: Int = a["duties"].array.count
        TeamGroup(title: "Jobs", trailing: {
            HStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule().fill(i < picked ? Theme.gold : Theme.hairline).frame(width: 18, height: 4)
                }
                Text("\(picked) of 2").popupText(.caption).padding(.leading, 4)
            }
        }) {
            ForEach(Array(ManagerModel.assistantDuties.enumerated()), id: \.offset) { _, d in
                let on: Bool = a["duties"].array.contains { $0.string == d.key }
                jobCard(co, n, d, on: on)
            }
            Text("Two jobs at most. Pick one, or swap by unticking another first.").popupText(.caption)
        }
        letGo(co, a, n, cur)
    }

    /// One of the assistant's possible jobs as a tappable card: the lit ring means they look after it.
    private func jobCard(_ co: Company, _ n: Person, _ d: (key: String, title: String, text: String), on: Bool) -> some View {
        Button {
            let ok = store.act { $0.toggleAssistantDuty(companyID: co.id, duty: d.key) } ?? false
            store.show(ok ? (on ? "\(n.name) no longer looks after \(d.title.lowercased())." : "\(n.name) now looks after \(d.title.lowercased()).") : "Two jobs at most. Untick one first.", tone: ok ? "n" : "warn")
            Haptics.choose()
        } label: {
            Card(padding: 12, radius: Theme.Radius.card, fill: on ? Theme.goldSelected : Theme.surface, stroke: on ? Theme.gold : Theme.border) {
                HStack(spacing: 12) {
                    IconCircle(glyph: on ? Glyph.check : Glyph.ring, size: 36, tint: on ? Theme.gold : Theme.ivoryFaint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.title.tidyMoney).popupText(.rowValue)
                        Text(d.text.tidyMoney).popupText(.caption)
                    }
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func letGo(_ co: Company, _ a: JSONValue, _ n: Person, _ cur: Currency) -> some View {
        let first: String = n.name.split(separator: " ").first.map(String.init) ?? "them"
        return Card(padding: 14, radius: Theme.Radius.card, stroke: Theme.loss.opacity(0.4)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconCircle(glyph: Glyph.exit, size: 34, tint: Theme.loss)
                    Text("Let \(first) go").popupText(.title)
                }
                Text("About one month of pay (\(cur.tidyShort(a["wage"].double))) as notice. Their jobs go back to \(co.managerID == nil ? "you" : "the manager").")
                    .popupText(.caption)
                QuietButton(title: "Let \(first) go…", tint: Theme.loss) {
                    pending = PendingAction(title: "Let \(n.name) go?", message: "About one month of pay (\(cur.tidyShort(a["wage"].double))) as notice. Their jobs go back to \(co.managerID == nil ? "you" : "the manager").",
                                            button: "Let go", destructive: true, tone: .danger, icon: "person.fill.xmark") {
                        store.act { $0.dismissAssistant(companyID: co.id) }
                        let gone = store.engine?.state.company(co.id)?.value("asst")["npc"].int ?? 0 == 0
                        store.show(gone ? "\(n.name) has left." : "They are still here.", tone: gone ? "n" : "warn"); Haptics.warning()
                    }
                }
            }
        }
    }

    @ViewBuilder private func hire(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let fee = cur.scaledPrice(2500)
        VStack(alignment: .leading, spacing: 4) {
            Text("Hire an assistant manager").popupText(.figure)
            RoleScopeBadge(role: co.name, scope: "store")
        }
        Text("Works alongside the team and takes up to two jobs off \(co.managerID == nil ? "your" : "the manager's") plate: complaints, insurance, equipment. Paid more than a worker, less than a manager. They advise; you decide.")
            .popupText(.caption)
        Button(candidates.isEmpty ? "Job ad · \(cur.tidyShort(fee))" : "New job ad · \(cur.tidyShort(fee))") {
            pending = PendingAction(title: "Place a job ad?", message: "Cost: \(cur.tidyShort(fee)). Benefit: a shortlist of applicants. Risk: none may suit.", button: "Pay \(cur.tidyShort(fee))", amount: fee, currency: cur, tone: .info, icon: "megaphone") {
                if let list = store.act({ $0.searchAssistants(companyID: co.id) }) ?? nil { candidates = list.map { $0.id }; Haptics.tap(); store.show("\(list.count) applicants. Job ad paid: \(cur.tidyShort(fee)).", tone: "n") }
                else { Haptics.warning(); store.show("Not enough cash for the job ad (\(cur.tidyShort(fee))).", tone: "warn") }
            }
        }.buttonStyle(TertiaryButtonStyle(size: .compact))
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        let auth: AppointmentAuthority = e.appointmentAuthority(companyID: co.id, role: "assistant manager")
        if let above = auth.needsConfirmationFrom {
            Text(above == .ceo ? "Needs confirmation from the CEO" : "Needs your confirmation")
                .popupText(.effect)
        }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Place a job ad to see applicants." : "Everyone has taken another job. Place a new ad.") { p in
            if let above = auth.needsConfirmationFrom {
                proposeRow(e, co, cur, p, above)
            } else {
                let request = HireRequest(post: .assistant, companyID: co.id, personID: p.id, roleTitle: "Assistant manager", onHired: { candidates = [] })
                CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(e, p), market: e.goingRate(for: .assistant, companyID: co.id), request: request, roleKey: "assistant-manager")
            }
        }
    }

    /// A candidate when the hire needs the level above: Appoint sends a proposal there (an inbox decision) instead of hiring.
    private func proposeRow(_ e: GameEngine, _ co: Company, _ cur: Currency, _ p: Person, _ above: Delegation.Rank) -> some View {
        let wage: Double = e.goingRate(for: .assistant, companyID: co.id)
        let pid: Int = p.id
        let cid: Int = co.id
        let who: String = above == .ceo ? "the CEO" : "you"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ThumbnailView(kind: .person, key: "assistant-manager", size: 36, initials: p.name, face: p.faceKey)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).popupText(.rowValue)
                    Text(CandidateClaims.line(e, p)).popupText(.caption)
                }
                Spacer(minLength: 8)
                Text(cur.tidyShort(wage)).popupText(.rowValue)
            }
            Button("Appoint (proposal to \(who))") {
                let ok: Bool = store.act { $0.proposeAssistantManager(companyID: cid, personID: pid, monthlyWage: wage) } ?? false
                if ok { Haptics.tap(); candidates = []; store.show("Proposal sent to \(who)", tone: "good") }
                else { Haptics.warning(); store.show("A proposal for this post is already open, or the person is not free.", tone: "warn") }
            }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }
    }
}
