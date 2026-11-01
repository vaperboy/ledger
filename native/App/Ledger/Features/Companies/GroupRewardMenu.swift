import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// "Reward" on the row of an executive, a head-office member or the data analyst: a pay review, a promotion, more responsibility, training, a benefit
/// (a weekly reimbursement) or a change of hours. Each is one of the engine's real `group*` actions; the engine prices it first
/// (`groupRewardPreview`) and the owner confirms with the cost and the consequence in front of them. A matching promise is kept by the same action.
struct GroupRewardMenu: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var personID: Int
    var name: String
    @State private var pending: PendingAction?

    private struct Reward: Identifiable {
        var id: String
        var title: String
        var kind: StaffPromises.Kind
        var percent: Double = 0.05
        var expense: String = ""
        var workingPercent: Double = 100
    }

    private var rewards: [Reward] {
        var out: [Reward] = [
            Reward(id: "pay", title: "Pay review, 5 percent", kind: .salaryReview),
            Reward(id: "promote", title: "Promotion", kind: .promotion),
            Reward(id: "resp", title: "More responsibility", kind: .responsibility),
            Reward(id: "train", title: "Training", kind: .training),
        ]
        for item in StaffExpenses.all.prefix(4) {
            out.append(Reward(id: "exp:" + item.id, title: "Benefit: " + item.name, kind: .futureBenefits, expense: item.id))
        }
        let now: Double = GroupPeople.percent(engine.state, personID: personID)
        for p in [50.0, 80.0, 100.0] where abs(p - now) > 0.5 {
            out.append(Reward(id: "pct\(Int(p))", title: "Hours: \(Int(p)) percent", kind: .percentageChange, workingPercent: p))
        }
        return out
    }

    var body: some View {
        Menu {
            ForEach(rewards) { r in Button(r.title) { confirm(r) } }
        } label: {
            Text("Reward").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1))
                .frame(minHeight: 32)
        }
        .accessibilityIdentifier("group-reward")
        .confirmAction($pending)
    }

    private func confirm(_ r: Reward) {
        let cur: Currency = engine.homeCurrency
        let pv: GroupRewardPreview = engine.groupRewardPreview(personID: personID, kind: r.kind, percent: r.percent, expense: r.expense, workingPercent: r.workingPercent)
        var parts: [String] = pv.lines
        if pv.wageAfter != pv.wageBefore { parts.append("Pay a month: \(cur.tidyShort(pv.wageBefore)) to \(cur.tidyShort(pv.wageAfter)).") }
        if pv.employerCostPerMonth != 0 { parts.append("Costs the group \(cur.tidyShort(pv.employerCostPerMonth)) more a month with employer charges.") }
        if pv.oneOffCost > 0 { parts.append("Costs \(cur.tidyShort(pv.oneOffCost)) once, paid now.") }
        parts.append("Any promise of this kind to \(name) counts as kept.")
        let amount: Double? = pv.oneOffCost > 0 ? pv.oneOffCost : nil
        pending = PendingAction(title: "\(r.title) for \(name)?", message: parts.joined(separator: " "), button: "Do it", amount: amount, currency: cur) { run(r) }
    }

    private func run(_ r: Reward) {
        let pid = personID
        let current: Int = GroupPeople.level(engine.state, personID: pid)
        let ok: Bool?
        switch r.kind {
        case .salaryReview: ok = store.act { $0.groupRaise(personID: pid, percent: r.percent) }
        case .promotion: ok = store.act { $0.groupPromote(personID: pid) }
        case .responsibility: ok = store.act { $0.groupSetLevel(personID: pid, level: min(2, current + 1)) }
        case .training: ok = store.act { $0.groupTrain(personID: pid) }
        case .betterConditions, .futureBenefits: ok = store.act { $0.groupSetExpense(personID: pid, item: r.expense, on: true) }
        case .percentageChange: ok = store.act { $0.groupSetPercent(personID: pid, percent: r.workingPercent) }
        }
        if ok == true { Haptics.success(); store.show("\(r.title): done for \(name).", tone: "good") }
        else { Haptics.warning(); store.show("That could not be done now: it may already be the case, or the cash is short.", tone: "warn") }
    }
}
