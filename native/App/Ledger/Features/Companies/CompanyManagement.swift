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
        LedgerSection(title: "Management", trailing: {
            Text("\(filled) of \(2 + slots.count) posts filled").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                Button { Haptics.tap(); sheet = .manager } label: { managerRow(cur) }.buttonStyle(.plain)
                Hairline()
                Button { Haptics.tap(); sheet = .assistant } label: { assistantRow(cur) }.buttonStyle(.plain)
                ForEach(slots) { slot in
                    Hairline()
                    Button { Haptics.tap(); sheet = .slot(slot.id) } label: { TeamSlotSheet.row(slot, company: company, engine: engine, cur: cur) }.buttonStyle(.plain)
                }
                above
            }
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
        let lvl = Int(company.value("auth")["lvl"].double)
        var line = AuthorityWords.label(lvl)
        if let card = engine.managerScorecard(companyID: company.id) { line += " · scorecard \(card.score), \(Self.scoreWord(card.score))" }
        if company.managerProfitBonus > 0 { line += " · \(Int((company.managerProfitBonus * 100).rounded()))% profit share" }
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

    /// Who stands above this company's own management (chain, region, group), managed where those posts live.
    @ViewBuilder private var above: some View {
        let chain = engine.decisionChain(companyID: company.id).filter { $0.kind != "mgr" && $0.kind != "mdir" || ($0.kind == "mdir" && company.holdingID != 0) }
        if !chain.isEmpty {
            Hairline()
            VStack(alignment: .leading, spacing: 3) {
                Text("Above this company").capsLabel(Theme.ivoryFaint)
                ForEach(Array(chain.enumerated()), id: \.offset) { _, b in
                    Text("\(b.name), \(GameEngine.bossTitle(b.kind, trade: nil).lowercased()), \(GameEngine.authorityText(level: b.level))")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }
                Text(engine.chainOf(companyID: company.id) != nil ? "Hired and set in the Chain section and in Group." : "Hired and set in Group (and the holding).")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            }.padding(.top, 8)
        }
    }
}

// MARK: - The manager

