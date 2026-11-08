import SwiftUI
import GameCore
import Businesses
import Simulation

/// The headcount order of a company: one row per role with who is in, what is open and the number to hire towards. The manager (or the boss
/// above a store with none) fills the plan; a number set here is the instruction, so they hire it without asking again. A chain store can
/// pass a role's number to every store of the chain.
struct StaffingPlanView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var pending: PendingAction?

    /// The most people one role can be set to (the engine's own cap).
    private static let maxTarget = 30.0

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                plan(e, co)
            } else {
                Text("This company no longer exists.").popupText(.body)
            }
        }
        .centerSheetTitle("Headcount")
        .confirmAction($pending)
    }

    @ViewBuilder private func plan(_ e: GameEngine, _ co: Company) -> some View {
        let rows: [StaffingPlan.Row] = e.staffingPlan(companyID: co.id)
        let chainID: Int? = co.value("chain").isNull ? nil : co.value("chain").int
        let hirer: String = rows.first(where: { (r: StaffingPlan.Row) -> Bool in !r.hirerName.isEmpty })?.hirerName ?? ""
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(hirer.isEmpty ? "How many people each role should have. Nobody hires for \(co.name) yet: you hire from the Team page."
                 : "How many people each role should have. \(hirer) hires towards these numbers and pays the recruiting fee.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            if rows.isEmpty {
                Text("This business has no posts to plan.").textStyle(.body, tint: Theme.inkSoft)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { n, r in
                        row(r, co, chainID)
                            .padding(.vertical, Theme.Space.m)
                            .overlay(alignment: .top) { if n > 0 { Hairline() } }
                            .accessibilityIdentifier("staffing-row-" + r.id)
                    }
                }
            }
        }
    }

    private func status(_ r: StaffingPlan.Row) -> String {
        var parts: [String] = ["\(r.filled) in"]
        if r.leaving > 0 { parts.append("\(r.leaving) leaving") }
        if r.vacancies > 0 { parts.append("\(r.vacancies) open" + (r.weeksOpen > 0 ? " for \(r.weeksOpen) \(r.weeksOpen == 1 ? "week" : "weeks")" : "")) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func row(_ r: StaffingPlan.Row, _ co: Company, _ chainID: Int?) -> some View {
        let isManagerPost: Bool = r.role == StaffingPlan.managerRole
        let title: String = r.seasonal ? "Seasonal \(r.roleName.lowercased()) crew" : r.roleName
        let target = Binding<Double>(get: { Double(r.target) }, set: { (v: Double) in setTarget(r, Int(v)) })
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title.tidyText).textStyle(.headline)
                    Text(status(r)).textStyle(.caption, tint: r.vacancies > 0 ? Theme.caution : Theme.inkFaint)
                }
                Spacer(minLength: Theme.Space.s)
                if isManagerPost {
                    Text(r.vacancies > 0 ? "Open" : "Filled").textStyle(.body, tint: r.vacancies > 0 ? Theme.caution : Theme.gain, weight: .medium)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(r.target)").textStyle(.headline, numeric: true)
                        Text("aim").textStyle(.caption, tint: Theme.inkFaint)
                    }
                    StepperPill(value: target, range: 0...Self.maxTarget, step: 1)
                }
            }
            if isManagerPost {
                Text("The post is filled by \(r.hirerName.isEmpty ? "you" : r.hirerName); it is not a number to set.").textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: Theme.Space.m) {
                    Text(r.ownerSet ? "Set by you" : "From the trade and the work").textStyle(.caption, tint: Theme.inkFaint)
                    Spacer(minLength: Theme.Space.s)
                    if r.ownerSet {
                        Button("Back to the usual") { Haptics.tap(); resetTarget(r) }.buttonStyle(TertiaryButtonStyle(size: .compact))
                    }
                    if let chainID, !r.seasonal {
                        Button("Every store\u{2026}") { Haptics.tap(); askChain(r, chainID) }.buttonStyle(TertiaryButtonStyle(size: .compact))
                    }
                }
            }
        }
    }

    private func setTarget(_ r: StaffingPlan.Row, _ value: Int) {
        let ok: Bool = store.act { $0.setHeadcountTarget(companyID: companyID, role: r.role, target: value, seasonal: r.seasonal) } ?? false
        if !ok { Haptics.warning(); store.show("That post cannot be set here.", tone: "warn") }
    }

    private func resetTarget(_ r: StaffingPlan.Row) {
        let ok: Bool = store.act { $0.resetHeadcountTarget(companyID: companyID, role: r.role, seasonal: r.seasonal) } ?? false
        if !ok { Haptics.warning(); store.show("That post cannot be set here.", tone: "warn") }
    }

    /// Passing a number to every open store of the chain is a bigger step than one company's setting, so it is asked first.
    private func askChain(_ r: StaffingPlan.Row, _ chainID: Int) {
        let role: String = r.role
        let aim: Int = r.target
        let name: String = r.roleName.lowercased()
        pending = PendingAction(title: "Set it for every store?",
                                message: "Every open store of the chain will aim for \(aim) \(name). Each store's manager, or the boss above it, hires towards that.",
                                button: "Set for the chain", tone: .info, icon: "building.2") {
            let n: Int = store.act { $0.setChainHeadcountTarget(chainID: chainID, role: role, target: aim) } ?? 0
            store.show(n == 1 ? "1 store now aims for \(aim) \(name)." : "\(n) stores now aim for \(aim) \(name).", tone: "n")
        }
    }
}
