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
                        NoteCard(text: "Nothing has moved yet. Salary, dividends, loans and purchases from your own account are listed here as they happen.", glyph: Glyph.list)
                    } else {
                        HeroFigure(label: "Balance after the latest line", value: store.money(lines[0].balanceAfter), tint: lines[0].balanceAfter < 0 ? Theme.loss : Theme.ivory)
                        FigureCard(items: [
                            .init(label: "Came in", value: "+" + store.short(moneyIn), tint: Theme.gain),
                            .init(label: "Went out", value: "−" + store.short(moneyOut)),
                            .init(label: "Lines", value: e.state.statement.count > shown ? "\(shown) of \(e.state.statement.count)" : "\(lines.count)")
                        ])
                        Card(padding: 14) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                    if i > 0 { CardLine() }
                                    RowLine(glyph: line.amount >= 0 ? Glyph.arrowIn : Glyph.arrowOut, tint: line.amount >= 0 ? Theme.gain : Theme.ivoryMuted,
                                            title: line.label,
                                            subtitle: GameCalendar.dateString(week: line.week, dayOffset: line.day),
                                            trailing: (line.amount >= 0 ? "+" : "−") + store.short(abs(line.amount)),
                                            trailingSub: "Balance " + store.short(line.balanceAfter),
                                            trailingTint: line.amount >= 0 ? Theme.gain : Theme.ivory)
                                }
                            }
                        }
                        if e.state.statement.count > shown {
                            Text("Older lines are kept in the save but not listed here.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
        }
    }
}
