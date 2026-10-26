import SwiftUI
import GameCore
import Simulation

/// Every movement on your personal account, newest first, with the balance after each. Company books are on each company's Money tab.
struct ActivityView: View {
    @EnvironmentObject var store: GameStore
    private let shown = 300

    var body: some View {
        if let e = store.engine {
            let lines = Array(e.state.statement.prefix(shown))
            let moneyIn = lines.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
            let moneyOut = lines.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if lines.isEmpty {
                        Text("Nothing has moved yet. Salary, dividends, loans and purchases from your own account are listed here as they happen.")
                            .font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Balance after the latest line").capsLabel(Theme.ivoryFaint)
                            Text(store.money(lines[0].balanceAfter)).font(.hero(34)).foregroundStyle(lines[0].balanceAfter < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                        }
                        KeyFigures(items: [
                            .init(label: "Came in", value: "+" + store.short(moneyIn), tint: Theme.gain),
                            .init(label: "Went out", value: "−" + store.short(moneyOut)),
                            .init(label: "Lines", value: e.state.statement.count > shown ? "\(shown) of \(e.state.statement.count)" : "\(lines.count)")
                        ])
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                if i > 0 { Hairline() }
                                ListRow(symbol: line.amount >= 0 ? "arrow.down.left" : "arrow.up.right", tint: line.amount >= 0 ? Theme.gain : Theme.ivoryMuted,
                                        title: line.label,
                                        subtitle: GameCalendar.dateString(week: line.week, dayOffset: line.day),
                                        trailing: (line.amount >= 0 ? "+" : "−") + store.short(abs(line.amount)),
                                        trailingSub: "Balance " + store.short(line.balanceAfter),
                                        trailingTint: line.amount >= 0 ? Theme.gain : Theme.ivory)
                            }
                        }
                        if e.state.statement.count > shown {
                            Text("Older lines are kept in the save but not listed here.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
