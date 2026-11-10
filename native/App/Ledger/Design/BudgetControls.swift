import SwiftUI
import GameCore
import Businesses

struct BudgetChip: View {
    var budget: Budget

    static func tint(_ b: Budget) -> Color { b == .tight ? Theme.caution : b == .normal ? Theme.gold : Theme.gain }

    var body: some View { Chip(text: "Budget \u{00B7} " + budget.title, tint: Self.tint(budget)) }
}

struct BudgetMenu: View {
    var budget: Budget
    var name: String
    var set: (Budget) -> Void

    var body: some View {
        Menu {
            ForEach(Budget.allCases, id: \.rawValue) { (b: Budget) in
                Button((b == budget ? "\u{2713} " : "") + b.title + ": " + b.text) { Haptics.choose(); set(b) }
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                BudgetChip(budget: budget)
                Text("\u{2304}").textStyle(.caption, tint: Theme.inkFaint)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(name), budget \(budget.title). Change")
    }
}

struct BudgetPicker: View {
    var budget: Budget
    var name: String
    var detail: String? = nil
    var set: (Budget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SegmentedPill(items: Budget.allCases,
                          title: { (b: Budget) -> String in b.title },
                          selection: Binding<Budget>(get: { budget }, set: { (b: Budget) in set(b) }),
                          identifier: { (b: Budget) -> String in "budget-" + b.title.lowercased() })
            Text((detail ?? "\(name) \(budget.text).").tidyMoney).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }
}
