import SwiftUI
import GameCore
import Businesses
import Simulation

/// The group's main office (rent a place, hire the people who work for the whole group, check their references, do their paperwork),
/// the reviews of your managers, a meeting with all managers, and the suppliers you know. One section of the Group tab; the rules are
/// in `Headquarters`, `OfficeChecks`, `ManagerModel` and `Suppliers`.
struct HeadOfficeSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var searchRole: String?
    @State private var candidates: [Int] = []
    @State private var references: [Int: OfficeChecks.Reference] = [:]
    @State private var goal = "review"
    @State private var tone = "casual"
    @State private var pending: PendingAction?
    @State private var allReviews = false
    @State private var report: [ManagerModel.AnalystLine] = []

    var body: some View {
        let tier = engine.officeTier
        let staff = engine.officeStaff
        LedgerSection(title: "Main office", trailing: { Text(tier?.name ?? "None").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier?.name ?? "No main office").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text(tier.map { "\(staff.count) of \($0.desks) desks · \(store.short(engine.officeRent(tier: $0))) a month" } ?? "Rent one to hire people who work for the whole group.")
                            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    Menu(tier == nil ? "Rent" : "Move") {
                        ForEach(engine.officeTiers) { t in
                            Button("\(t.name) · \(store.short(engine.officeRent(tier: t))) a month · \(t.desks) desks") { confirmRent(t, moving: tier != nil) }
                        }
                    }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                }.padding(.vertical, 8)
                if tier != nil {
                    ForEach(Array(staff.enumerated()), id: \.offset) { _, x in
                        Hairline()
                        staffRow(x)
                    }
                    ForEach(engine.officeRoles.filter { r in !staff.contains { $0["role"].string == r.id } }) { r in
                        Hairline()
                        roleRow(r)
                    }
                }
                if let rh = engine.rightHand { Hairline(); rightHand(rh) }
                if engine.state.hasHeadOffice("ana") { Hairline(); analyst }
                if tier != nil { Hairline(); reviews }
                if engine.state.companies.contains(where: { $0.status.isLive && $0.managerID != nil }) { Hairline(); dueMeetings; Hairline(); meeting }
            }
        }
        .confirmAction($pending)
        SuppliersGroupSection(engine: engine)
    }

    // MARK: Office and staff

    private func confirmRent(_ t: Headquarters.Tier, moving: Bool) {
        let cost = engine.officeRent(tier: t)
        pending = PendingAction(title: moving ? "Move to \(t.name)?" : "Rent \(t.name)?",
                                message: "\(store.short(cost)) a month for \(t.desks) desks, paid by a holding with spare cash or by you." + (moving ? " Moving costs the first month now as a deposit; your office staff move with you." : " The people who work there are hired one by one after that."),
                                button: moving ? "Move" : "Rent") { rent(t) }
    }

    private func rent(_ t: Headquarters.Tier) {
        switch store.act({ $0.rentOffice(tier: t.id) }) {
        case .ok?: Haptics.success(); store.show("\(t.name) rented.", tone: "good")
        case .desks?: store.show("Too many people for that office.", tone: "warn")
        case .notEnoughCash?: store.show("Not enough cash for the deposit.", tone: "warn")
        default: store.show("That office is not available.", tone: "warn")
        }
    }

    @ViewBuilder private func staffRow(_ x: JSONValue) -> some View {
        let id = x["id"].int
        let open = engine.officePaperwork(personID: id).filter { !$0.done }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(x["name"].string).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text(engine.officeRoles.first { $0.id == x["role"].string }?.title ?? x["role"].string).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    let does = engine.officeRoleResult(role: x["role"].string)
                    if !does.isEmpty { Text(does).font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                Text(store.short(x["wage"].double)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
            HStack(spacing: 16) {
                if !open.isEmpty {
                    Button("Paperwork done (\(open.count))") { for p in open { store.act { $0.tickOfficePaperwork(personID: id, item: p.key) } }; Haptics.success() }
                }
                Spacer(minLength: 0)
                Button("Let go") {
                    let name = x["name"].string
                    pending = PendingAction(title: "Let \(name) go?", message: "What they do for the group stops at once. " + engine.officeRoleResult(role: x["role"].string), button: "Let go", destructive: true) {
                        store.act { $0.fireOffice(personID: id) }; Haptics.warning(); store.show("\(name) has left the main office.")
                    }
                }.foregroundStyle(Theme.loss)
            }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
        }.padding(.vertical, 8)
    }

    @ViewBuilder private func roleRow(_ r: Headquarters.Role) -> some View {
        let room = engine.officeRoom(role: r.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text(room == .locked ? "Opens with " + Headquarters.unlockText(r.id) : r.text).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if room == .ok {
                    Menu("Find") {
                        Button("Ask around (free)") { search(r.id, .network) }
                        Button("Job ad") { search(r.id, .ad) }
                        Button("Agency (checked)") { search(r.id, .agency) }
                    }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                } else if room == .desks {
                    Text("No free desk").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
                }
            }
            if searchRole == r.id {
                ForEach(candidates, id: \.self) { id in
                    if let p = engine.state.people[id] { candidate(p, role: r) }
                }
            }
        }.padding(.vertical, 8)
    }

    private func search(_ role: String, _ mode: Headquarters.SearchMode) {
        if let list = store.act({ $0.searchOffice(role: role, mode: mode) }) ?? nil {
            searchRole = role; candidates = list.map { $0.id }; references = [:]; Haptics.tap()
            if list.isEmpty { store.show("No one suitable answered.") }
        } else {
            store.show(mode == .network ? "You asked around recently. Try again in a few weeks." : "Not enough cash for the search.", tone: "warn")
        }
    }

    @ViewBuilder private func candidate(_ p: Person, role: Headquarters.Role) -> some View {
        let ref = references[p.id] ?? (p.flag("checked") ? OfficeChecks.reference(p) : nil)
        CandidateHireRow(person: p, currency: engine.homeCurrency, subtitle: "Age \(p.age) · says \(StaffProfile.band(p.claimedSkill).lowercased())",
                         market: engine.goingRate(for: .office(role: role.id)), factors: [0.9, 1.0, 1.15, 1.3],
                         offer: { wage in hire(role, p, wage) }) {
            if let ref {
                Text("References: really \(ref.skillBand.lowercased()), \(String(format: "%g", ref.experience)) yr" + (ref.matchesCV ? ". Matches the CV." : ". The CV does not match."))
                    .font(.system(size: 11)).foregroundStyle(ref.matchesCV ? Theme.gain : Theme.caution)
            } else {
                Button("Check references") { checkReferences(p) }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
            }
        }
    }

    private func checkReferences(_ p: Person) {
        switch store.act({ $0.referenceCheckCandidate(personID: p.id) }) {
        case .ok(let ref)?: references[p.id] = ref; Haptics.success()
        case .notEnoughCash?: store.show("Not enough cash.", tone: "warn")
        default: store.show("They are no longer available.", tone: "warn")
        }
    }

    /// The engine's answer in the words every hiring screen uses; the shared row shows it under the candidate.
    private func hire(_ role: Headquarters.Role, _ p: Person, _ wage: Double) -> HireFeedback {
        let feedback = HireFeedback.from(store.act { $0.hireOffice(role: role.id, personID: p.id, monthlyWage: wage) }, name: p.name, role: role.title)
        if feedback.isHired { candidates = []; searchRole = nil }
        store.show(feedback.text, tone: feedback.isHired ? "good" : "warn")
        return feedback
    }

    // MARK: Manager reviews

    @ViewBuilder private var reviews: some View {
        let managed = engine.state.companies.filter { ($0.status == .open || $0.status == .closed) && $0.managerID != nil }
        let analyst = engine.state.hasHeadOffice("perf")
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Manager reviews").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                Spacer()
                if analyst && !managed.isEmpty { Button("Review all") { store.act { $0.runManagerScorecards() }; Haptics.success() }.buttonStyle(QuietButtonStyle(tint: Theme.gold)) }
            }
            if managed.isEmpty { Text("No company has a manager yet.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            else if !analyst { Text("Without a performance analyst each review is an external one and costs money.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            else {
                Toggle(isOn: Binding(get: { autoScorecards }, set: { v in store.act { $0.setPerformanceAnalystAuto(v) }; store.show(v ? "Scorecards arrive every month." : "Scorecards only when you ask.") })) {
                    Text("Scorecards every month").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                }.tint(Theme.gold)
            }
            // Never-reviewed and weakest first; with many managers only the ones that need a look, the rest on request.
            let ordered = managed.sorted { score($0) < score($1) }
            let shown: [Company] = allReviews ? ordered : Array(ordered.filter { score($0) < 50 }.prefix(6))
            if !allReviews && shown.isEmpty && !managed.isEmpty { Text("Every reviewed manager scores acceptable or better.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            ForEach(shown) { co in
                let last = co.value("lastRev")
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(co.name).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                        Text(last.isNull ? "Not reviewed yet" : "\(verdict(last["score"].int)) · \(last["score"].int) of 100 · week \(last["w"].int)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer()
                    Button("Review now") { review(co) }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                }
            }
            if managed.count > shown.count || allReviews {
                Button(allReviews ? "Show only the weak ones" : "Show all \(managed.count) managers") { allReviews.toggle() }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
            }
        }.padding(.vertical, 8)
    }

    private func score(_ co: Company) -> Int { co.value("lastRev").isNull ? -1 : co.value("lastRev")["score"].int }
    private var autoScorecards: Bool { let v = engine.state.rest["office"]?["perfAuto"] ?? .null; return v.isNull ? true : v.bool }

    // MARK: Your right hand

    @ViewBuilder private func rightHand(_ rh: Headquarters.RightHand) -> some View {
        let name = engine.state.people[rh.personID]?.name ?? "Your assistant"
        VStack(alignment: .leading, spacing: 6) {
            Text("Right hand · \(name)").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
            Text(rh.decidesForYou ? "Decides small matters for you and sits on every board." : "Brings everything to you and sits on every board.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            HStack(spacing: 16) {
                Button(rh.decidesForYou ? "Stop deciding for me" : "Let them decide") {
                    if rh.decidesForYou {
                        store.act { $0.setRightHand(decidesForYou: false) }; store.show("Everything comes to you again.")
                    } else {
                        pending = PendingAction(title: "Let \(name) decide for you?", message: "Benefit: fewer small decisions reach you. Risk: they choose by their own judgement, and a choice you would have made differently still stands. You can switch this off at any time.", button: "Let them decide") {
                            store.act { $0.setRightHand(decidesForYou: true) }; Haptics.success(); store.show("\(name) decides small matters.", tone: "good")
                        }
                    }
                }
                Menu("Briefing: \(["week": "weekly", "month": "monthly", "off": "none"][rh.briefing] ?? rh.briefing)") {
                    ForEach([("week", "Every week"), ("month", "Every month"), ("off", "None")], id: \.0) { k, label in
                        Button(label) { store.act { $0.setRightHand(briefing: k) }; store.show("Briefing set: \(label.lowercased()).") }
                    }
                }
                Spacer(minLength: 0)
            }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
        }.padding(.vertical, 8)
    }

    // MARK: The data analyst's report

    @ViewBuilder private var analyst: some View {
        let open = engine.state.companies.filter { $0.status == .open && $0.type != "hold" }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Data analyst's report").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text("Sales trend, capacity, the weakest link and an outlook. A copy goes to the Inbox.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Menu("Ask") {
                    Button("All companies") { askReport(nil) }
                    ForEach(open) { c in Button(c.name) { askReport(c.id) } }
                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
            }
            ForEach(Array(report.prefix(8).enumerated()), id: \.offset) { _, l in
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(l.lines.isEmpty ? "Too early to say." : l.lines.joined(separator: " ")).font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 4)
            }
            if report.count > 8 { Text("The full report on \(report.count) companies is in the Inbox.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
        }.padding(.vertical, 8)
    }

    private func askReport(_ companyID: Int?) {
        let r: [ManagerModel.AnalystLine]? = store.act { $0.requestAnalystReport(companyID: companyID) } ?? nil
        if let r { report = r; Haptics.success(); store.show("The report is in. A copy is in the Inbox.", tone: "good") }
        else { store.show("No open company to report on, or the analyst has left.", tone: "warn") }
    }

    // MARK: Managers nobody has met

    @ViewBuilder private var dueMeetings: some View {
        let due = engine.managersDueMeeting.filter { $0.status == .open }
        VStack(alignment: .leading, spacing: 6) {
            Text("Managers due a meeting").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
            Text(due.isEmpty ? "You have met every manager in the last eight weeks." : "A manager left alone slowly works worse. A meeting resets that, lifts their mood and brings their proposals to your Inbox.")
                .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            ForEach(due.prefix(8)) { co in
                HStack {
                    NavigationLink(value: CompanyRoute.companyAt(co.id, .staff)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(co.name).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                            Text("\(co.managerID.flatMap { engine.state.people[$0]?.name } ?? "Manager") · last met \(engine.weeksSinceMeeting(companyID: co.id)) weeks ago").font(.system(size: 11)).foregroundStyle(Theme.caution)
                        }
                    }.buttonStyle(.plain)
                    Spacer()
                    Button("Meet for proposals") { meetForProposals(co) }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                }
            }
            if due.count > 8 { Text("And \(due.count - 8) more. The meeting with all managers below reaches them all at once.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
        }.padding(.vertical, 8)
    }

    private func meetForProposals(_ co: Company) {
        let n: Int? = store.act { $0.meetForProposals(companyID: co.id) } ?? nil
        if let n {
            Haptics.success()
            store.show(n == 0 ? "You met. \(co.name) runs well; nothing to change." : "You met. \(n) \(n == 1 ? "proposal is" : "proposals are") in your Inbox.", tone: "good")
        } else {
            store.show("You met this manager in the last three weeks, or the company has no manager.", tone: "warn")
        }
    }

    private func verdict(_ s: Int) -> String { s >= 80 ? "Excellent" : s >= 65 ? "Good" : s >= 50 ? "Acceptable" : s >= 35 ? "Weak" : "Poor" }

    private func review(_ co: Company) {
        switch store.act({ $0.reviewManagerNow(companyID: co.id) }) {
        case .ok(let card)?: Haptics.success(); store.show("\(co.name): \(verdict(card.score)), \(card.score) of 100.")
        case .notEnoughCash?: store.show("Not enough cash for an external review.", tone: "warn")
        default: store.show("This company has no manager.", tone: "warn")
        }
    }

    // MARK: A meeting with all managers

    @ViewBuilder private var meeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Call a meeting with all managers").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
            HStack {
                Menu(engine.meetingGoals.first { $0.key == goal }?.label ?? "Topic") {
                    ForEach(engine.meetingGoals, id: \.key) { g in Button(g.label) { goal = g.key } }
                }
                Menu(engine.meetingTones.first { $0.key == tone }?.label ?? "Tone") {
                    ForEach(engine.meetingTones, id: \.key) { t in Button(t.label) { tone = t.key } }
                }
                Spacer()
                Button("Call") {
                    switch store.act({ $0.callMeeting(companyID: nil, goal: goal, tone: tone) }) {
                    case .ok(let n)?: Haptics.success(); store.show("You met \(n) manager\(n == 1 ? "" : "s").", tone: "good")
                    case .wait?: store.show("You met them all recently. Give it a few weeks.", tone: "warn")
                    default: store.show("No manager to meet.", tone: "warn")
                    }
                }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
            }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
        }.padding(.vertical, 8)
    }
}

