import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

// Three people actions of Company > Team, each grouped by its purpose and each with its own layout:
//   Goals      (CompanyTargetsCard)  what the manager is judged on: month targets as progress bars, the year's budget, a history strip, and a setter.
//   Rewards    (CompanyPerksCard)    what keeps people: a cost summary and one card per perk.
//   Succession (SuccessorSection)    what happens when the manager leaves: the search and the shortlist.
// Every card says what an action costs, what it gains and what it risks before it is confirmed. The engine decides all of it.

/// The head of a purpose card: a round icon, a serif title and one grey line on what the card is for.
private struct PurposeHeader: View {
    var glyph: String
    var title: String
    var note: String = ""
    var tint: Color = Theme.gold

    var body: some View {
        HStack(spacing: 12) {
            IconCircle(glyph: glyph, size: 36, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.serifTitle(17)).foregroundStyle(Theme.ivory)
                if !note.isEmpty { Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Cost, benefit and risk of an action as three short lines, each with its own mark. Shown before the button that commits.
private struct ConsequenceNote: View {
    var cost: String
    var benefit: String
    var risk: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            line(Glyph.cost, "Cost", cost, Theme.ivoryMuted)
            line(Glyph.market, "Benefit", benefit, Theme.gain)
            line(Glyph.warning, "Risk", risk, Theme.caution)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.divider, lineWidth: 1))
    }

    private func line(_ glyph: String, _ label: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(glyph: glyph, size: 14, weight: 1.6, tint: tint).padding(.top, 1)
            (Text(label + "  ").font(.system(size: 11.5, weight: .semibold)).foregroundColor(tint)
             + Text(text).font(.system(size: 11.5)).foregroundColor(Theme.ivoryMuted))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Goals: targets and the budget

/// Manager targets and the yearly budget (Company > Team). Shows cost, benefit and risk before the targets are set.
struct CompanyTargetsCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var mode = 1
    @State private var bonus = 1
    @State private var confirm = false

    private static let names = ["rev": "Sales", "profit": "Profit", "rating": "Rating", "util": "How busy", "aware": "Awareness"]
    private static let modeNames = ["Easy", "Realistic", "Stretch"]
    private func value(_ key: String, _ v: Double, _ cur: Currency) -> String { key == "rev" || key == "profit" ? cur.tidyShort(v) : String(format: "%.0f", v) }
    private func share(_ now: Double, _ target: Double) -> Double { target > 0 ? min(1, max(0, now / target)) : 0 }

    var body: some View {
        if let st = engine.targetStatus(companyID: company.id) {
            let cur = engine.currency(for: company)
            TeamGroup(title: "Goals", trailing: {
                Text(st.setter.isOwner ? "set by you" : "set by \(st.setter.title.lowercased())").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                monthCard(st, cur)
                budgetCard(st, cur)
                historyCard(st, cur)
                setterCard(st, cur)
            }
            .onAppear { bonus = min(2, max(0, st.bonusLevel)) }
            .confirmationDialog("Set the targets for this month?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Set targets") {
                    if store.act({ $0.setTargets(companyID: company.id, mode: mode, bonus: bonus) }) == true { Haptics.success(); store.show("Targets set.", tone: "good") }
                    else { Haptics.warning(); store.show("Targets cannot be set now.", tone: "warn") }
                }
            } message: {
                Text(confirmMessage(cur))
            }
        }
    }

    private func confirmMessage(_ cur: Currency) -> String {
        let perTarget: Double = engine.targetPreview(companyID: company.id, mode: mode).map { $0.hasManager ? $0.bonusPerTarget[min(2, max(0, bonus))] : 0 } ?? 0
        return (perTarget > 0 ? "Bonus up to \(cur.tidyDisplay(perTarget * 3)) a month if all three are met. " : "No bonus is paid. ") + "The year's budget is confirmed with them."
    }

    // This month: one bar per target.
    private func monthCard(_ st: ManagerTargets.Status, _ cur: Currency) -> some View {
        Card(padding: 14, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 12) {
                PurposeHeader(glyph: Glyph.goals, title: "This month", note: "Where each target stands")
                if st.standing.isEmpty {
                    Text("No targets this month yet.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                }
                ForEach(st.standing, id: \.key) { s in standingRow(s, cur) }
            }
        }
    }

    private func standingRow(_ s: ManagerTargets.Standing, _ cur: Currency) -> some View {
        let tint: Color = s.onTrack ? Theme.gain : Theme.caution
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.names[s.key] ?? s.key).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                Spacer(minLength: 8)
                Text("\(value(s.key, s.now, cur)) of \(value(s.key, s.target, cur))").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(tint)
                GlyphView(glyph: s.onTrack ? Glyph.check : Glyph.clock, size: 13, weight: 1.8, tint: tint)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(tint).frame(width: max(3, g.size.width * CGFloat(share(s.now, s.target))))
                }
            }.frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    // The year's budget.
    @ViewBuilder private func budgetCard(_ st: ManagerTargets.Status, _ cur: Currency) -> some View {
        if let b = st.budget {
            Card(padding: 14, radius: Theme.Radius.card) {
                VStack(alignment: .leading, spacing: 12) {
                    PurposeHeader(glyph: Glyph.reports, title: "Budget \(b.year)", note: b.by.isEmpty ? "The year's aim" : "Drafted by \(b.by)")
                    RateBar(label: "Sales", fraction: share(b.doneRev, b.rev))
                    Text("\(cur.tidyShort(b.doneRev)) of \(cur.tidyShort(b.rev))").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                    RateBar(label: "Profit", fraction: share(b.doneProfit, b.profit), tint: b.doneProfit < 0 ? Theme.loss : Theme.gold)
                    Text("\(cur.tidyShort(b.doneProfit)) of \(cur.tidyShort(b.profit))").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(b.doneProfit < 0 ? Theme.loss : Theme.ivoryFaint)
                    if b.approved {
                        HStack(spacing: 6) {
                            GlyphView(glyph: Glyph.check, size: 13, weight: 1.8, tint: Theme.gain)
                            Text("Approved").font(.system(size: 12)).foregroundStyle(Theme.gain)
                        }
                    } else {
                        approval(b, cur)
                    }
                }
            }
        }
    }

    private func approval(_ b: ManagerTargets.Status.Budget, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLine()
            Text("Waiting for your approval. Approving makes these the numbers the manager is judged on this year; you can still change targets each month.")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Approve the budget") {
                if store.act({ $0.approveBudget(companyID: company.id) }) == true { Haptics.success(); store.show("Budget \(b.year) approved: sales \(cur.tidyShort(b.rev)), profit \(cur.tidyShort(b.profit)).", tone: "good") }
                else { Haptics.warning(); store.show("The budget could not be approved now.", tone: "warn") }
            }
        }
    }

    // Past months: three pips each, filled for every target met.
    @ViewBuilder private func historyCard(_ st: ManagerTargets.Status, _ cur: Currency) -> some View {
        if !st.log.isEmpty {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 10) {
                    PurposeHeader(glyph: Glyph.calendar, title: "Last months", note: "Targets met each month, oldest first")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 10) {
                        ForEach(Array(st.log.enumerated()), id: \.offset) { _, l in monthPips(l, cur) }
                    }
                }
            }
        }
    }

    private func monthPips(_ l: ManagerTargets.Status.LogLine, _ cur: Currency) -> some View {
        let tint: Color = l.met == 3 ? Theme.gain : l.met == 0 ? Theme.loss : Theme.caution
        return VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i < l.met ? tint : Theme.hairline).frame(width: 12, height: 18)
                }
            }
            Text("\(l.met) of 3").font(.system(size: 10.5)).foregroundStyle(tint)
            Text(l.bonus > 0 ? cur.tidyShort(l.bonus) : "no bonus").font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.ivoryFaint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // Setting the month's targets.
    @ViewBuilder private func setterCard(_ st: ManagerTargets.Status, _ cur: Currency) -> some View {
        if st.canSet, let pv = engine.targetPreview(companyID: company.id, mode: mode) {
            Card(padding: 14, radius: Theme.Radius.card) {
                VStack(alignment: .leading, spacing: 12) {
                    PurposeHeader(glyph: Glyph.arrowOut, title: "Set this month's targets", note: "How hard to push")
                    modeChoices
                    previewTable(pv, cur)
                    if pv.hasManager {
                        Text("Bonus for the manager").capsLabel(Theme.ivoryFaint)
                        SegmentedPill(items: [0, 1, 2], title: { ManagerTargets.bonusLevels[$0].name }, selection: $bonus)
                    }
                    ConsequenceNote(cost: costLine(pv, cur), benefit: benefitLine + " This also approves the year's budget.", risk: riskLine)
                    QuietButton(title: "Set targets…", fullWidth: true) { confirm = true }
                }
            }
        } else if !st.canSet && !st.setter.isOwner {
            Card(padding: 12, radius: Theme.Radius.row) {
                HStack(spacing: 10) {
                    GlyphView(glyph: Glyph.lock, size: 16, weight: 1.5, tint: Theme.ivoryFaint)
                    Text("\(st.setter.name) sets the targets here.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                }
            }
        }
    }

    private var modeChoices: some View {
        VStack(spacing: 8) {
            ForEach([0, 1, 2], id: \.self) { m in
                ChoiceCard(title: Self.modeNames[m], subtitle: modeNote(m), selected: mode == m) { mode = m }
            }
        }
    }

    private func modeNote(_ m: Int) -> String {
        m == 0 ? "Usually met, so the bonus is nearly always earned." : m == 2 ? "Pushes for the most; often missed." : "A fair aim from the last year and the market."
    }

    private func previewTable(_ pv: ManagerTargets.Preview, _ cur: Currency) -> some View {
        let cols: [TableColumn] = [TableColumn(title: "Target"), TableColumn(title: "Aim", width: 110)]
        return SharpTable {
            TableHeader(columns: cols)
            ForEach(pv.rows, id: \.key) { r in
                TableRow(columns: cols, title: Self.names[r.key] ?? r.key, values: [value(r.key, r.target, cur)])
            }
        }
    }

    private func costLine(_ pv: ManagerTargets.Preview, _ cur: Currency) -> String {
        let perTarget: Double = pv.hasManager ? pv.bonusPerTarget[min(2, max(0, bonus))] : 0
        if !pv.hasManager { return "none, you run it yourself." }
        return perTarget > 0 ? "\(cur.tidyShort(perTarget)) for each target met, up to \(cur.tidyShort(perTarget * 3)) a month." : "no bonus is paid."
    }

    private var benefitLine: String {
        mode == 2 ? "a stretch pushes for the most, and a manager with a bonus works to it." : mode == 0 ? "easy numbers are usually met, so the bonus is nearly always earned." : "a fair aim based on the last year and the market."
    }

    private var riskLine: String {
        mode == 2 ? "stretch targets are often missed, and a manager who misses again and again can lose heart." : mode == 0 ? "you may pay bonuses for what would have happened anyway." : "a bad month still misses them."
    }
}

// MARK: - Rewards: staff perks

/// Staff perks (Company > Team): a cost summary, then one card per perk with its monthly cost and what it does before it is switched on.
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

    private static func glyph(_ id: String) -> String {
        switch id {
        case "gym": return Glyph.gym
        case "lunch": return Glyph.cafe
        case "car": return Glyph.luxury
        case "trips": return Glyph.world
        case "health": return Glyph.person
        case "crew": return Glyph.team
        case "sales": return Glyph.stats
        case "keys": return Glyph.settings
        default: return Glyph.hire
        }
    }

    var body: some View {
        if !company.staff.isEmpty || company.managerID != nil {
            let cur = engine.currency(for: company)
            let total = engine.staffPerksMonthlyTotal(companyID: company.id)
            let options: [StaffPerks.Perk] = engine.staffPerkOptions
            TeamGroup(title: "Rewards", trailing: {
                Text(total > 0 ? "\(cur.tidyShort(total)) a month" : "none yet").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                summary(options, total: total, cur)
                ForEach(options) { p in perkCard(p, cur) }
            }
            .confirmationDialog(pendingGroup.map { "Add \($0.perk.name.lowercased()) for \($0.group.name.lowercased())?" } ?? "", isPresented: Binding(get: { pendingGroup != nil }, set: { if !$0 { pendingGroup = nil } }), titleVisibility: .visible) {
                groupDialogButton(cur)
            } message: {
                groupDialogMessage
            }
            .confirmationDialog(pending.map { "Add \($0.name.lowercased())?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                perkDialogButton(cur)
            } message: {
                perkDialogMessage
            }
        }
    }

    // MARK: Summary and cards

    private func summary(_ options: [StaffPerks.Perk], total: Double, _ cur: Currency) -> some View {
        let on: Int = options.filter { engine.staffPerkIsOn(companyID: company.id, perk: $0.id) }.count
        let together: Double = engine.staffPerksFewerLeavePercent(companyID: company.id)
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                PurposeHeader(glyph: Glyph.people, title: "Keeping people", note: "A perk costs every month and makes fewer people leave")
                StatStrip(cells: [
                    .init(label: "Switched on", value: "\(on) of \(options.count)"),
                    .init(label: "Cost a month", value: total > 0 ? cur.tidyShort(total) : "none"),
                    .init(label: "Fewer leave", value: together > 0 ? "\(Int(together.rounded()))%" : "none", tint: together > 0 ? Theme.gain : Theme.ivory),
                ])
            }
        }
    }

    private func perkCard(_ p: StaffPerks.Perk, _ cur: Currency) -> some View {
        let on: Bool = engine.staffPerkIsOn(companyID: company.id, perk: p.id)
        let cost: String = cur.tidyShort(engine.staffPerkMonthlyCost(companyID: company.id, perk: p.id))
        return Card(padding: 14, radius: Theme.Radius.card, stroke: on ? Theme.gold.opacity(0.6) : Theme.border) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    IconCircle(glyph: Self.glyph(p.id), tint: on ? Theme.gold : Theme.ivoryMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text(p.detail.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                StatStrip(cells: [
                    .init(label: "Cost a month", value: cost),
                    .init(label: "Fewer leave", value: "\(fewer(p))%", tint: Theme.gain),
                ])
                groupChoices(p, cur)
                if p.id == "car" && on {
                    ForEach(engine.companyCarRecipients(companyID: company.id)) { r in
                        Text(recipientLine(r, cur)).font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
                    }
                }
                HStack {
                    Text(on ? "A fixed cost while it is on." : "Cost, benefit and risk are shown before you confirm.").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                    Spacer(minLength: 8)
                    if on {
                        QuietButton(title: "On · switch off", tint: Theme.gain) { switchOff(p) }
                    } else {
                        QuietButton(title: "Add…") { pending = p }
                    }
                }
            }
        }
    }

    private func switchOff(_ p: StaffPerks.Perk) {
        let r = store.act { $0.toggleStaffPerk(companyID: company.id, perk: p.id) } ?? nil
        Haptics.tap()
        store.show(r == nil ? "Not possible right now." : "\(p.name) switched off.", tone: r == nil ? "warn" : "n")
    }

    // MARK: Confirmations

    @ViewBuilder private func groupDialogButton(_ cur: Currency) -> some View {
        if let pg = pendingGroup {
            Button("Add for \(cur.tidyShort(engine.staffPerkMonthlyCost(companyID: company.id, perk: pg.perk.id, group: pg.group.id))) a month") {
                let r = store.act { $0.toggleStaffPerk(companyID: company.id, perk: pg.perk.id, group: pg.group.id) } ?? nil
                if r == true { Haptics.success(); store.show("\(pg.perk.name) added for \(pg.group.name.lowercased()).", tone: "good") } else { Haptics.warning(); store.show("Not possible right now.", tone: "warn") }
                pendingGroup = nil
            }
        }
    }

    @ViewBuilder private var groupDialogMessage: some View {
        if let pg = pendingGroup {
            Text("Cost: paid every month for \(engine.staffPerkPeople(companyID: company.id, group: pg.group.id)) people in this group while it is on. Benefit: they leave about \(fewer(pg.perk))% less, and better applicants come for their jobs. Risk: a fixed cost in a bad month. Switch it off at any time.")
        }
    }

    @ViewBuilder private func perkDialogButton(_ cur: Currency) -> some View {
        if let p = pending {
            Button("Add for \(cur.tidyShort(engine.staffPerkMonthlyCost(companyID: company.id, perk: p.id))) a month") {
                let r = store.act { $0.toggleStaffPerk(companyID: company.id, perk: p.id) } ?? nil
                if r == true { Haptics.success(); store.show("\(p.name) added.", tone: "good") } else { Haptics.warning(); store.show("Not possible right now.", tone: "warn") }
                pending = nil
            }
        }
    }

    @ViewBuilder private var perkDialogMessage: some View {
        if let p = pending, p.id == "car" {
            Text("Cost: a leased car for the manager and for each team lead; the lease and the fuel are paid every month while it is on, and the cars show in the fleet. Benefit: \(fewer(p))% fewer people leave and better applicants come. Risk: cars are a fixed cost in a bad month. Switch it off and the cars go back.")
        } else if let p = pending {
            Text("Cost: paid every month while it is on. Benefit: \(fewer(p))% fewer people leave and better applicants come. Risk: it is a fixed cost in a bad month. Switch it off at any time.")
        }
    }
}

