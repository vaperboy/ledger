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
    private func value(_ key: String, _ v: Double, _ cur: Currency) -> String { key == "rev" || key == "profit" ? cur.short(v) : String(format: "%.0f", v) }

    var body: some View {
        if let st = engine.targetStatus(companyID: company.id) {
            let cur = engine.currency(for: company)
            LedgerSection(title: "Targets and budget", trailing: { Text(st.setter.isOwner ? "set by you" : "set by \(st.setter.title.lowercased())").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 10) {
                    if st.standing.isEmpty {
                        Text("No targets this month yet.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
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
                        FlatRow(label: "Sales", value: "\(cur.short(b.doneRev)) of \(cur.short(b.rev))", rule: false)
                        FlatRow(label: "Profit", value: "\(cur.short(b.doneProfit)) of \(cur.short(b.profit))", tint: b.doneProfit < 0 ? Theme.loss : Theme.ivory)
                        if b.approved {
                            Text("Approved.").font(.system(size: 11.5)).foregroundStyle(Theme.gain)
                        } else {
                            Text("Waiting for your approval. Approving makes these the numbers the manager is judged on this year; you can still change targets each month.")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                            Button("Approve the budget") {
                                if store.act({ $0.approveBudget(companyID: company.id) }) == true { Haptics.success(); store.show("Budget approved.", tone: "good") }
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
                                Text(l.bonus > 0 ? "bonus \(cur.short(l.bonus))" : "no bonus").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
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
                        let costLine = pv.hasManager ? (perTarget > 0 ? "\(cur.short(perTarget)) for each target met, up to \(cur.short(perTarget * 3)) a month." : "no bonus is paid.") : "none, you run it yourself."
                        let benefitLine = mode == 2 ? "a stretch pushes for the most, and a manager with a bonus works to it." : mode == 0 ? "easy numbers are usually met, so the bonus is nearly always earned." : "a fair aim based on the last year and the market."
                        let riskLine = mode == 2 ? "stretch targets are often missed, and a manager who misses again and again can lose heart." : mode == 0 ? "you may pay bonuses for what would have happened anyway." : "a bad month still misses them."
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Cost: " + costLine)
                            Text("Benefit: " + benefitLine + " This also approves the year's budget.")
                            Text("Risk: " + riskLine)
                        }.font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                        Button("Set targets") { confirm = true }.buttonStyle(GoldButtonStyle())
                    } else if !st.canSet && !st.setter.isOwner {
                        Text("\(st.setter.name) sets the targets here.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            .onAppear { bonus = min(2, max(0, st.bonusLevel)) }
            .confirmationDialog("Set the targets for this month?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Set targets") {
                    if store.act({ $0.setTargets(companyID: company.id, mode: mode, bonus: bonus) }) == true { Haptics.success(); store.show("Targets set.", tone: "good") }
                    else { store.show("Not possible now.", tone: "warn") }
                }
            } message: { Text("The bonus level and the year's budget are confirmed with them.") }
        }
    }
}

/// Staff perks (Company > Team): each shows its monthly cost and what it does before it is switched on.
struct CompanyPerksCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: StaffPerks.Perk?

    private func fewer(_ p: StaffPerks.Perk) -> Int { Int(((1 - p.quitFactor) * 100).rounded()) }

    var body: some View {
        if !company.staff.isEmpty || company.managerID != nil {
            let cur = engine.currency(for: company)
            let total = engine.staffPerksMonthlyTotal(companyID: company.id)
            LedgerSection(title: "Perks", trailing: { Text(total > 0 ? "\(cur.short(total)) a month" : "none yet").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(engine.staffPerkOptions.enumerated()), id: \.element.id) { n, p in
                        let on = engine.staffPerkIsOn(companyID: company.id, perk: p.id)
                        if n > 0 { Hairline() }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(p.detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                Text("\(cur.short(engine.staffPerkMonthlyCost(companyID: company.id, perk: p.id))) a month · \(fewer(p))% fewer leave").font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
                            }
                            Spacer(minLength: 8)
                            Button(on ? "On" : "Add") {
                                if on { store.act { $0.toggleStaffPerk(companyID: company.id, perk: p.id) }; Haptics.tap() } else { pending = p }
                            }.buttonStyle(QuietButtonStyle(tint: on ? Theme.gain : Theme.gold))
                        }.padding(.vertical, 9)
                    }
                    let together = engine.staffPerksFewerLeavePercent(companyID: company.id)
                    if together > 0 { Text("Together \(Int(together.rounded()))% fewer people leave.").font(.caption2).foregroundStyle(Theme.gain).padding(.top, 6) }
                }
            }
            .confirmationDialog(pending.map { "Add \($0.name.lowercased())?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let p = pending {
                    Button("Add for \(cur.short(engine.staffPerkMonthlyCost(companyID: company.id, perk: p.id))) a month") {
                        store.act { $0.toggleStaffPerk(companyID: company.id, perk: p.id) }; Haptics.success(); pending = nil
                    }
                }
            } message: {
                if let p = pending {
                    Text("Cost: paid every month while it is on. Benefit: \(fewer(p))% fewer people leave and better applicants come. Risk: it is a fixed cost in a bad month. Switch it off at any time.")
                }
            }
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
                Button("Find a successor · \(cur.short(cur.scaledPrice(15000)))") { confirm = true }.buttonStyle(QuietButtonStyle())
                Text("Cost: the executive search fee. Benefit: four candidates to choose from before the handover, so the company is not left without a manager. Risk: none may suit, and the fee is not refunded.")
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Candidates").capsLabel(Theme.ivoryFaint)
                ForEach(Array(waiting.enumerated()), id: \.element.id) { n, p in
                    if n > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                            Text("Age \(p.age) · \(String(format: "%g", p.num("exp"))) yr · \(p.str("resume"))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        Menu("\(cur.short(p.askingMonthlyWage)) / mo") {
                            ForEach([1.0, 1.1], id: \.self) { f in
                                Button("Offer \(cur.short(cur.roundedStep(p.askingMonthlyWage * f, about: 500)))") { hire(p, cur.roundedStep(p.askingMonthlyWage * f, about: 500)) }
                            }
                        }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                    }
                }
            }
        }
        .confirmationDialog("Start the search?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Pay \(cur.short(cur.scaledPrice(15000))) and search") {
                if let list = store.act({ $0.findSuccessor(companyID: company.id) }) ?? nil, !list.isEmpty { Haptics.success() }
                else { store.show("Not enough cash for the search.", tone: "warn") }
            }
        } message: { Text("Three people from the trade and one generalist. The list stays for about six months.") }
    }

    private func hire(_ p: Person, _ wage: Double) {
        switch store.act({ $0.hireManager(personID: p.id, companyID: company.id, monthlyWage: wage) }) {
        case .ok?: Haptics.success(); store.show("\(p.name) now runs \(company.name).", tone: "good")
        case .refused?: store.show("\(p.name) declined. Offer more.", tone: "warn")
        default: store.show("They took another job.", tone: "warn")
        }
    }
}
