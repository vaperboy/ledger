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
                            Button("\(t.name) · \(store.short(engine.officeRent(tier: t))) a month · \(t.desks) desks") { rent(t) }
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
                if tier != nil { Hairline(); reviews }
                if engine.state.companies.contains(where: { $0.status.isLive && $0.managerID != nil }) { Hairline(); meeting }
            }
        }
        SuppliersGroupSection(engine: engine)
    }

    // MARK: Office and staff

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
                }
                Spacer(minLength: 8)
                Text(store.short(x["wage"].double)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
            HStack(spacing: 16) {
                if !open.isEmpty {
                    Button("Paperwork done (\(open.count))") { for p in open { store.act { $0.tickOfficePaperwork(personID: id, item: p.key) } }; Haptics.success() }
                }
                Spacer(minLength: 0)
                Button("Let go") { store.act { $0.fireOffice(personID: id) }; Haptics.warning() }.foregroundStyle(Theme.loss)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text("Age \(p.age) · says \(StaffProfile.band(p.claimedSkill).lowercased())").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    if let ref {
                        Text("References: really \(ref.skillBand.lowercased()), \(String(format: "%g", ref.experience)) yr" + (ref.matchesCV ? ". Matches the CV." : ". The CV does not match."))
                            .font(.system(size: 11)).foregroundStyle(ref.matchesCV ? Theme.gain : Theme.caution)
                    }
                }
                Spacer(minLength: 8)
                Menu(store.short(p.askingMonthlyWage) + " / mo") {
                    ForEach([1.0, 1.1], id: \.self) { f in Button("Offer \(store.short(p.askingMonthlyWage * f))") { hire(role, p, p.askingMonthlyWage * f) } }
                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
            }
            if ref == nil {
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

    private func hire(_ role: Headquarters.Role, _ p: Person, _ wage: Double) {
        switch store.act({ $0.hireOffice(role: role.id, personID: p.id, monthlyWage: wage) }) {
        case .ok?: Haptics.success(); candidates = []; searchRole = nil; store.show("\(p.name) joins as \(role.title.lowercased()). Complete the paperwork.", tone: "good")
        case .refuse?: store.show("\(p.name) found that a bit low.", tone: "warn")
        case .taken?: store.show("They took another job.", tone: "warn")
        default: store.show("There is no room for that role.", tone: "warn")
        }
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
            ForEach(managed) { co in
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
        }.padding(.vertical, 8)
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