extension CompanyPerksCard {
    /// Who a perk is for: one chip per role group it may be given to (only where there is a choice), each switching it on or off for that group.
    @ViewBuilder func groupChoices(_ p: StaffPerks.Perk, _ cur: Currency) -> some View {
        let groups = engine.staffPerkGroups(perk: p.id)
        if groups.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who it covers").capsLabel(Theme.ivoryFaint)
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
                }
            }
        }
    }
}

// MARK: - Succession: the search for a new manager

/// Shown under the manager's notice: pay for the executive search for a successor and hire one of the candidates.
struct SuccessorSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var confirm = false

    var body: some View {
        let cur = engine.currency(for: company)
        let waiting = engine.successorCandidates(companyID: company.id)
        let fee: String = cur.tidyShort(ManagerModel.searchFee(currency: cur))
        VStack(alignment: .leading, spacing: 10) {
            PurposeHeader(glyph: Glyph.search, title: "Succession", note: waiting.isEmpty ? "Find someone before they leave" : "Candidates for the handover")
            if waiting.isEmpty {
                ConsequenceNote(cost: "the executive search fee, \(fee).",
                                benefit: "four candidates to choose from before the handover, so the company is not left without a manager.",
                                risk: "none may suit, and the fee is not refunded.")
                QuietButton(title: "Find a successor · \(fee)…", fullWidth: true) { confirm = true }
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
            Button("Pay \(fee) and search") {
                if let list = store.act({ $0.findSuccessor(companyID: company.id) }) ?? nil, !list.isEmpty { Haptics.success(); store.show("\(list.count) candidates found. Search paid: \(fee).", tone: "good") }
                else { Haptics.warning(); store.show("The search found no one, or the company cannot pay \(fee).", tone: "warn") }
            }
        } message: { Text("Three people from the trade and one generalist. The list stays for about six months.") }
    }
}
