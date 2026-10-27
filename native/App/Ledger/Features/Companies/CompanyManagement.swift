import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Who runs the company, as one management list at the top of Company > Team: the store manager, the assistant manager and the
/// management posts above the manager (managing director, department heads, regional manager), each a row with a role + scope badge.
/// A row opens its sheet, where hiring, authority, duties, pay and letting go happen. Original: the Manager, Assistant and Team pages
/// of the company headquarters (ui/company/people.js, headquarters.js, features/people/owner_hours_clients_assistants.js, manager_duties.js).
struct CompanyManagement: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var sheet: Sheet?
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
        let cur = engine.currency(for: company)
        let slots = engine.teamSlots(companyID: company.id)
        let hasAssistant = company.value("asst")["npc"].int != 0
        let filled = (company.managerID != nil ? 1 : 0) + (hasAssistant ? 1 : 0) + slots.filter { $0.personID != nil }.count
        let list: [OrgNode] = orgNodes(cur)
        TeamGroup(title: "Chain of command", trailing: {
            Text("\(filled) of \(2 + slots.count) posts filled").font(.system(size: 11.5)).foregroundStyle(filled < 2 + slots.count ? Theme.caution : Theme.ivoryFaint)
        }) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, node in
                    OrgStripRow(node: node, last: n == list.count - 1, open: opener(node))
                }
            }
            aboveNote
        }
        .sheet(item: $sheet) { s in
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

    // MARK: The strip, top (the owner) to bottom (the posts under the manager)

    /// One step of the strip: who stands there, what they may decide, and the sheet it opens (none for the owner and for posts above the company).
    fileprivate struct OrgNode: Identifiable {
        var id: String
        var glyph: String
        var row: ManagementRow
        var level: Int?
        var sheet: Sheet?
        var isOwner = false
    }

    private func opener(_ node: OrgNode) -> (() -> Void)? {
        guard let target = node.sheet else { return nil }
        return { sheet = target }
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
        let youLine: String = company.ownerHours > 0 ? "Runs it day to day." : "Final say on anything above the limits you set."
        out.append(OrgNode(id: "you", glyph: Glyph.person, row: ManagementRow(name: "You", role: "Owner", scope: "company", line: youLine), level: nil, sheet: nil, isOwner: true))
        for b in chainAbove.reversed() {
            let title: String = GameEngine.bossTitle(b.kind, trade: nil)
            let said: String = GameEngine.authorityText(level: b.level)
            let row = ManagementRow(name: b.name, role: title, scope: Self.scope(b.kind), line: String(said.prefix(1)).uppercased() + String(said.dropFirst()) + ".", wage: nil)
            out.append(OrgNode(id: "b:" + b.kind + ":\(b.personID)", glyph: Glyph.group, row: row, level: b.level, sheet: nil))
        }
        let mgrLevel: Int? = company.managerID != nil ? Int(company.value("auth")["lvl"].double) : nil
        out.append(OrgNode(id: "m", glyph: Glyph.person, row: managerRow(cur), level: mgrLevel, sheet: .manager))
        out.append(OrgNode(id: "a", glyph: Glyph.people, row: assistantRow(cur), level: nil, sheet: .assistant))
        for slot in engine.teamSlots(companyID: company.id) {
            let row: ManagementRow = TeamSlotSheet.row(slot, company: company, engine: engine, cur: cur)
            out.append(OrgNode(id: "s:" + slot.id, glyph: Glyph.team, row: row, level: slot.personID != nil ? slot.level : nil, sheet: .slot(slot.id)))
        }
        return out
    }

    @ViewBuilder private var aboveNote: some View {
        if !chainAbove.isEmpty {
            Text(engine.chainOf(companyID: company.id) != nil ? "Posts above the company are hired and set in the Chain section and in Group." : "Posts above the company are hired and set in Group (and the holding).")
                .font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func managerRow(_ cur: Currency) -> ManagementRow {
        let title = engine.tradeInfo(companyID: company.id).map { ManagerModel.title($0) } ?? "Manager"
        guard let mid = company.managerID, let m = engine.state.people[mid] else {
            return ManagementRow(name: nil, role: title, scope: "store",
                                 line: company.ownerHours > 0 ? "You run it yourself. Hire one to step back." : "No one runs it day to day. Hire one.",
                                 lineTint: company.ownerHours > 0 ? Theme.ivoryFaint : Theme.caution, wage: nil)
        }
        let notice = company.value("mgrNotice")
        if !notice.isNull {
            return ManagementRow(name: m.name, role: title, scope: "store", line: "Leaves on \(GameCalendar.dateString(week: notice["w"].int, dayOffset: 0)). Find a successor.",
                                 lineTint: Theme.loss, wage: cur.tidyShort(company.managerMonthlyWage))
        }
        var line = ""
        if let card = engine.managerScorecard(companyID: company.id) { line += "scorecard \(card.score), \(Self.scoreWord(card.score))" }
        if company.managerProfitBonus > 0 { line += (line.isEmpty ? "" : " · ") + "\(Int((company.managerProfitBonus * 100).rounded()))% profit share" }
        let weak = (engine.managerScorecard(companyID: company.id)?.score ?? 100) < 35
        return ManagementRow(name: m.name, role: title, scope: "store", line: line, lineTint: weak ? Theme.caution : Theme.ivoryFaint, wage: cur.tidyShort(company.managerMonthlyWage))
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
                             lineTint: jobs.isEmpty ? Theme.caution : Theme.ivoryFaint, wage: cur.tidyShort(a["wage"].double))
    }
}

/// How much a post may decide alone, as three bars and the word: filled up to the level (asks you, within limits, full control).
private struct AuthorityMark: View {
    var level: Int

    var body: some View {
        let lvl: Int = min(2, max(0, level))
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= lvl ? Theme.gold : Theme.hairline).frame(width: 16, height: 4)
                }
            }
            Text(AuthorityWords.label(lvl)).font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Authority: \(AuthorityWords.label(lvl))")
    }
}