/// The store manager's sheet: performance, what they decide, duties, profit share, talks and pay, replacing them; or hiring one.
struct ManagerSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @Binding var candidates: [Int]
    @State private var pending: PendingAction?

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
    }

    // MARK: Managing the manager

    @ViewBuilder private func manage(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        let bd = e.tradeInfo(companyID: co.id)
        let started = co.value("mgrW0").isNull ? e.state.week : co.int("mgrW0")
        let months = max(0, e.state.week - started) / 4
        let notice = co.value("mgrNotice")
        VStack(alignment: .leading, spacing: 4) {
            Text(m.name).font(.serifTitle(22)).foregroundStyle(Theme.ivory)
            RoleScopeBadge(role: bd.map { ManagerModel.title($0) } ?? "Manager", scope: "store")
            Text("\(co.name) · age \(m.age) · \(String(format: "%g", m.num("exp"))) years of experience · \(months) month\(months == 1 ? "" : "s") in the job · \(cur.tidyShort(co.managerMonthlyWage)) a month")
                .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }
        if !notice.isNull {
            LedgerSection("Leaving") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(m.name.split(separator: " ").first.map(String.init) ?? "The manager") leaves on \(GameCalendar.dateString(week: notice["w"].int, dayOffset: 0)). Hire a successor before then and they will hand over.")
                        .font(.system(size: 12)).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                    SuccessorSection(engine: e, company: co)
                }
            }
        }
        performance(e, co, m, months)
        authority(e, co, m, cur)
        duties(e, co)
        profitShare(e, co, m, cur)
        talks(e, co, m, cur)
    }

    @ViewBuilder private func performance(_ e: GameEngine, _ co: Company, _ m: Person, _ months: Int) -> some View {
        let bd = e.tradeInfo(companyID: co.id)
        LedgerSection("Performance") {
            VStack(alignment: .leading, spacing: 10) {
                RateBar(label: "Overall results", fraction: e.managerQuality(companyID: co.id))
                if let card = e.managerScorecard(companyID: co.id) {
                    KeyFigures(items: [
                        .init(label: "Scorecard", value: "\(card.score)", tint: card.score < 35 ? Theme.loss : card.score >= 65 ? Theme.gain : Theme.ivory, sub: CompanyManagement.scoreWord(card.score)),
                        .init(label: "Margin, 3 months", value: String(format: "%.0f%%", card.margin * 100), tint: Theme.change(card.margin)),
                        .init(label: "Reputation", value: "\(card.reputation)"),
                        .init(label: "Quality", value: "\(card.quality)"),
                    ], columns: 4)
                    if card.paperworkGaps > 0 { Text("\(card.paperworkGaps) staff with paperwork missing count against them.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
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
        LedgerSection("Decides") {
            VStack(alignment: .leading, spacing: 10) {
                AuthorityLevelPicker(level: lvl) { v in
                    store.act { $0.setManagerAuthority(companyID: co.id, level: v) }
                    store.show("\(m.name) now \(GameEngine.authorityText(level: v)).", tone: "n")
                }
                if lvl == 1 {
                    limitRow("Pay and promotions a month", auth["hire"].double, [0, 3000, 8000, 15000, 30000], cur) { v in store.act { $0.setManagerAuthority(companyID: co.id, pay: v) } }
                    limitRow("Purchases and hires up to", auth["buy"].double, [10000, 25000, 50000, 100000, 250000], cur) { v in store.act { $0.setManagerAuthority(companyID: co.id, buy: v) } }
                    limitRow("Advertising a week", auth["ad"].double, [0, 1500, 3000, 7000], cur) { v in store.act { $0.setManagerAuthority(companyID: co.id, ad: v) } }
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
            } label: { Text(value == 0 ? "None" : cur.tidyShort(value)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.gold) }
        }
    }

    @ViewBuilder private func duties(_ e: GameEngine, _ co: Company) -> some View {
        let list = e.managerDuties(companyID: co.id)
        if !list.isEmpty {
            LedgerSection("Duties") {
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
                                    Text(d.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                    Text(d.manager ? d.managerText : d.ownerText).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Text(d.manager ? "Manager" : "You").font(.system(size: 12, weight: .medium)).foregroundStyle(d.manager ? Theme.gold : Theme.ivoryMuted)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func profitShare(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        if let pv = e.managerProfitBonusPreview(companyID: co.id, share: co.managerProfitBonus) {
            LedgerSection(title: "Profit share", trailing: {
                Text(pv.current > 0 ? "\(Int((pv.current * 100).rounded()))% of profit" : "none").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A share of each profitable month's profit, paid on top of the salary with the next wages. Nothing is paid in a loss month.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    FlatRow(label: "Average monthly profit, last 3 months", value: cur.tidyShort(pv.averageMonthlyProfit), rule: false)
                    if pv.current > 0 { FlatRow(label: "At this share it costs about", value: "\(cur.tidyShort(pv.monthlyCost)) a month") }
                    if pv.lastPaid > 0 { FlatRow(label: "Bonus paid last month", value: cur.tidyShort(pv.lastPaid)) }
                    Menu {
                        ForEach([0.0, 0.05, 0.1, 0.15, 0.2, 0.3], id: \.self) { x in
                            Button(x == 0 ? "No profit share" : "\(Int(x * 100))%") { askShare(x, co, m, cur) }
                        }
                    } label: {
                        Text(pv.current > 0 ? "Change the share" : "Offer a profit share").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                    }
                }
            }
        }
    }

    private func askShare(_ x: Double, _ co: Company, _ m: Person, _ cur: Currency) {
        guard let pv = store.engine?.managerProfitBonusPreview(companyID: co.id, share: x) else { return }
        let pct = Int((x * 100).rounded())
        pending = PendingAction(
            title: x == 0 ? "Stop \(m.name)'s profit share?" : "Give \(m.name) \(pct)% of profit?",
            message: x == 0
                ? "Saves about \(cur.tidyShort(pv.averageMonthlyProfit * pv.current)) a month at recent profit. They lose part of their pay, which they will not like."
                : "Cost: about \(cur.tidyShort(pv.monthlyCost)) a month at the recent average profit of \(cur.tidyShort(pv.averageMonthlyProfit)), employer costs included; more in a good month, nothing in a loss month. Benefit: their pay follows the profit, and the share moves with them if you move them. Risk: you pay it on profit they did not make.",
            button: x == 0 ? "Stop the share" : "Set \(pct)%") {
                store.act { $0.setManagerProfitBonus(companyID: co.id, share: x) }
                let now = store.engine?.state.company(co.id)?.managerProfitBonus ?? -1
                if abs(now - min(0.3, x)) < 0.0001 { store.show(x == 0 ? "No profit share now." : "\(m.name) now gets \(pct)% of each month's profit.", tone: "good"); Haptics.success() }
                else { store.show("The share could not be set.", tone: "warn") }
            }
    }

    @ViewBuilder private func talks(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        let free = e.state.companies.filter { $0.id != co.id && $0.managerID == nil && $0.status.isLive && $0.type != "hold" && $0.type != "club" }
        LedgerSection("Talk and pay") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Button("Meet") {
                        let ok = store.act { $0.meetManager(companyID: co.id) } ?? false
                        store.show(ok ? "You met. Their news is in the Inbox." : "You met recently. Give it a few weeks.", tone: ok ? "good" : "n")
                    }
                    Menu("Ask for…") {
                        ForEach(Array(ManagerModel.askOptions.enumerated()), id: \.offset) { _, o in
                            Button(o.label) {
                                let said = store.act { $0.askManager(companyID: co.id, key: o.key) } ?? nil
                                store.show(said.map { "\(m.name): \($0)" } ?? "\(m.name) has nothing to add on that now.", tone: "n")
                            }
                        }
                    }
                    Button("Give a raise") {
                        let next = cur.roundedStep(co.managerMonthlyWage * 1.08, about: 100)
                        pending = PendingAction(title: "Give \(m.name) a raise?",
                                                message: "Cost: their pay goes from \(cur.tidyShort(co.managerMonthlyWage)) to about \(cur.tidyShort(next)) a month. Benefit: a happier manager is less likely to leave or slack. Risk: pay only goes up.",
                                                button: "Raise to \(cur.tidyShort(next))") {
                            store.act { $0.giveManagerRaise(companyID: companyID) }
                            let now = store.engine?.state.company(companyID)?.managerMonthlyWage ?? 0
                            store.show("Raise given: now \(cur.tidyShort(now)) a month.", tone: "good"); Haptics.success()
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 16) {
                    if !free.isEmpty {
                        Menu("Move to…") {
                            ForEach(free) { c in
                                Button(c.name) {
                                    pending = PendingAction(title: "Move \(m.name) to \(c.name)?",
                                                            message: "\(c.name) gets a manager, with their pay and any profit share. \(co.name) is left without a store manager until you hire one.",
                                                            button: "Move") {
                                        let ok = store.act { $0.moveManager(from: co.id, to: c.id) } ?? false
                                        store.show(ok ? "\(m.name) now manages \(c.name)." : "Could not move them.", tone: ok ? "good" : "warn")
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Replace") {
                        pending = PendingAction(title: "Dismiss \(m.name)?",
                                                message: "Notice and severance by the country's labour law are paid now. You run \(co.name) yourself until you hire someone new.",
                                                button: "Dismiss", destructive: true) {
                            let sev = store.act { $0.dismissManager(companyID: co.id) } ?? 0
                            store.show("\(m.name) has gone. Paid \(cur.display(sev)) in notice and severance. You run \(co.name) yourself again.", tone: "n"); Haptics.warning()
                        }
                    }.foregroundStyle(Theme.loss)
                }
            }
            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
        }
    }

    // MARK: Hiring a manager

    @ViewBuilder private func hire(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let title = e.tradeInfo(companyID: co.id).map { ManagerModel.title($0) } ?? "Manager"
        let fee = cur.scaledPrice(15000)
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
                else { store.show("Not enough cash for the search.", tone: "warn") }
            }
        }.buttonStyle(QuietButtonStyle())
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Run a search to see candidates." : "Everyone on the shortlist has taken another job. Search again.") { p in
            CandidateHireRow(person: p, currency: cur, subtitle: "Age \(p.age) · \(String(format: "%g", p.num("exp"))) yr · \(ManagerModel.typeTitles[p.str("mtype")] ?? "Manager")",
                             factors: [1.0, 1.1, 1.25], offer: { wage in
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

    private func band(_ v: Double) -> String { v >= 80 ? "Outstanding" : v >= 65 ? "Strong" : v >= 45 ? "Capable" : v >= 28 ? "Developing" : "Entry level" }

    var body: some View {
        let q = person.value("q")
        let left = person.value("qLeft").isNull ? 3 : person.int("qLeft")
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
            HStack(spacing: 16) {
                Menu("Interview (\(left) question\(left == 1 ? "" : "s") left)") {
                    ForEach(Array(ManagerModel.skillKeys.enumerated()), id: \.offset) { _, k in
                        Button(k.label) {
                            let r = store.act { $0.interviewManager(personID: person.id, skill: k.key) } ?? nil
                            if r == nil { store.show("No questions left for \(person.name).", tone: "warn") }
                        }.disabled(left <= 0 && q[k.key].isNull)
                    }
                }
                if !checked {
                    Button("References · \(currency.tidyShort(fee))") {
                        let ok = store.act { $0.checkManagerReferences(personID: person.id, companyID: companyID) } ?? false
                        store.show(ok ? "References in: their real skills are shown." : "Not enough cash for the reference check.", tone: ok ? "n" : "warn")
                    }
                } else {
                    Text("References checked").font(.system(size: 11.5)).foregroundStyle(Theme.gain)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
            Text("Interviews show what they claim; references show what is true.").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(n.name).font(.serifTitle(22)).foregroundStyle(Theme.ivory)
            RoleScopeBadge(role: "Assistant manager", scope: "store")
            Text("\(co.name) · \(cur.tidyShort(a["wage"].double)) a month · works a full week and takes jobs off \(co.managerID == nil ? "your" : "the manager's") plate. They advise; you decide.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }
        LedgerSection(title: "Jobs", trailing: { Text("\(a["duties"].array.count) of 2").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ManagerModel.assistantDuties.enumerated()), id: \.offset) { i, d in
                    if i > 0 { Hairline() }
                    let on = a["duties"].array.contains { $0.string == d.key }
                    Button {
                        let ok = store.act { $0.toggleAssistantDuty(companyID: co.id, duty: d.key) } ?? false
                        store.show(ok ? (on ? "\(n.name) no longer looks after \(d.title.lowercased())." : "\(n.name) now looks after \(d.title.lowercased()).") : "Two jobs at most. Untick one first.", tone: ok ? "n" : "warn")
                        Haptics.choose()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(d.text).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.gold : Theme.ivoryFaint)
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        Button("Let \(n.name.split(separator: " ").first.map(String.init) ?? "them") go") {
            pending = PendingAction(title: "Let \(n.name) go?", message: "About one month of pay as notice. Their jobs go back to \(co.managerID == nil ? "you" : "the manager").",
                                    button: "Let go", destructive: true) {
                store.act { $0.dismissAssistant(companyID: co.id) }
                let gone = store.engine?.state.company(co.id)?.value("asst")["npc"].int ?? 0 == 0
                store.show(gone ? "\(n.name) has left." : "They are still here.", tone: gone ? "n" : "warn"); Haptics.warning()
            }
        }
        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.loss).buttonStyle(.plain)
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
                else { store.show("Not enough cash for the job ad.", tone: "warn") }
            }
        }.buttonStyle(QuietButtonStyle())
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Place a job ad to see applicants." : "Everyone has taken another job. Place a new ad.") { p in
            CandidateHireRow(person: p, currency: cur) { wage in
                var fb = HireFeedback.from(store.act { $0.hireAssistant(personID: p.id, companyID: co.id, monthlyWage: wage) }, name: p.name, role: "Assistant manager")
                if fb.isHired { candidates = []; fb = .hired("\(p.name) is your assistant manager. Pick their two jobs."); store.show(fb.text, tone: "good") }
                return fb
            }
        }
    }
}

/// The promotion talk: the posts a person could fill, what they would ask, and a counter if the offer is close.
/// Original: ACT.p11offer and the promotion page (features/people/worker_roles_and_promotions.js).
struct PromotionSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var engine: GameEngine
    var company: Company
    var member: StaffMember
    @State private var post: ManagerModel.PromotionPost?
    @State private var offer = 0.0
    @State private var reply = ""

    var body: some View {
        let cur = engine.currency(for: company)
        let name = engine.state.people[member.id]?.name ?? "This person"
        let posts = engine.promotionPosts(companyID: company.id, personID: member.id)
        PeopleSheet(title: "Promotion") {
            Text("Promote \(name)").font(.serifTitle(22)).foregroundStyle(Theme.ivory)
            LedgerSection("Promote to") {
                VStack(spacing: 0) {
                    if posts.isEmpty { Text("No higher post fits right now.").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(Array(posts.enumerated()), id: \.element.id) { n, p in
                        if n > 0 { Hairline() }
                        Button { post = p; offer = p.ask; reply = "" } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                    Text("\(p.place) · will ask about \(cur.tidyShort(p.ask)) a month").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer()
                                Image(systemName: post?.id == p.id ? "checkmark" : "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let post {
                LedgerSection("Your offer for \(post.title.lowercased())") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Now \(cur.tidyShort(member.monthlyWage)) a month.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        HStack(spacing: 12) {
                            ForEach([0.9, 1.0, 1.1], id: \.self) { f in
                                Button("\(Int(f * 100))% · \(cur.tidyShort(cur.roundedStep(post.ask * f, about: 500)))") { offer = cur.roundedStep(post.ask * f, about: 500) }
                                    .buttonStyle(QuietButtonStyle())
                            }
                        }
                        AmountField(title: "Monthly salary", currency: cur, amount: $offer)
                        Button("Send offer · \(cur.tidyShort(offer))") { send(post, cur) }.buttonStyle(GoldButtonStyle())
                        if !reply.isEmpty { Text(reply).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
        }
    }

    private func send(_ post: ManagerModel.PromotionPost, _ cur: Currency) {
        let r = store.act { $0.offerPromotion(companyID: company.id, personID: member.id, post: post.id, monthlyWage: offer) }
        switch r {
        case .accepted(let text)?: Haptics.success(); store.show(text, tone: "good"); dismiss()
        case .counter(let want, let text)?: reply = text; offer = want; Haptics.tap()
        case .tooLow(let text)?: reply = text; Haptics.warning()
        case .declinedForGood(let text)?: reply = text; store.show(text, tone: "warn"); dismiss()
        case .unavailable(let text)?: reply = text
        case nil: store.show("No game is loaded.", tone: "warn")
        }
    }
}
