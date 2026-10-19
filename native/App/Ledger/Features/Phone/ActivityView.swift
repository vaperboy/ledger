import SwiftUI
import GameCore
import Simulation

/// Every movement on your personal account, newest first, with the balance after each. Company books are on each company's Money tab.
struct ActivityView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine {
            List {
                ForEach(Array(e.state.statement.prefix(300).enumerated()), id: \.offset) { _, line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.label).font(.bodyText).foregroundStyle(Theme.ivory)
                            Text("Week \(line.week + 1) · \(GameCalendar.dateString(week: line.week, dayOffset: line.day))").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text((line.amount >= 0 ? "+" : "−") + store.short(abs(line.amount))).font(.system(.subheadline, design: .serif).monospacedDigit()).foregroundStyle(Theme.change(line.amount))
                            Text(store.short(line.balanceAfter)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                    .listRowBackground(Theme.leather.opacity(0.5))
                }
            }
            .scrollContentBackground(.hidden)
            .ledgerBackground()
            .navigationTitle("Activity")
        }
    }
}
