import SwiftUI
import GameCore
import Businesses
import Finance
import Countries
import Simulation

struct PlanStatement: View {
    var plan: NewCompanyPlan
    var cur: Currency
    @Binding var choices: SetupChoices
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
            TableRow(columns: Self.columns, title: "Needed now", note: "Recommended investment: \(cur.tidyShort(plan.recommendedInvestment)). Nothing is bought or hired for you.", values: [cur.tidyShort(plan.neededNow)], selected: true)
            if plan.estimate.shareCapital > 0 {
                TableRow(columns: Self.columns, title: "Share capital", note: "From your account; stays in the company.", values: [cur.tidyShort(plan.estimate.shareCapital)])
            }
        }
    }

    @ViewBuilder private var optionalChoices: some View {
        let hasStock: Bool = plan.estimate.stock > 0
        if hasStock {
            CardSection("Opening stock") {
                Text("Equipment and people are not bought or hired for you: you choose them yourself while setting up. Only the opening stock is chosen here.").textStyle(.caption, tint: Theme.inkFaint)
                SegmentedPill(items: SetupChoices.Stock.allCases, title: { stockTitle($0) }, selection: Binding(get: { choices.stock }, set: { choices.stock = $0 }))
                Text("Opening stock of the standard size costs \(cur.tidyShort(plan.estimate.stock)). It is bought when the last paper is approved.").textStyle(.caption, tint: Theme.inkFaint)
            }
        }
    }

    private func stockTitle(_ s: SetupChoices.Stock) -> String { s == .full ? "Full stock" : s == .half ? "Half" : "None" }

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

    private var alternatives: some View {
        CardSection("Cheaper ways to start") {
            ForEach(Array(plan.alternatives.enumerated()), id: \.element.id) { n, a in
                if n > 0 { CardLine() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.title).textStyle(.body, weight: .medium)
                    Text(a.detail.tidyMoney).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
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