/// One step of the vertical strip: a round icon on the rail, a line down to the next step, and the post as a card. A step with a sheet
/// is a button with a chevron; the owner and the posts above the company are plain (they are managed elsewhere).
private struct OrgStripRow: View {
    var node: CompanyManagement.OrgNode
    var last: Bool
    var open: (() -> Void)?

    var body: some View {
        let vacant: Bool = node.row.name == nil
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                IconCircle(glyph: node.glyph, size: 34, tint: vacant ? Theme.ivoryFaint : Theme.gold)
                if !last { Rectangle().fill(Theme.borderStrong).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: 34)
            cardOrButton(vacant)
                .padding(.bottom, last ? 0 : 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func cardOrButton(_ vacant: Bool) -> some View {
        if let open {
            Button { Haptics.tap(); open() } label: { card(vacant, tappable: true) }.buttonStyle(.plain)
        } else {
            card(vacant, tappable: false)
        }
    }

    private func card(_ vacant: Bool, tappable: Bool) -> some View {
        let r: ManagementRow = node.row
        return Card(padding: 12, radius: Theme.Radius.card, stroke: node.isOwner ? Theme.gold.opacity(0.5) : Theme.border) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.role + " · " + r.scope).capsLabel(Theme.ivoryFaint)
                    Text(r.name ?? "Vacant").font(.system(size: 15, weight: .medium)).foregroundStyle(vacant ? Theme.ivoryMuted : Theme.ivory).lineLimit(1)
                    if !r.line.isEmpty { Text(r.line).font(.system(size: 11.5)).foregroundStyle(r.lineTint).fixedSize(horizontal: false, vertical: true) }
                    if let level = node.level { AuthorityMark(level: level).padding(.top, 2) }
                }
                Spacer(minLength: 8)
                trailing(vacant, tappable: tappable)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func trailing(_ vacant: Bool, tappable: Bool) -> some View {
        if let wage = node.row.wage {
            VStack(alignment: .trailing, spacing: 1) {
                Text(wage).font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text("a month").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            }
        } else if vacant && tappable {
            Text("Hire").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
        }
        if tappable { GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim) }
    }
}

// MARK: - The manager

