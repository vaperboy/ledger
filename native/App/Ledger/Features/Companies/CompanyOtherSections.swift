import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Small flat sections of a company that belong to no bigger screen: customer complaints, developing something new, giving up the
/// premises, changing the accountant. Placed at the end of Operations. Ivory Ledger rows, no boxes.
struct CompanyOtherSections: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            complaints
            development
            premises
            accountant
        }
    }

    // MARK: Complaints

    @ViewBuilder private var complaints: some View {
        let open = engine.openComplaints(companyID: company.id)
        if !open.isEmpty {
            LedgerSection(title: "Complaints", trailing: { Text("answer within two weeks").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                ForEach(Array(open.enumerated()), id: \.offset) { n, c in
                    VStack(alignment: .leading, spacing: 6) {
                        if n > 0 { Hairline() }
                        Text(c["who"].string).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("\u{201C}\(c["t"].string)\u{201D}").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        HStack {
                            Button("Refund") { answer(c, .refund) }
                            Button("Apologise") { answer(c, .sorry) }
                            Button("Ignore") { answer(c, .ignore) }
                        }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }
    }

    private func answer(_ c: JSONValue, _ a: Satisfaction.Answer) {
        let r = store.act { $0.answerComplaint(companyID: company.id, complaintID: c["id"].int, answer: a) }
        switch (a, r ?? nil) {
        case (.refund, _): store.show("Refunded. The customer is satisfied.", tone: "good")
        case (.sorry, true?): store.show("They accepted the apology.", tone: "good")
        case (.sorry, _): store.show("They are still unhappy.", tone: "warn")
        default: store.show("Ignored. Expect a bad review.", tone: "warn")
        }
    }

    // MARK: Development

    @ViewBuilder private var development: some View {
        let list = engine.developmentProjects(companyID: company.id)
        if !list.isEmpty, company.status == .open {
            let cur = engine.currency(for: company)
            let run = Development.running(company)
            LedgerSection(title: "Develop something new", trailing: {
                if let run { Text("\(max(0, run.weeksLeft - engine.state.week)) weeks to go").font(.system(size: 11)).foregroundStyle(Theme.caution) }
            }) {
                if let run, let p = list.first(where: { $0.project.id == run.project }) {
                    FlatRow(label: p.project.name, value: cur.short(run.cost), sub: "Spent. The team's skill and your quality decide how well it works.", rule: false)
                } else {
                    ForEach(Array(list.enumerated()), id: \.offset) { n, x in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x.project.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text("\(x.project.text) · \(x.project.weeks) weeks · \(cur.short(x.cost))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Button("Start") { start(x.project) }.buttonStyle(QuietButtonStyle())
                        }
                        if n < list.count - 1 { Hairline() }
                    }
                }
                let live = Development.finished(company)
                if !live.isEmpty {
                    Text("Working now: " + live.map { "\($0["n"].string) (\(Int(($0["mag"].double * 100).rounded()))%)" }.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func start(_ p: Development.Project) {
        switch store.act({ $0.startDevelopment(companyID: company.id, project: p.id) }) {
        case .ok?: Haptics.success(); store.show("Development started.", tone: "good")
        case .notEnoughCash?: store.show("Not enough cash in the company.", tone: "warn")
        case .busy?: store.show("One project at a time.", tone: "warn")
        default: store.show("Not possible right now.", tone: "warn")
        }
    }

    // MARK: Premises and accountant

    @ViewBuilder private var premises: some View {
        let prem = company.value("prem")
        if company.status == .open, engine.tradeInfo(companyID: company.id)?.premisesKind == "home", prem["m2"].double > 0 {
            LedgerSection("Premises") {
                HStack {
                    Text(prem["owned"].bool ? "You own this place" : "Rented place").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Spacer()
                    Button("Work from home again") {
                        if store.act({ $0.giveUpPremises(companyID: company.id) }) == true { Haptics.success(); store.show("Everyone works from home again.", tone: "n") }
                    }.buttonStyle(QuietButtonStyle())
                }
                Text(prem["owned"].bool ? "The building is sold at today's value and the mortgage paid off." : "The deposit comes back.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    @ViewBuilder private var accountant: some View {
        let choices = engine.accountantChoices(companyID: company.id)
        if choices.count > 1, company.status.isLive {
            let cur = engine.currency(for: company)
            LedgerSection("Accountant") {
                ForEach(Array(choices.enumerated()), id: \.offset) { n, a in
                    if n > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text("\(cur.short(a.fee)) a month · rated \(String(format: "%.1f", a.rating))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        if a.current { Chip(text: "Yours", tint: Theme.gain) }
                        else { Button("Hire") { if store.act({ $0.changeAccountant(companyID: company.id, accountantID: a.id) }) == true { store.show("Accountant hired.", tone: "good") } }.buttonStyle(QuietButtonStyle()) }
                    }
                }
            }
        }
    }
}

/// The ways of employing one person, in the menu of a staff member: hours, part time, seasons, fixed salary, own car, pay model.
struct StaffContractMenu: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var member: StaffMember

    var body: some View {
        let id = company.id, sid = member.id
        let part = member.weeklyHours != nil
        let seasonal = !member.value("seas").isNull
        if part {
            Menu("Hours a week") {
                ForEach([10.0, 20, 30, 40, 50], id: \.self) { h in
                    Button("\(Int(h)) h") { report(store.act { $0.setStaffHours(companyID: id, staffID: sid, hours: h) }) }
                }
            }
            Button("Offer full time") { report(store.act { $0.offerFullTime(companyID: id, staffID: sid) }, want: "full") }
        }
        if seasonal {
            Menu("Seasons") {
                ForEach(StaffTalks.seasons, id: \.id) { s in
                    Button((s.months.allSatisfy { member.value("seas").array.map { $0.int }.contains($0) } ? "On: " : "Off: ") + s.name) {
                        store.act { $0.toggleSeason(companyID: id, staffID: sid, season: s.id) }
                    }
                }
            }
            Button("Offer part time all year") { report(store.act { $0.offerPartTime(companyID: id, staffID: sid) }, want: "season") }
        }
        if !part, member.payBasis == "hour" {
            Button("Offer a fixed salary") { store.act { $0.offerFixedSalary(companyID: id, staffID: sid) }; store.show("Now on a fixed salary.", tone: "good") }
        }
        if member.role == "estate" {
            Button(member.num("ownCar") != 0 ? "Give a company car" : "Own car and mileage") { store.act { $0.toggleOwnCar(companyID: id, staffID: sid) } }
        }
        if engine.salesRoles.contains(member.role) {
            Menu("Pay model") {
                Button("Fixed salary") { payModel("fix") }
                Button("Salary and commission") { payModel("mix") }
                Button("Commission only") { payModel("com") }
                if member.commissionMode != nil && member.commissionMode != "fix" {
                    ForEach([0.02, 0.03, 0.05, 0.08, 0.12], id: \.self) { r in
                        Button("Commission \(Int(r * 100))%") { store.act { $0.setCommissionRate(companyID: id, staffID: sid, rate: r) } }
                    }
                }
            }
        }
    }

    private func payModel(_ m: String) {
        if store.act({ $0.setPayModel(companyID: company.id, staffID: member.id, mode: m) }) == .resigned {
            store.show("They will not work on commission only and resign.", tone: "bad")
        } else { store.show("Pay model changed.", tone: "n") }
    }

    private func report(_ r: StaffTalks.OfferResult?, want: String = "full") {
        switch r {
        case .ok?: store.show("They said yes.", tone: "good")
        case .refused?, .student?: store.show(engine.refusalReason(companyID: company.id, staffID: member.id, want: want), tone: "warn")
        default: break
        }
    }
}

/// How to hire a candidate: full time, part time, seasonal for the busy months, or after a paid trial week.
struct HireOptionsMenu: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var person: Person
    var onHired: () -> Void

    var body: some View {
        Menu {
            Button("Full time") { hire(Hiring.Terms()) }
            Button("Part time, 20 h") { hire(Hiring.Terms(hours: 20)) }
            Button("Seasonal, busy months") { hire(Hiring.Terms(hours: 25, seasonMonths: busy)) }
            if person.role == "estate" { Button("Full time, own car") { hire(Hiring.Terms(ownCar: true)) } }
            Button("Paid trial week") {
                if let seen = store.act({ $0.startTrialWeek(personID: person.id, companyID: company.id) }) ?? nil {
                    store.show("After a week their work looks like \(Int(seen)) skill.", tone: "n")
                } else { store.show("Could not arrange a trial week.", tone: "warn") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ivoryMuted).frame(width: 32, height: 32).contentShape(Rectangle())
        }
    }

    private var busy: [Int] { let m = engine.busyMonths(companyID: company.id); return m.isEmpty ? [6, 7, 8] : m }

    private func hire(_ t: Hiring.Terms) {
        switch store.act({ $0.hire(personID: person.id, companyID: company.id, monthlyWage: person.askingMonthlyWage, terms: t) }) {
        case .ok?: Haptics.success(); onHired(); store.show("\(person.name) has joined.", tone: "good")
        case .taken?: store.show("They took another job.", tone: "warn")
        default: store.show("They declined that offer.", tone: "warn")
        }
    }
}

/// Places in a chain that are short of a role, with a sister store that has one to spare.
struct ChainStaffShortages: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var chainID: Int

    var body: some View {
        let list = engine.staffShortages(chainID: chainID)
        if !list.isEmpty {
            LedgerSection("Short of staff") {
                ForEach(Array(list.prefix(6).enumerated()), id: \.offset) { n, x in
                    if n > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(engine.state.company(x.storeID)?.name ?? "Store").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text("Needs a \(x.role)" + (x.spareAtStoreID.flatMap { engine.state.company($0)?.name }.map { " · \($0) has one spare" } ?? "")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        if let from = x.spareAtStoreID {
                            Button("Move one") { if store.act({ $0.lendWorker(from: from, to: x.storeID, role: x.role) }) == true { Haptics.success() } }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
        }
    }
}
