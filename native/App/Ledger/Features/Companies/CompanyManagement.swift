import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Who runs the company: the manager (what they decide, their skill and pay, hiring and replacing them), and the assistant manager.
/// Shown at the top of Company > Team. Original: the Manager and Assistant pages of the company headquarters (ui/company/people.js,
/// features/people/owner_hours_clients_assistants.js).
struct CompanyManagement: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var candidates: [Int] = []
    @State private var assistants: [Int] = []
    @State private var confirmDismiss = false
    @State private var confirmDismissAssistant = false

    private func band(_ v: Double) -> String { v >= 80 ? "Outstanding" : v >= 65 ? "Strong" : v >= 45 ? "Capable" : v >= 28 ? "Developing" : "Entry level" }

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if let mid = company.managerID, let m = engine.state.people[mid] { manager(m, cur) } else { hireManager(cur) }
            assistant(cur)
        }
        .confirmationDialog("Replace the manager?", isPresented: $confirmDismiss, titleVisibility: .visible) {
            Button("Dismiss", role: .destructive) {
                let sev = store.act { $0.dismissManager(companyID: company.id) } ?? 0
                store.show("Severance paid: \(cur.display(sev)). You run \(company.name) yourself again.", tone: "n"); Haptics.warning()
            }
        } message: { Text("You pay three months of salary as severance and run the company yourself until you hire someone new.") }
        .confirmationDialog("Let the assistant go?", isPresented: $confirmDismissAssistant, titleVisibility: .visible) {
            Button("Let go", role: .destructive) { store.act { $0.dismissAssistant(companyID: company.id) }; Haptics.warning() }
        } message: { Text("About one month of pay as notice.") }
    }

    // MARK: The manager

    @ViewBuilder private func manager(_ m: Person, _ cur: Currency) -> some View {
        let q = engine.managerQuality(companyID: company.id)
        let auth = company.value("auth")
        let lvl = Int(auth["lvl"].double)
        let notice = company.value("mgrNotice")
        let bd = engine.tradeInfo(companyID: company.id)
        let started = company.value("mgrW0").isNull ? 0 : company.int("mgrW0")
        let months = max(0, engine.state.week - started) / 4
        LedgerSection(title: bd.map { ManagerModel.title($0) } ?? "Manager", trailing: {
            Text("\(months) month\(months == 1 ? "" : "s") in the job").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("Age \(m.age) · \(String(format: "%g", m.num("exp"))) years of experience").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(cur.short(company.managerMonthlyWage)).font(.system(size: 15).monospacedDigit()).foregroundStyle(Theme.ivory)
                        Text("a month").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                if !notice.isNull {
                    Text("\(m.name.split(separator: " ").first.map(String.init) ?? "The manager") leaves on \(GameCalendar.dateString(week: notice["w"].int, dayOffset: 0)). Hire a successor before then and they will hand over.")
                        .font(.system(size: 12)).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                }
                if !notice.isNull { SuccessorSection(engine: engine, company: company) }
                RateBar(label: "Overall results", fraction: q)
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
                Hairline()
                Text("Decides").capsLabel(Theme.ivoryFaint)
                SectionTabs(items: [0, 1, 2], title: { ["Asks you", "Within limits", "Full control"][$0] }, selection: Binding(get: { lvl }, set: { v in
                    store.act { $0.setManagerAuthority(companyID: company.id, level: v) }
                })).padding(.horizontal, -Theme.Space.margin)
                Text(["Every decision and spend comes to you as a message.", "Handles things up to the limits you set; bigger things come to you.", "Decides everything on their own."][min(2, max(0, lvl))])
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                if lvl == 1 {
                    limitRow("Pay and promotions a month", auth["hire"].double, [0, 3000, 8000, 15000, 30000], cur) { v in store.act { $0.setManagerAuthority(companyID: company.id, pay: v) } }
                    limitRow("Purchases and hires up to", auth["buy"].double, [10000, 25000, 50000, 100000, 250000], cur) { v in store.act { $0.setManagerAuthority(companyID: company.id, buy: v) } }
                    limitRow("Advertising a week", auth["ad"].double, [0, 1500, 3000, 7000], cur) { v in store.act { $0.setManagerAuthority(companyID: company.id, ad: v) } }
                }
                HStack(spacing: 16) {
                    Button("Give raise") { store.act { $0.giveManagerRaise(companyID: company.id) }; store.show("Raise given.", tone: "good"); Haptics.success() }
                    Button("Meet") {
                        let ok = store.act { $0.meetManager(companyID: company.id) } ?? false
                        store.show(ok ? "You met. Their news is in Messages." : "You met recently. Give it a few weeks.", tone: ok ? "good" : "n")
                    }
                    Menu("Ask for…") {
                        ForEach(Array(ManagerModel.askOptions.enumerated()), id: \.offset) { _, o in
                            Button(o.label) { store.act { $0.askManager(companyID: company.id, key: o.key) }; store.show("Asked. The answer is in Messages.", tone: "n") }
                        }
                    }
                    let free = engine.state.companies.filter { $0.id != company.id && $0.managerID == nil && $0.status.isLive && $0.type != "hold" }
                    if !free.isEmpty {
                        Menu("Move to…") {
                            ForEach(free) { c in
                                Button(c.name) {
                                    let ok = store.act { $0.moveManager(from: company.id, to: c.id) } ?? false
                                    store.show(ok ? "\(m.name) now manages \(c.name)." : "Could not move them.", tone: ok ? "good" : "warn")
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Replace") { confirmDismiss = true }.foregroundStyle(Theme.loss)
                }
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
            }
        }
    }

    private func limitRow(_ label: String, _ value: Double, _ options: [Double], _ cur: Currency, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { o in Button(o == 0 ? "None" : cur.short(cur.scaledPrice(o))) { set(cur.scaledPrice(o)) } }
            } label: { Text(value == 0 ? "None" : cur.short(value)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.gold) }
        }
    }

    // MARK: Hiring a manager

    @ViewBuilder private func hireManager(_ cur: Currency) -> some View {
        let title = engine.tradeInfo(companyID: company.id).map { ManagerModel.title($0) } ?? "Manager"
        LedgerSection("Hire a \(title.lowercased())") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runs \(company.name) day to day: hires, prices, stock, and keeps the team up. You set what they may decide, and you step back from the work. They are not cheap, and a manager nobody checks on slowly slips.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                Button("Executive search · \(cur.short(cur.scaledPrice(15000)))") {
                    if let list = store.act({ $0.searchManagers(companyID: company.id) }) ?? nil { candidates = list.map { $0.id }; Haptics.tap() }
                    else { store.show("Not enough cash for the search.", tone: "warn") }
                }.buttonStyle(QuietButtonStyle())
                ForEach(Array(candidates.enumerated()), id: \.element) { n, id in
                    if let p = engine.state.people[id] {
                        if n > 0 { Hairline() }
                        candidate(p, cur)
                    }
                }
            }
        }
    }

    @ViewBuilder private func candidate(_ p: Person, _ cur: Currency) -> some View {
        let q = p.value("q")
        let left = p.value("qLeft").isNull ? 3 : p.int("qLeft")
        let checked = p.flag("ref")
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text("Age \(p.age) · \(String(format: "%g", p.num("exp"))) yr · \(ManagerModel.typeTitles[p.str("mtype")] ?? "Manager")").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer(minLength: 8)
                Text(cur.short(p.askingMonthlyWage) + " / mo").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
            Text(p.str("resume")).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
            ForEach(Array(ManagerModel.skillKeys.enumerated()), id: \.offset) { _, k in
                if checked {
                    Text("\(k.label): really \(band(p.value("stats")[k.key].double))").font(.system(size: 11.5)).foregroundStyle(Theme.ivory)
                } else if !q[k.key].isNull {
                    Text("\(k.label): says \(band(q[k.key].double))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
                }
            }
            HStack(spacing: 16) {
                Menu("Ask (\(left) left)") {
                    ForEach(Array(ManagerModel.skillKeys.enumerated()), id: \.offset) { _, k in
                        Button(k.label) { store.act { $0.interviewManager(personID: p.id, skill: k.key) } }.disabled(left <= 0 && q[k.key].isNull)
                    }
                }
                if !checked { Button("References · \(cur.short(cur.scaledPrice(2500)))") {
                    let ok = store.act { $0.checkManagerReferences(personID: p.id, companyID: company.id) } ?? false
                    if !ok { store.show("Not enough cash.", tone: "warn") }
                } }
                Spacer(minLength: 0)
                Menu("Hire") {
                    ForEach([1.0, 1.1, 1.25], id: \.self) { f in
                        Button("\(cur.short(cur.roundedStep(p.askingMonthlyWage * f, about: 500))) a month") { offer(p, cur.roundedStep(p.askingMonthlyWage * f, about: 500)) }
                    }
                }.foregroundStyle(Theme.gold)
            }
            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
        }.padding(.vertical, 6)
    }

    private func offer(_ p: Person, _ wage: Double) {
        let r = store.act { $0.hireManager(personID: p.id, companyID: company.id, monthlyWage: wage) }
        switch r {
        case .ok?: Haptics.success(); candidates = []; store.show("\(p.name) now runs \(company.name).", tone: "good")
        case .refused?: store.show("\(p.name) declined. Offer more.", tone: "warn")
        case .taken?: store.show("They took another job.", tone: "warn")
        default: store.show("Could not hire.", tone: "warn")
        }
    }

    // MARK: The assistant

    @ViewBuilder private func assistant(_ cur: Currency) -> some View {
        let a = company.value("asst")
        if a["npc"].int != 0, let n = engine.state.people[a["npc"].int] {
            LedgerSection(title: "Assistant manager", trailing: { Text("\(a["duties"].array.count) of 2 jobs").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                            Text("Works a full week and takes jobs off \(company.managerID == nil ? "your" : "the manager's") plate").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        Text(cur.short(a["wage"].double)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                    }.padding(.vertical, 8)
                    ForEach(Array(ManagerModel.assistantDuties.enumerated()), id: \.offset) { _, d in
                        Hairline()
                        let on = a["duties"].array.contains { $0.string == d.key }
                        Button {
                            let ok = store.act { $0.toggleAssistantDuty(companyID: company.id, duty: d.key) } ?? false
                            if !ok { store.show("Two jobs at most. Untick one first.", tone: "warn") }
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
                    Hairline()
                    Button("Let go") { confirmDismissAssistant = true }
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.loss).buttonStyle(.plain).padding(.top, 8)
                }
            }
        } else {
            LedgerSection("Assistant manager") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Works alongside the team and takes up to two jobs off \(company.managerID == nil ? "your" : "the manager's") plate: complaints, paperwork, equipment. Paid more than a worker, less than a manager. They advise; you decide.")
                        .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    Button("Job ad · \(cur.short(cur.scaledPrice(2500)))") {
                        if let list = store.act({ $0.searchAssistants(companyID: company.id) }) ?? nil { assistants = list.map { $0.id }; Haptics.tap() }
                        else { store.show("Not enough cash for the job ad.", tone: "warn") }
                    }.buttonStyle(QuietButtonStyle())
                    ForEach(Array(assistants.enumerated()), id: \.element) { n, id in
                        if let p = engine.state.people[id] {
                            if n > 0 { Hairline() }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                                    Text("Age \(p.age) · \(String(format: "%g", p.num("exp"))) yr · \(p.str("resume"))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                Menu("\(cur.short(p.askingMonthlyWage)) / mo") {
                                    ForEach([1.0, 1.1], id: \.self) { f in
                                        Button("Offer \(cur.short(cur.roundedStep(p.askingMonthlyWage * f, about: 500)))") { hireAssistant(p, cur.roundedStep(p.askingMonthlyWage * f, about: 500)) }
                                    }
                                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    private func hireAssistant(_ p: Person, _ wage: Double) {
        switch store.act({ $0.hireAssistant(personID: p.id, companyID: company.id, monthlyWage: wage) }) {
        case .ok?: Haptics.success(); assistants = []; store.show("\(p.name) is your assistant manager. Pick their two jobs.", tone: "good")
        case .refused?: store.show("\(p.name) found that a bit low.", tone: "warn")
        default: store.show("They took another job.", tone: "warn")
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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("Promote \(name)").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ivory)
                LedgerSection("Promote to") {
                    VStack(spacing: 0) {
                        if posts.isEmpty { Text("No higher post fits right now.").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                        ForEach(Array(posts.enumerated()), id: \.element.id) { n, p in
                            if n > 0 { Hairline() }
                            Button { post = p; offer = p.ask; reply = "" } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                        Text("\(p.place) · will ask about \(cur.short(p.ask)) a month").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
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
                            Text("Now \(cur.short(member.monthlyWage)) a month.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                            HStack(spacing: 12) {
                                ForEach([0.9, 1.0, 1.1], id: \.self) { f in
                                    Button("\(Int(f * 100))% · \(cur.short(cur.roundedStep(post.ask * f, about: 500)))") { offer = cur.roundedStep(post.ask * f, about: 500) }
                                        .buttonStyle(QuietButtonStyle())
                                }
                            }
                            AmountField(title: "Monthly salary", currency: cur, amount: $offer)
                            Button("Send offer · \(cur.short(offer))") { send(post, cur) }.buttonStyle(GoldButtonStyle())
                            if !reply.isEmpty { Text(reply).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }
            .padding(Theme.Space.margin)
        }
        .ledgerBackground()
    }

    private func send(_ post: ManagerModel.PromotionPost, _ cur: Currency) {
        let r = store.act { $0.offerPromotion(companyID: company.id, personID: member.id, post: post.id, monthlyWage: offer) }
        switch r {
        case .accepted(let text)?: Haptics.success(); store.show(text, tone: "good"); dismiss()
        case .counter(let want, let text)?: reply = text; offer = want; Haptics.tap()
        case .tooLow(let text)?: reply = text; Haptics.warning()
        case .declinedForGood(let text)?: reply = text; store.show(text, tone: "warn"); dismiss()
        case .unavailable(let text)?: reply = text
        case nil: break
        }
    }
}
