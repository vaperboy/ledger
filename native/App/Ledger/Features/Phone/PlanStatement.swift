import SwiftUI
import GameCore
import Businesses
import Finance
import Countries
import Simulation

/// The start-up statement of a new company, shared by both New company screens: what is mandatory, what is optional and chosen, deposits that come
/// back, fees, working capital kept in the company, and the cash that is left (with the personal reserve kept visible). Nothing optional is
/// bought unless it is switched on here; every other choice is shown with its price. All figures come from `GameEngine.newCompanyPlan`.
struct PlanStatement: View {
    var plan: NewCompanyPlan
    var cur: Currency
    @Binding var choices: SetupChoices
    /// Applying an alternative that changes something outside the choices (rent instead of buy, smaller size) is up to the screen.
    var onAlternative: (PlanAlternative) -> Void = { _ in }

    private static let columns: [TableColumn] = [TableColumn(title: "What"), TableColumn(title: "Amount", width: 96)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            statement
            optionalChoices
            remainingCash
            if !plan.alternatives.isEmpty { alternatives }
        }
    }

    @ViewBuilder private func group(_ title: String, _ kinds: [PlanLine.Kind]) -> some View {
        let rows: [PlanLine] = plan.lines.filter { kinds.contains($0.kind) }
        if !rows.isEmpty {
            TableRow(columns: Self.columns, title: title, values: [cur.tidyShort(rows.reduce(0) { $0 + $1.amount })], selected: true)
            ForEach(rows) { l in
                TableRow(columns: Self.columns, title: l.title, note: l.note, values: [cur.tidyShort(l.amount)])
            }
        }
    }

    private var statement: some View {
        SharpTable {
            TableHeader(columns: Self.columns)
            group("Must be paid", [.mandatory])
            group("Deposits (come back when you leave)", [.deposit])
            group("Fees", [.fee])
            group("Optional, chosen by you", [.optional])
            group("Working capital (stays in the company)", [.workingCapital])
            TableRow(columns: Self.columns, title: "The company needs", note: "With a 15% margin: \(cur.tidyShort(plan.neededNow * 1.15))", values: [cur.tidyShort(plan.neededNow)], selected: true)
            if plan.estimate.shareCapital > 0 {
                TableRow(columns: Self.columns, title: "Share capital", note: "From your account; stays in the company.", values: [cur.tidyShort(plan.estimate.shareCapital)])
            }
        }
    }

    // MARK: Optional items

    @ViewBuilder private var optionalChoices: some View {
        let hasStock: Bool = plan.estimate.stock > 0
        let hasExtraKit: Bool = plan.choices.optionalEquipment || plan.notChosen.contains { $0.id == "optEq" }
        let hasTeam: Bool = plan.choices.team == .standard || plan.notChosen.contains { $0.id == "team" }
        if hasStock || hasExtraKit || hasTeam {
            CardSection("Optional extras") {
                Text("Nothing here is bought unless you choose it. Each choice shows what it costs.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                if hasStock {
                    SegmentedPill(items: SetupChoices.Stock.allCases, title: { stockTitle($0) }, selection: Binding(get: { choices.stock }, set: { choices.stock = $0 }))
                    Text("Opening stock of the standard size costs \(cur.tidyShort(plan.estimate.stock)). It is bought when the last paper is approved.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                if hasExtraKit, let line = plan.notChosen.first(where: { $0.id == "optEq" }) {
                    CardLine()
                    Toggle(isOn: Binding(get: { choices.optionalEquipment }, set: { choices.optionalEquipment = $0 })) {
                        Text("Optional equipment and vehicles · \(cur.tidyShort(line.amount))").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    }
                } else if choices.optionalEquipment {
                    CardLine()
                    Toggle(isOn: Binding(get: { choices.optionalEquipment }, set: { choices.optionalEquipment = $0 })) {
                        Text("Optional equipment and vehicles").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    }
                }
                if hasTeam {
                    CardLine()
                    Toggle(isOn: Binding(get: { choices.team == .standard }, set: { choices.team = $0 ? .standard : .minimum })) {
                        Text("Hire the whole standard team now").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    }
                    Text("By default only the core team is hired, and only while the company's cash carries two months of their wages. Every further hire is a monthly cost; the rest of the team is about \(cur.tidyShort(plan.notChosen.first { $0.id == "team" }?.amount ?? 0)) a month.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func stockTitle(_ s: SetupChoices.Stock) -> String { s == .full ? "Full stock" : s == .half ? "Half" : "None" }

    // MARK: Cash left

    @ViewBuilder private var remainingCash: some View {
        let tint: Color = plan.keepsReserve ? Theme.gain : Theme.caution
        SharpTable {
            TableHeader(columns: Self.columns)
            TableRow(columns: Self.columns, title: "You have", values: [cur.tidyShort(plan.available)])
            TableRow(columns: Self.columns, title: "Registration, fees and share capital", values: [cur.tidyShort(plan.registrationAndCapital)])
            TableRow(columns: Self.columns, title: "Moved into the company", note: choices.putInto == nil ? "Keeps your reserve of \(cur.tidyShort(plan.personalReserve))." : "Your own figure.", values: [cur.tidyShort(plan.intoCompany)])
            TableRow(columns: Self.columns, title: "Left in your accounts", note: plan.keepsReserve ? "Above your reserve of \(cur.tidyShort(plan.personalReserve))." : "Below your reserve of \(cur.tidyShort(plan.personalReserve)).", values: [cur.tidyShort(plan.accountsAfter)], valueTints: [tint], selected: true)
            TableRow(columns: Self.columns, title: "Company cash after set-up", values: [cur.tidyShort(plan.companyCashAfterSetup)])
        }
        if plan.shortfall > 0 {
            NoteCard(text: "The company is \(cur.tidyShort(plan.shortfall)) short of the scope above. Set-up pays the mandatory costs first and skips what the cash cannot carry (it is listed afterwards); the company opens when the money is there.", glyph: Glyph.warning, tint: Theme.caution)
        }
        if choices.putInto != nil {
            QuietButton(title: "Go back to the amount that keeps my reserve") { choices.putInto = nil }
        } else if plan.shortfall > 0 && plan.available - plan.registrationAndCapital > plan.intoCompany {
            QuietButton(title: "Put in all my money instead (\(cur.tidyShort(max(0, plan.available - plan.registrationAndCapital))))") { choices.putInto = max(0, plan.available - plan.registrationAndCapital) }
        }
    }

    // MARK: Alternatives

    private var alternatives: some View {
        CardSection("Cheaper ways to start") {
            ForEach(Array(plan.alternatives.enumerated()), id: \.element.id) { n, a in
                if n > 0 { CardLine() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(a.detail.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    QuietButton(title: "Use this") { apply(a) }
                }
            }
        }
    }

    private func apply(_ a: PlanAlternative) {
        if a.id == "lean" {
            choices.optionalEquipment = false
            choices.team = .minimum
            choices.stock = choices.stock == .full ? .half : .none
            choices.putInto = nil
        } else { onAlternative(a) }
    }
}