/// The store manager's sheet: performance, what they decide, duties, profit share, talks and pay, replacing them; or hiring one.
struct ManagerSheet: View {
    @State private var discussing: ContractTalk.Topic?
    @State private var discussingOpen = false
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @Binding var candidates: [Int]
    @State private var pending: PendingAction?
    @State private var tab: ManagerTab = .results

    /// The three pages of the manager's sheet: how they are doing, what they may decide, and what they are paid and how you talk.
    enum ManagerTab: String, CaseIterable, Hashable { case results = "Results", powers = "Powers", pay = "Pay and talks" }

    private func band(_ v: Double) -> String { v >= 80 ? "Outstanding" : v >= 65 ? "Strong" : v >= 45 ? "Capable" : v >= 28 ? "Developing" : "Entry level" }

    var body: some View {
        PeopleSheet(title: "Manager") {
            if let e = store.engine, let co = e.state.company(companyID) {
                let cur = e.currency(for: co)
                if let mid = co.managerID, let m = e.state.people[mid] { manage(e, co, m, cur) } else { hire(e, co, cur) }
            } else {
                Text("This company no longer exists.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .confirmAction($pending)
        .sheet(isPresented: Binding(get: { discussing != nil || discussingOpen }, set: { if !$0 { discussing = nil; discussingOpen = false } })) {
            if let mid = store.engine?.state.company(companyID)?.managerID { ContractDiscussionView(companyID: companyID, personID: mid, startTopic: discussing).environmentObject(store) }
        }
    }

    // MARK: Managing the manager

    @ViewBuilder private func manage(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        let bd = e.tradeInfo(companyID: co.id)
        let started = co.value("mgrW0").isNull ? e.state.week : co.int("mgrW0")
        let months = max(0, e.state.week - started) / 4
        let notice = co.value("mgrNotice")
        let mgrRole: String = bd.map { ManagerModel.title($0) } ?? "Manager"
        let mgrNote: String = "\(co.name) · age \(m.age) · \(String(format: "%g", m.num("exp"))) years of experience · \(months) month\(months == 1 ? "" : "s") in the job"
        PersonCard(name: m.name, role: mgrRole, scope: "store", note: mgrNote, wage: cur.tidyShort(co.managerMonthlyWage), chevron: false, roleKey: "manager")
        if !notice.isNull {
            CardSection("Leaving") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(m.name.split(separator: " ").first.map(String.init) ?? "The manager") leaves on \(GameCalendar.dateString(week: notice["w"].int, dayOffset: 0)). Hire a successor before then and they will hand over.")
                        .font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                    SuccessorSection(engine: e, company: co)
                }
            }
        }
        SegmentedPill(items: ManagerTab.allCases, title: { $0.rawValue }, selection: $tab)
        switch tab {
        case .results:
            performance(e, co, m, months)
        case .powers:
            authority(e, co, m, cur)
            duties(e, co)
        case .pay:
            profitShare(e, co, m, cur)
            talks(e, co, m, cur)
            lettingGo(co, m, cur)
        }
    }

    @ViewBuilder private func performance(_ e: GameEngine, _ co: Company, _ m: Person, _ months: Int) -> some View {
        let bd = e.tradeInfo(companyID: co.id)
        CardSection("Performance") {
            VStack(alignment: .leading, spacing: 10) {
                RateBar(label: "Overall results", fraction: e.managerQuality(companyID: co.id))
                if let card = e.managerScorecard(companyID: co.id) {
                    FigureCard(items: [
                        .init(label: "Scorecard", value: "\(card.score)", tint: card.score < 35 ? Theme.loss : card.score >= 65 ? Theme.gain : Theme.ivory, sub: CompanyManagement.scoreWord(card.score)),
                        .init(label: "Margin, 3 months", value: String(format: "%.0f%%", card.margin * 100), tint: Theme.change(card.margin)),
                        .init(label: "Reputation", value: "\(card.reputation)"),
                        .init(label: "Quality", value: "\(card.quality)"),
                    ], columns: 4)
                    if card.paperworkGaps > 0 { Text("\(card.paperworkGaps.peopleText) with paperwork missing \(card.paperworkGaps == 1 ? "counts" : "count") against them.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
                    if card.fraud > 0 { Text("Fraud was found under this manager.").font(.system(size: 11.5)).foregroundStyle(Theme.loss) }
                }
                if let bd, m.str("mtype") != bd.managerType { Text("Not the ideal type for this trade.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
                if months >= 3 {
                    let st = m.value("stats")
                    ForEach(Array(ManagerModel.skillKeys.enumerated()), id: \.offset) { _, k in
                        HStack {
                            Text(k.label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                            Spacer()
                            Text(band(st[k.key].double)).font(.system(size: 12.5)).foregroundStyle(Theme.ivory)
                        }
                    }
                } else {
                    Text("Detailed skills show after a few months. Judge by results.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                Text("The scorecard weighs margin, reputation, quality, mistakes, paperwork and targets met. Targets and their bonus are set under Targets and budget.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func authority(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        let auth = co.value("auth")
        let lvl = Int(auth["lvl"].double)
        CardSection("Decides") {
            VStack(alignment: .leading, spacing: 10) {
                AuthorityLevelPicker(level: lvl) { v in
                    store.settle(store.act { $0.setManagerAuthority(companyID: co.id, level: v) }, "\(m.name) now \(GameEngine.authorityText(level: v)).", same: "\(m.name) already works that way.")
                }
                if lvl == 1 {
                    limitRow("Pay and promotions a month", auth["hire"].double, [0, 3000, 8000, 15000, 30000], cur) { v in store.settle(store.act { $0.setManagerAuthority(companyID: co.id, pay: v) }, "Pay and promotions limit: \(cur.tidyShort(v)) a month.") }
                    limitRow("Purchases and hires up to", auth["buy"].double, [10000, 25000, 50000, 100000, 250000], cur) { v in store.settle(store.act { $0.setManagerAuthority(companyID: co.id, buy: v) }, "Purchases and hires limit: \(cur.tidyShort(v)).") }
                    limitRow("Advertising a week", auth["ad"].double, [0, 1500, 3000, 7000], cur) { v in store.settle(store.act { $0.setManagerAuthority(companyID: co.id, ad: v) }, "Advertising limit: \(cur.tidyShort(v)) a week.") }
                    Text("Above these limits a request comes to you (or to the boss above them first) and shows in Team as a decision.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func limitRow(_ label: String, _ value: Double, _ options: [Double], _ cur: Currency, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { o in
                    Button(o == 0 ? "None" : cur.tidyShort(cur.scaledPrice(o))) { set(cur.scaledPrice(o)); store.show("\(label): \(o == 0 ? "none" : cur.tidyShort(cur.scaledPrice(o))).", tone: "n") }
                }
            } label: { Text((value == 0 ? "None" : cur.tidyShort(value)) + "  ⌄").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.gold) }
        }
    }

    @ViewBuilder private func duties(_ e: GameEngine, _ co: Company) -> some View {
        let list = e.managerDuties(companyID: co.id)
        if !list.isEmpty {
            CardSection("Duties") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { d in
                        Button {
                            store.act { $0.setManagerDuty(companyID: co.id, duty: d.id, manager: !d.manager) }
                            let now = store.engine?.managerDuties(companyID: co.id).first { $0.id == d.id }?.manager
                            store.show(now == true ? "The manager looks after \(d.title.lowercased()) again." : now == false ? "You keep \(d.title.lowercased()) yourself." : "Not possible now.", tone: now == nil ? "warn" : "n")
                            Haptics.choose()
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.title.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                    Text(d.manager ? d.managerText : d.ownerText).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                handoverSwitch(managerHas: d.manager)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Who looks after a duty, as a two-part switch: the lit side is the one that does it. Tapping the row flips it.
    private func handoverSwitch(managerHas: Bool) -> some View {
        HStack(spacing: 0) {
            handoverSide("Manager", on: managerHas)
            handoverSide("You", on: !managerHas)
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func handoverSide(_ text: String, on: Bool) -> some View {
        Text(text).font(.system(size: 11.5, weight: on ? .medium : .regular))
            .foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.goldSelected : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? Theme.gold : Color.clear, lineWidth: 1))
    }

    @ViewBuilder private func profitShare(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        if let pv = e.managerProfitBonusPreview(companyID: co.id, share: co.managerProfitBonus) {
            CardSection(title: "Profit share", trailing: {
                Text(pv.current > 0 ? "\(Int((pv.current * 100).rounded()))% of profit" : "none").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A share of each profitable month's profit, paid on top of the salary with the next wages. Nothing is paid in a loss month.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    FlatRow(label: "Average monthly profit, last 3 months", value: cur.tidyShort(pv.averageMonthlyProfit), rule: false)
                    if pv.current > 0 { FlatRow(label: "At this share it costs about", value: "\(cur.tidyShort(pv.monthlyCost)) a month") }
                    if pv.lastPaid > 0 { FlatRow(label: "Bonus paid last month", value: cur.tidyShort(pv.lastPaid)) }
                    Button(pv.current > 0 ? "Change the share…" : "Offer a profit share…") { discussing = .bonus }
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private func talks(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        CardSection("Talk and pay") {
            VStack(alignment: .leading, spacing: 12) {
                WrapRow {
                    Button("Meet") {
                        let ok = store.act { $0.meetManager(companyID: co.id) } ?? false
                        store.show(ok ? "You met. Their news is in the Inbox." : "You met recently. Give it a few weeks.", tone: ok ? "good" : "n")
                    }.buttonStyle(QuietButtonStyle())
                    Menu {
                        ForEach(Array(ManagerModel.askOptions.enumerated()), id: \.offset) { _, o in
                            Button(o.label) {
                                let said = store.act { $0.askManager(companyID: co.id, key: o.key) } ?? nil
                                store.show(said.map { "\(m.name): \($0)" } ?? "\(m.name) has nothing to add on that now.", tone: "n")
                            }
                        }
                    } label: { Text("Ask for…  ⌄").font(.system(.subheadline).weight(.semibold)).foregroundStyle(Theme.gold).padding(.horizontal, 14).padding(.vertical, 8).overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1)) }
                    Button("Contract discussion…") { discussing = nil; discussingOpen = true }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    /// Replacing the manager: its own card apart from the talks, with the consequence stated before the button.
    private func lettingGo(_ co: Company, _ m: Person, _ cur: Currency) -> some View {
        Card(padding: 14, radius: Theme.Radius.card, stroke: Theme.loss.opacity(0.4)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconCircle(glyph: Glyph.exit, size: 34, tint: Theme.loss)
                    Text("Replace the manager").font(.serifTitle(16)).foregroundStyle(Theme.ivory)
                }
                Text("Notice and severance by the country's labour law are paid now. You run \(co.name) yourself until you hire someone new.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                QuietButton(title: "Replace…", tint: Theme.loss) {
                    pending = PendingAction(title: "Dismiss \(m.name)?",
                                            message: "Notice and severance by the country's labour law are paid now. You run \(co.name) yourself until you hire someone new.",
                                            button: "Dismiss", destructive: true) {
                        let sev = store.act { $0.dismissManager(companyID: co.id) } ?? 0
                        store.show("\(m.name) has gone. Paid \(cur.tidyDisplay(sev)) in notice and severance. You run \(co.name) yourself again.", tone: "n"); Haptics.warning()
                    }
                }
            }
        }
    }

    // MARK: Hiring a manager

    @ViewBuilder private func hire(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let title = e.tradeInfo(companyID: co.id).map { ManagerModel.title($0) } ?? "Manager"
        let fee = ManagerModel.searchFee(currency: cur)
        VStack(alignment: .leading, spacing: 4) {
            Text("Hire a \(title.lowercased())").font(.serifTitle(22)).foregroundStyle(Theme.ivory)
            RoleScopeBadge(role: co.name, scope: "store")
        }
        Text("Runs \(co.name) day to day: hires, prices, stock, and keeps the team up. You set what they may decide and step back from the work. They are not cheap, and a manager nobody checks on slowly slips.")
            .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
        Button(candidates.isEmpty ? "Executive search · \(cur.tidyShort(fee))" : "Search again · \(cur.tidyShort(fee))") {
            pending = PendingAction(title: "Pay for an executive search?",
                                    message: "Cost: \(cur.tidyShort(fee)), not refunded. Benefit: a shortlist you can interview and check. Risk: none may suit.",
                                    button: "Search for \(cur.tidyShort(fee))", amount: fee, currency: cur) {
                if let list = store.act({ $0.searchManagers(companyID: co.id) }) ?? nil { candidates = list.map { $0.id }; Haptics.tap(); store.show("\(list.count) candidates found. Search paid: \(cur.tidyShort(fee)).", tone: "n") }
                else { Haptics.warning(); store.show("Not enough cash for the search (\(cur.tidyShort(fee))).", tone: "warn") }
            }
        }.buttonStyle(QuietButtonStyle())
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Run a search to see candidates." : "Everyone on the shortlist has taken another job. Search again.") { p in
            CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(e, p, extra: ManagerModel.typeTitles[p.str("mtype")] ?? "Manager"),
                             market: e.goingRate(for: .manager, companyID: co.id), factors: [0.9, 1.0, 1.15, 1.3], roleKey: "manager", offer: { wage in
                let fb = HireFeedback.from(store.act { $0.hireManager(personID: p.id, companyID: co.id, monthlyWage: wage) }, name: p.name, company: co.name)
                if fb.isHired { candidates = []; store.show(fb.text, tone: "good") }
                return fb
            }) {
                ManagerCandidateChecks(person: p, companyID: co.id, currency: cur)
            }
        }
    }
}

/// What a manager candidate says about themselves, the interview questions left and the reference check (the engine's interview model).
struct ManagerCandidateChecks: View {
    @EnvironmentObject var store: GameStore
    var person: Person
    var companyID: Int
    var currency: Currency
    @State private var trialSeen: Double?

    private func band(_ v: Double) -> String { v >= 80 ? "Outstanding" : v >= 65 ? "Strong" : v >= 45 ? "Capable" : v >= 28 ? "Developing" : "Entry level" }

    var body: some View {
        let q = person.value("q")
        let checked = person.flag("ref")
        let fee = currency.scaledPrice(2500)
        VStack(alignment: .leading, spacing: 4) {
            if !person.str("resume").isEmpty { Text(person.str("resume")).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(ManagerModel.skillKeys.enumerated()), id: \.offset) { _, k in
                if checked {
                    Text("\(k.label): really \(band(person.value("stats")[k.key].double).lowercased())").font(.system(size: 11.5)).foregroundStyle(Theme.ivory)
                } else if !q[k.key].isNull {
                    Text("\(k.label): says \(band(q[k.key].double).lowercased())").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
                }
            }
            WrapRow {
                if let seen = trialSeen {
                    Text("Trial week: their work looked like skill \(Int(seen.rounded())).").font(.system(size: 11.5)).foregroundStyle(Theme.ivory)
                } else {
                    Button("Trial week") {
                        let r: Double? = store.act { $0.startTrialWeek(personID: person.id, companyID: companyID) } ?? nil
                        if let r { trialSeen = r; Haptics.success(); store.show("After a paid trial week their work looks like \(Int(r.rounded())) skill.", tone: "n") }
                        else { Haptics.warning(); store.show("Could not arrange a trial week: it was done already, or the company lacks the cash for a week's wage.", tone: "warn") }
                    }.buttonStyle(QuietButtonStyle())
                }
                if !checked {
                    Button("References · \(currency.tidyShort(fee))") {
                        let ok = store.act { $0.checkManagerReferences(personID: person.id, companyID: companyID) } ?? false
                        if !ok { Haptics.warning() }
                        store.show(ok ? "References in: their real skills are shown. Paid \(currency.tidyShort(fee))." : "Not enough cash for the reference check (\(currency.tidyShort(fee))).", tone: ok ? "n" : "warn")
                    }.buttonStyle(QuietButtonStyle())
                } else {
                    Text("References checked").font(.system(size: 11.5)).foregroundStyle(Theme.gain)
                }
            }
            Text("A paid trial week shows about how good their work is; references show what is true.").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
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
                Text("This company no longer exists.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .confirmAction($pending)
    }

    @ViewBuilder private func manage(_ co: Company, _ a: JSONValue, _ n: Person, _ cur: Currency) -> some View {
        let asstNote: String = "\(co.name) · works a full week and takes jobs off \(co.managerID == nil ? "your" : "the manager's") plate. They advise; you decide."
        PersonCard(name: n.name, role: "Assistant manager", scope: "store", note: asstNote, wage: cur.tidyShort(a["wage"].double), chevron: false, roleKey: "assistant-manager")
        let picked: Int = a["duties"].array.count
        TeamGroup(title: "Jobs", trailing: {
            HStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule().fill(i < picked ? Theme.gold : Theme.hairline).frame(width: 18, height: 4)
                }
                Text("\(picked) of 2").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).padding(.leading, 4)
            }
        }) {
            ForEach(Array(ManagerModel.assistantDuties.enumerated()), id: \.offset) { _, d in
                let on: Bool = a["duties"].array.contains { $0.string == d.key }
                jobCard(co, n, d, on: on)
            }
            Text("Two jobs at most. Pick one, or swap by unticking another first.").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
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
                        Text(d.title.tidyMoney).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text(d.text.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func letGo(_ co: Company, _ a: JSONValue, _ n: Person, _ cur: Currency) -> some View {
        let first: String = n.name.split(separator: " ").first.map(String.init) ?? "them"
        return Card(padding: 14, radius: Theme.Radius.card, stroke: Theme.loss.opacity(0.4)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconCircle(glyph: Glyph.exit, size: 34, tint: Theme.loss)
                    Text("Let \(first) go").font(.serifTitle(16)).foregroundStyle(Theme.ivory)
                }
                Text("About one month of pay (\(cur.tidyShort(a["wage"].double))) as notice. Their jobs go back to \(co.managerID == nil ? "you" : "the manager").")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                QuietButton(title: "Let \(first) go…", tint: Theme.loss) {
                    pending = PendingAction(title: "Let \(n.name) go?", message: "About one month of pay (\(cur.tidyShort(a["wage"].double))) as notice. Their jobs go back to \(co.managerID == nil ? "you" : "the manager").",
                                            button: "Let go", destructive: true) {
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
            Text("Hire an assistant manager").font(.serifTitle(22)).foregroundStyle(Theme.ivory)
            RoleScopeBadge(role: co.name, scope: "store")
        }
        Text("Works alongside the team and takes up to two jobs off \(co.managerID == nil ? "your" : "the manager's") plate: complaints, paperwork, equipment. Paid more than a worker, less than a manager. They advise; you decide.")
            .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
        Button(candidates.isEmpty ? "Job ad · \(cur.tidyShort(fee))" : "New job ad · \(cur.tidyShort(fee))") {
            pending = PendingAction(title: "Place a job ad?", message: "Cost: \(cur.tidyShort(fee)). Benefit: a shortlist of applicants. Risk: none may suit.", button: "Pay \(cur.tidyShort(fee))", amount: fee, currency: cur) {
                if let list = store.act({ $0.searchAssistants(companyID: co.id) }) ?? nil { candidates = list.map { $0.id }; Haptics.tap(); store.show("\(list.count) applicants. Job ad paid: \(cur.tidyShort(fee)).", tone: "n") }
                else { Haptics.warning(); store.show("Not enough cash for the job ad (\(cur.tidyShort(fee))).", tone: "warn") }
            }
        }.buttonStyle(QuietButtonStyle())
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Place a job ad to see applicants." : "Everyone has taken another job. Place a new ad.") { p in
            CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(e, p), market: e.goingRate(for: .assistant, companyID: co.id), factors: [0.9, 1.0, 1.15, 1.3], roleKey: "assistant-manager") { wage in
                var fb = HireFeedback.from(store.act { $0.hireAssistant(personID: p.id, companyID: co.id, monthlyWage: wage) }, name: p.name, role: "Assistant manager")
                if fb.isHired { candidates = []; fb = .hired("\(p.name) is your assistant manager. Pick their two jobs."); store.show(fb.text, tone: "good") }
                return fb
            }
        }
    }
}
