import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var role = ""
    @State private var candidates: [Person] = []
    @State private var confirmFire: StaffMember?
    @State private var promoting: StaffMember?

    /// Who handles day-to-day staffing here (the engine's decision chain), so an owner change is a deliberate override.
    @ViewBuilder private var delegation: some View {
        let chain = engine.decisionChain(companyID: company.id)
        if let boss = chain.first {
            let title = GameEngine.bossTitle(boss.kind, trade: engine.tradeInfo(companyID: company.id)).lowercased()
            let lvl = ["asks you before deciding", "decides within your limits", "decides on their own"][min(2, max(0, boss.level))]
            Text("\(boss.name), \(title), runs the team day to day and \(lvl). Anything you change here overrides them; problems they cannot solve reach you in Team.")
                .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if company.status == .open {
            Text(company.ownerHours > 0 ? "You run this team yourself. A manager takes the day-to-day off you once the company is big enough to need one." : "No one runs this team: you do not work here and there is no manager.")
                .font(.system(size: 12)).foregroundStyle(company.ownerHours > 0 ? Theme.ivoryMuted : Theme.caution).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(spacing: Theme.Space.l) {
            delegation
            CompanyManagement(engine: engine, company: company)
            CompanyTeamRoster(engine: engine, company: company)
            CompanyTargetsCard(engine: engine, company: company)
            CompanyPerksCard(engine: engine, company: company)
            CompanyLabourCard(engine: engine, company: company)
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack {
                        SectionLabel("Team")
                        Spacer()
                        Chip(text: "\(company.staff.count) \(company.staff.count == 1 ? "person" : "people") · \(cur.short(company.staff.reduce(0) { $0 + $1.monthlyWage })) a month", tint: Theme.ivoryMuted)
                    }
                    if company.staff.isEmpty { Text(company.ownerHours > 0 ? "No one works here but you." : "No one works here.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                    ForEach(company.staff) { m in
                        let missing = StaffExtras.missing(m)
                        HStack(alignment: .center, spacing: Theme.Space.m) {
                            IconBadge(symbol: "person.fill", tint: m.sickUntilWeek != nil ? Theme.loss : Theme.ivoryMuted, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.state.people[m.id]?.name ?? roleName(m.role)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(roleName(m.role)).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                    if m.sickUntilWeek != nil { Text("· off sick").font(.caption).foregroundStyle(Theme.loss) }
                                    if m.tiredness > 60 { Text("· tired").font(.caption).foregroundStyle(Theme.caution) }
                                    if !missing.isEmpty { Text("· \(missing.count) papers missing").font(.caption).foregroundStyle(Theme.caution) }
                                }
                            }
                            Spacer(minLength: 6)
                            Text(cur.short(m.monthlyWage)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ivory)
                            Menu {
                                Button("Raise pay 5%") { store.act { $0.raise(personID: m.id, companyID: company.id, percent: 0.05) }; Haptics.tap() }
                                if !missing.isEmpty { Button("Paperwork done (\(missing.count))") { store.act { $0.completePaperwork(companyID: company.id, personID: m.id) }; Haptics.success() } }
                                StaffContractMenu(engine: engine, company: company, member: m)
                                Button("Promote…") { promoting = m }
                                Button("Written warning") { warn(m) }
                                if !engine.courses(companyID: company.id).isEmpty {
                                    Menu("Send on a course") {
                                        ForEach(engine.courses(companyID: company.id)) { c in
                                            Button("\(c.name) · \(cur.short(engine.courseCost(c, companyID: company.id)))") { sendOnCourse(m, c) }
                                        }
                                    }
                                }
                                Button("Let go…", role: .destructive) { confirmFire = m }
                            } label: {
                                Image(systemName: "ellipsis").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ivoryMuted).frame(width: 32, height: 32).contentShape(Rectangle())
                            }
                        }
                    }
                    if company.staff.count > 1 {
                        HStack {
                            Text("Cutting costs").font(.caption).foregroundStyle(Theme.ivoryFaint)
                            Spacer()
                            Menu("Lay off the weakest") {
                                ForEach([1, 2, 3].filter { $0 < company.staff.count }, id: \.self) { n in
                                    let p = engine.layoffPreview(companyID: company.id, count: n)
                                    Button("\(n) · saves \(cur.short(p.savesPerMonth)) a month, severance \(cur.short(p.severance))") { layOff(n) }
                                }
                            }.font(.caption.weight(.semibold)).foregroundStyle(Theme.loss)
                        }
                    }
                    let papers = company.staff.reduce(0) { $0 + StaffExtras.missing($1).count }
                    if papers > 0 {
                        HStack {
                            Text("\(papers) paperwork item\(papers == 1 ? "" : "s") missing. An inspection can fine you.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                            Spacer()
                            Button("Do all") { for m in company.staff { store.act { $0.completePaperwork(companyID: company.id, personID: m.id) } }; Haptics.success() }
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.gold).buttonStyle(.plain)
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Find workers")
                    let roles = engine.hireableRoles(companyID: company.id)
                    if roles.isEmpty { Text("This trade has no staff roles.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                    else {
                        SectionTabs(items: roles, title: { roleName($0) }, selection: $role).padding(.horizontal, -Theme.Space.margin)
                        HStack {
                            Button("Job ad") { search(.ads) }.buttonStyle(QuietButtonStyle())
                            Button("Network") { search(.network) }.buttonStyle(QuietButtonStyle())
                            Button("Agency") { search(.agency) }.buttonStyle(QuietButtonStyle())
                        }
                        Text("Ads are cheap and slow, the agency is quick and expensive; better people take better searches.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        if role == "mktan" {
                            let v = engine.marketAnalystVerdict(companyID: company.id)
                            Text(v.title + ". " + v.text).font(.caption).foregroundStyle(v.ok ? Theme.ivoryMuted : Theme.caution)
                        }
                    }
                    ForEach(candidates) { p in
                        HStack(spacing: Theme.Space.m) {
                            IconBadge(symbol: "person.crop.circle.badge.plus", tint: Theme.ivoryMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.bodyText.weight(.medium))
                                Text("Says \(Int(p.claimedSkill.rounded())) skill · age \(p.age)").font(.caption).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer()
                            Button(cur.short(p.askingMonthlyWage) + " / mo") { hire(p) }.buttonStyle(QuietButtonStyle())
                            HireOptionsMenu(engine: engine, company: company, person: p) { candidates.removeAll { $0.id == p.id } }
                        }
                    }
                }
            }
        }
        .sheet(item: $promoting) { m in PromotionSheet(engine: engine, company: company, member: m).environmentObject(store) }
        .onAppear { if role.isEmpty { role = engine.hireableRoles(companyID: company.id).first ?? "" } }
        .confirmationDialog("Let this person go?", isPresented: Binding(get: { confirmFire != nil }, set: { if !$0 { confirmFire = nil } }), presenting: confirmFire) { m in
            Button("Let go", role: .destructive) {
                let severance = store.act { $0.fire(personID: m.id, companyID: company.id) } ?? 0
                store.show(severance > 0 ? "Severance paid: \(cur.display(severance))" : "Done.", tone: "n")
                Haptics.warning()
            }
        } message: { _ in Text("Notice periods and severance may apply.") }
    }

    private func warn(_ m: StaffMember) {
        let worked = store.act { $0.warnStaff(companyID: company.id, staffID: m.id) } ?? nil
        let name = engine.state.people[m.id]?.name ?? "They"
        store.show(worked == true ? "The warning worked. \(name) has improved." : "Warning on file for \(name).", tone: worked == true ? "good" : "n")
        Haptics.tap()
    }

    private func sendOnCourse(_ m: StaffMember, _ c: Academy.Course) {
        let r: Academy.Outcome? = store.act { $0.sendOnCourse(companyID: company.id, staffID: m.id, courseID: c.id) }
        switch r {
        case .done(let message, _, let poached)?: Haptics.success(); store.show(poached ? "\(message). A competitor poached them." : message, tone: poached ? "warn" : "good")
        case .notEnoughCash?: store.show("Not enough cash for the course.", tone: "warn")
        case .unavailable?, nil: store.show("That course is not available.", tone: "warn")
        }
    }

    private func layOff(_ n: Int) {
        let ids = store.act { $0.layOffStaff(companyID: company.id, count: n) } ?? []
        Haptics.warning()
        store.show(ids.isEmpty ? "No one was let go." : "\(ids.count) \(ids.count == 1 ? "person" : "people") let go. The rest are shaken.", tone: "n")
    }

    private func search(_ mode: Hiring.SearchMode) {
        guard !role.isEmpty else { return }
        candidates = store.act { $0.searchWorkers(companyID: company.id, role: role, mode: mode) } ?? []
        Haptics.tap()
        if candidates.isEmpty { store.show("No one suitable answered.", tone: "n") }
    }

    private func hire(_ p: Person) {
        let r = store.act { $0.hire(personID: p.id, companyID: company.id, monthlyWage: p.askingMonthlyWage) }
        switch r {
        case .ok?: Haptics.success(); candidates.removeAll { $0.id == p.id }; store.show("\(p.name) has joined.", tone: "good")
        case .taken?: store.show("They took another job.", tone: "warn")
        default: store.show("Could not hire.", tone: "warn")
        }
    }

    private func roleName(_ id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }
}
