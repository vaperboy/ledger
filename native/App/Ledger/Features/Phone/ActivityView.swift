import SwiftUI
import GameCore
import Simulation

/// Every movement on your personal account, newest first, with the balance after each. Company books are on each company's Money tab.
struct ActivityView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine {
            ScrollView {
                Card {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                        if e.state.statement.isEmpty { Text("Nothing has moved yet.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                        ForEach(Array(e.state.statement.prefix(300).enumerated()), id: \.offset) { _, line in
                            ListRow(symbol: line.amount >= 0 ? "arrow.down.left" : "arrow.up.right", tint: line.amount >= 0 ? Theme.gain : Theme.ivoryMuted,
                                    title: line.label,
                                    subtitle: "Week \(line.week + 1) · \(GameCalendar.dateString(week: line.week, dayOffset: line.day))",
                                    trailing: (line.amount >= 0 ? "+" : "−") + store.short(abs(line.amount)),
                                    trailingSub: "Balance " + store.short(line.balanceAfter),
                                    trailingTint: line.amount >= 0 ? Theme.gain : Theme.ivory)
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Activity")
        }
    }
}