/// The people you buy from, known across your companies: a lunch to get to know them (a better relationship is a better discount on every order)
/// and an agreement with the board to buy through one of them for every company.
struct SuppliersGroupSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let known = engine.knownSuppliers
        if !known.isEmpty {
            LedgerSection(title: "People you buy from", trailing: { Text("\(known.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(known.enumerated()), id: \.element.id) { n, v in
                        if n > 0 { Hairline() }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(v.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                    Text("\(v.owner) · \(v.relationshipWord)" + (v.discount > 0 ? " · \(Int((v.discount * 100).rounded()))% off every order" : " · same price as everyone"))
                                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                Text(String(format: "%.1f ★", v.rating)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                            }
                            HStack(spacing: 16) {
                                Button("Take to lunch") {
                                    switch store.act({ $0.lunchWithSupplier(vendorID: v.id) }) {
                                    case .ok?: Haptics.success(); store.show("A good lunch.", tone: "good")
                                    case .wait?: store.show("You met recently.", tone: "warn")
                                    case .cash?: store.show("Not enough cash.", tone: "warn")
                                    default: break
                                    }
                                }
                                if engine.state.liveCompanies.count >= 2 {
                                    let current = engine.boardAgreement(scope: "goods") == v.id
                                    Button(current ? "End the goods deal" : "Buy goods through them for all") { agree(current ? nil : v.id) }
                                }
                                Spacer(minLength: 0)
                            }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func agree(_ vendorID: String?) {
        switch store.act({ $0.agreeSupplierDeal(scope: "goods", vendorID: vendorID) }) {
        case .ok?: Haptics.success(); store.show(vendorID == nil ? "The agreement is ended." : "Agreed with the board. Every company gets their discount.", tone: "good")
        case .cash?: store.show("Not enough cash for the board dinner.", tone: "warn")
        case .fewCompanies?: store.show("You need two companies for a group deal.", tone: "warn")
        default: break
        }
    }
}
