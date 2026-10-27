import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Manager targets and the yearly budget (Company > Team). Shows cost, benefit and risk before the targets are set.
struct CompanyTargetsCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var mode = 1
    @State private var bonus = 1
    @State private var confirm = false

    private static let names = ["rev": "Sales", "profit": "Profit", "rating": "Rating", "util": "How busy", "aware": "Awareness"]
    private func value(_ key: String, _ v: Double, _ cur: Currency) -> String { key == "rev" || key == "profit" ? cur.tidyShort(v) : String(format: "%.0f", v) }

    var body: some View {
        if let st = engine.targetStatus(companyID: company.id) {
            let cur = engine.currency(for: company)
            TeamCardGroup(title: "Targets and budget", trailing: { Text(st.setter.isOwner ? "set by you" : "set by \(st.setter.title.lowercased())").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 10) {
                    if st.standing.isEmpty {
                        Text("No targets this month yet.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                    }
                    ForEach(Array(st.standing.enumerated()), id: \.offset) { n, s in
                        if n > 0 { Hairline() }
                        HStack(alignment: .firstTextBaseline) {
                            Text(Self.names[s.key] ?? s.key).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Spacer(minLength: 8)
                            Text("\(value(s.key, s.now, cur)) of \(value(s.key, s.target, cur))").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(s.onTrack ? Theme.gain : Theme.caution)
                        }
                    }
                    if let b = st.budget {
                        Hairline()
                        Text("Budget \(b.year)\(b.by.isEmpty ? "" : " · drafted by \(b.by)")").capsLabel(Theme.ivoryFaint)
                        FlatRow(label: "Sales", value: "\(cur.tidyShort(b.doneRev)) of \(cur.tidyShort(b.rev))", rule: false)
                        FlatRow(label: "Profit", value: "\(cur.tidyShort(b.doneProfit)) of \(cur.tidyShort(b.profit))", tint: b.doneProfit < 0 ? Theme.loss : Theme.ivory)
                        if b.approved {
                            Text("Approved.").font(.system(size: 11.5)).foregroundStyle(Theme.gain)
                        } else {
                            Text("Waiting for your approval. Approving makes these the numbers the manager is judged on this year; you can still change targets each month.")
                                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                            Button("Approve the budget") {
                                if store.act({ $0.approveBudget(companyID: company.id) }) == true { Haptics.success(); store.show("Budget \(b.year) approved: sales \(cur.tidyShort(b.rev)), profit \(cur.tidyShort(b.profit)).", tone: "good") }
                                else { Haptics.warning(); store.show("The budget could not be approved now.", tone: "warn") }
                            }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    if !st.log.isEmpty {
                        Hairline()
                        Text("Last months").capsLabel(Theme.ivoryFaint)
                        ForEach(Array(st.log.reversed().enumerated()), id: \.offset) { _, l in
                            HStack {
                                Text("\(l.met) of 3 met").font(.system(size: 12.5)).foregroundStyle(l.met == 3 ? Theme.gain : l.met == 0 ? Theme.loss : Theme.ivoryMuted)
                                Spacer()
                                Text(l.bonus > 0 ? "bonus \(cur.tidyShort(l.bonus))" : "no bonus").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                            }
                        }
                    }
                    if st.canSet, let pv = engine.targetPreview(companyID: company.id, mode: mode) {
                        Hairline()
                        Text("Set this month's targets").capsLabel(Theme.ivoryFaint)
                        SectionTabs(items: [0, 1, 2], title: { ["Easy", "Realistic", "Stretch"][$0] }, selection: $mode).padding(.horizontal, -Theme.Space.margin)
                        ForEach(Array(pv.rows.enumerated()), id: \.offset) { _, r in
                            HStack {
                                Text(Self.names[r.key] ?? r.key).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                                Spacer()
                                Text(value(r.key, r.target, cur)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                            }
                        }
                        if pv.hasManager {
                            Text("Bonus for the manager").capsLabel(Theme.ivoryFaint).padding(.top, 4)
                            SectionTabs(items: [0, 1, 2], title: { ManagerTargets.bonusLevels[$0].name }, selection: $bonus).padding(.horizontal, -Theme.Space.margin)
                        }
                        let perTarget = pv.hasManager ? pv.bonusPerTarget[min(2, max(0, bonus))] : 0
                        let costLine = pv.hasManager ? (perTarget > 0 ? "\(cur.tidyShort(perTarget)) for each target met, up to \(cur.tidyShort(perTarget * 3)) a month." : "no bonus is paid.") : "none, you run it yourself."
                        let benefitLine = mode == 2 ? "a stretch pushes for the most, and a manager with a bonus works to it." : mode == 0 ? "easy numbers are usually met, so the bonus is nearly always earned." : "a fair aim based on the last year and the market."
                        let riskLine = mode == 2 ? "stretch targets are often missed, and a manager who misses again and again can lose heart." : mode == 0 ? "you may pay bonuses for what would have happened anyway." : "a bad month still misses them."
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Cost: " + costLine)
                            Text("Benefit: " + benefitLine + " This also approves the year's budget.")
                            Text("Risk: " + riskLine)
                        }.font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                        Button("Set targets…") { confirm = true }.buttonStyle(QuietButtonStyle())
                    } else if !st.canSet && !st.setter.isOwner {
                        Text("\(st.setter.name) sets the targets here.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            .onAppear { bonus = min(2, max(0, st.bonusLevel)) }
            .confirmationDialog("Set the targets for this month?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Set targets") {
                    if store.act({ $0.setTargets(companyID: company.id, mode: mode, bonus: bonus) }) == true { Haptics.success(); store.show("Targets set.", tone: "good") }
                    else { Haptics.warning(); store.show("Targets cannot be set now.", tone: "warn") }
                }
            } message: {
                let cur = engine.currency(for: company)
                let perTarget = engine.targetPreview(companyID: company.id, mode: mode).map { $0.hasManager ? $0.bonusPerTarget[min(2, max(0, bonus))] : 0 } ?? 0
                Text((perTarget > 0 ? "Bonus up to \(cur.tidyDisplay(perTarget * 3)) a month if all three are met. " : "No bonus is paid. ") + "The year's budget is confirmed with them.")
            }
        }
    }
}

/// Staff perks (Company > Team): each shows its monthly cost and what it does before it is switched on.
struct CompanyPerksCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: StaffPerks.Perk?
    @State private var pendingGroup: (perk: StaffPerks.Perk, group: StaffPerks.RoleGroup)?

    private func recipientLine(_ r: CompanyCarPerk.Recipient, _ cur: Currency) -> String {
        let role = r.role == "Manager" ? "manager" : "team lead"
        guard let car = r.carName else { return "\(r.name) · \(role) · car arrives next week" }
        return "\(r.name) · \(role) · \(car), lease \(cur.tidyShort(r.monthlyLease)) a month"
    }

    private func fewer(_ p: StaffPerks.Perk) -> Int { Int(((1 - p.quitFactor) * 100).rounded()) }

    var body: some View {
        if !company.staff.isEmpty || company.managerID != nil {
            let cur = engine.currency(for: company)
            let total = engine.staffPerksMonthlyTotal(companyID: company.id)
            TeamCardGroup(title: "Perks", trailing: { Text(total > 0 ? "\(cur.tidyShort(total)) a month" : "none yet").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(engine.staffPerkOptions.enumerated()), id: \.element.id) { n, p in
                        let on = engine.staffPerkIsOn(companyID: company.id, perk: p.id)
                        if n > 0 { Hairline() }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(p.detail.tidyMoney).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                Text("\(cur.tidyShort(engine.staffPerkMonthlyCost(companyID: company.id, perk: p.id))) a month · \(fewer(p))% fewer leave among those it covers").font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
                                groupChoices(p, cur)
                                if p.id == "car" && on {
                                    ForEach(engine.companyCarRecipients(companyID: company.id)) { r in
                                        Text(recipientLine(r, cur)).font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
                                    }
                                }
                            }
                            Spacer(minLength: 8)
                            Button(on ? "On · switch off" : "Add…") {
                                if on { let r = store.act { $0.toggleStaffPerk(companyID: company.id, perk: p.id) } ?? nil; Haptics.tap(); store.show(r == nil ? "Not possible right now." : "\(p.name) switched off.", tone: r == nil ? "warn" : "n") } else { pending = p }
                            }.buttonStyle(QuietButtonStyle(tint: on ? Theme.gain : Theme.gold))
                        }.padding(.vertical, 9)
                    }
                    let together = engine.staffPerksFewerLeavePercent(companyID: company.id)
                    if together > 0 { Text("Together \(Int(together.rounded()))% fewer people leave.").font(.caption2).foregroundStyle(Theme.gain).padding(.top, 6) }
                }
            }
            .confirmationDialog(pendingGroup.map { "Add \($0.perk.name.lowercased()) for \($0.group.name.lowercased())?" } ?? "", isPresented: Binding(get: { pendingGroup != nil }, set: { if !$0 { pendingGroup = nil } }), titleVisibility: .visible) {
                if let pg = pendingGroup {
                    Button("Add for \(cur.tidyShort(engine.staffPerkMonthlyCost(companyID: company.id, perk: pg.perk.id, group: pg.group.id))) a month") {
                        let r = store.act { $0.toggleStaffPerk(companyID: company.id, perk: pg.perk.id, group: pg.group.id) } ?? nil
                        if r == true { Haptics.success(); store.show("\(pg.perk.name) added for \(pg.group.name.lowercased()).", tone: "good") } else { Haptics.warning(); store.show("Not possible right now.", tone: "warn") }
                        pendingGroup = nil
                    }
                }
            } message: {
                if let pg = pendingGroup {
                    Text("Cost: paid every month for \(engine.staffPerkPeople(companyID: company.id, group: pg.group.id)) people in this group while it is on. Benefit: they leave about \(fewer(pg.perk))% less, and better applicants come for their jobs. Risk: a fixed cost in a bad month. Switch it off at any time.")
                }
            }
            .confirmationDialog(pending.map { "Add \($0.name.lowercased())?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let p = pending {
                    Button("Add for \(cur.tidyShort(engine.staffPerkMonthlyCost(companyID: company.id, perk: p.id))) a month") {
                        let r = store.act { $0.toggleStaffPerk(companyID: company.id, perk: p.id) } ?? nil
                        if r == true { Haptics.success(); store.show("\(p.name) added.", tone: "good") } else { Haptics.warning(); store.show("Not possible right now.", tone: "warn") }
                        pending = nil
                    }
                }
            } message: {
                if let p = pending, p.id == "car" {
                    Text("Cost: a leased car for the manager and for each team lead; the lease and the fuel are paid every month while it is on, and the cars show in the fleet. Benefit: \(fewer(p))% fewer people leave and better applicants come. Risk: cars are a fixed cost in a bad month. Switch it off and the cars go back.")
                } else if let p = pending {
                    Text("Cost: paid every month while it is on. Benefit: \(fewer(p))% fewer people leave and better applicants come. Risk: it is a fixed cost in a bad month. Switch it off at any time.")
                }
            }
        }
    }
}

extension CompanyPerksCard {
    /// Who a perk is for: one chip per role group it may be given to (only where there is a choice), each switching it on or off for that group.
    @ViewBuilder func groupChoices(_ p: StaffPerks.Perk, _ cur: Currency) -> some View {
        let groups = engine.staffPerkGroups(perk: p.id)
        if groups.count > 1 {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(groups) { g in
                    let covered = engine.staffPerkCovers(companyID: company.id, perk: p.id, group: g.id)
                    let people = engine.staffPerkPeople(companyID: company.id, group: g.id)
                    Button("\(g.name) (\(people))\(covered ? " · on" : "")") {
                        if covered { let r = store.act { $0.toggleStaffPerk(companyID: company.id, perk: p.id, group: g.id) } ?? nil; Haptics.tap(); if r == nil { store.show("Not possible right now.", tone: "warn") } }
                        else if people > 0 { pendingGroup = (p, g) }
                        else { store.show("Nobody is in this group at \(company.name) yet.", tone: "n") }
                    }.buttonStyle(QuietButtonStyle(tint: covered ? Theme.gain : Theme.ivoryMuted))
                }
            }.padding(.top, 3)
        }
    }
}

/// Shown under the manager's notice: pay for the executive search for a successor and hire one of the candidates.
struct SuccessorSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var confirm = false

    var body: some View {
        let cur = engine.currency(for: company)
        let waiting = engine.successorCandidates(companyID: company.id)
        VStack(alignment: .leading, spacing: 8) {
            if waiting.isEmpty {
                Button("Find a successor · \(cur.tidyShort(ManagerModel.searchFee(currency: cur)))…") { confirm = true }.buttonStyle(QuietButtonStyle())
                Text("Cost: the executive search fee. Benefit: four candidates to choose from before the handover, so the company is not left without a manager. Risk: none may suit, and the fee is not refunded.")
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                CandidateHireList(people: waiting.filter { $0.employerID == 0 }, emptyText: "Everyone on the list has taken another job. Search again.") { p in
                    CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(engine, p), market: engine.goingRate(for: .manager, companyID: company.id), factors: [0.9, 1.0, 1.15, 1.3], offer: { wage in
                        let fb = HireFeedback.from(store.act { $0.hireManager(personID: p.id, companyID: company.id, monthlyWage: wage) }, name: p.name, company: company.name)
                        if fb.isHired { store.show(fb.text, tone: "good") }
                        return fb
                    }) { ManagerCandidateChecks(person: p, companyID: company.id, currency: cur) }
                }
            }
        }
        .confirmationDialog("Start the search?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Pay \(cur.tidyShort(ManagerModel.searchFee(currency: cur))) and search") {
                if let list = store.act({ $0.findSuccessor(companyID: company.id) }) ?? nil, !list.isEmpty { Haptics.success(); store.show("\(list.count) candidates found. Search paid: \(cur.tidyShort(ManagerModel.searchFee(currency: cur))).", tone: "good") }
                else { Haptics.warning(); store.show("The search found no one, or the company cannot pay \(cur.tidyShort(ManagerModel.searchFee(currency: cur))).", tone: "warn") }
            }
        } message: { Text("Three people from the trade and one generalist. The list stays for about six months.") }
    }
}
