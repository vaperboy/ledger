import SwiftUI
import GameCore
import Simulation

/// Activity app: a dated timeline feed of every movement on your personal account, newest first, grouped under the day it happened,
/// with a vertical line through the icon circles and the balance after each line. Company books are on each company's Money tab.
struct ActivityView: View {
    @EnvironmentObject var store: GameStore
    private let shown = 300

    /// One day of the feed: the date, and the lines that happened on it.
    private struct DayGroup: Identifiable {
        var id: Int
        var week: Int
        var day: Int
        var lines: [StatementLine]
    }

    private func groups(_ lines: [StatementLine]) -> [DayGroup] {
        var out: [DayGroup] = []
        for line in lines {
            if let last = out.last, last.week == line.week, last.day == line.day {
                out[out.count - 1].lines.append(line)
            } else {
                out.append(DayGroup(id: out.count, week: line.week, day: line.day, lines: [line]))
            }
        }
        return out
    }

    var body: some View {
        if let e = store.engine {
            let lines: [StatementLine] = Array(e.state.statement.prefix(shown))
            PhonePageScroll(spacing: 14) {
                if lines.isEmpty {
                    NoteCard(text: "Nothing has moved yet. Salary, dividends, loans and purchases from your own account are listed here as they happen.", glyph: Glyph.list)
                } else {
                    summary(lines, total: e.state.statement.count)
                    feed(lines)
                    if e.state.statement.count > shown {
                        Text("Older lines are kept in the save but not listed here.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
        }
    }

    private func summary(_ lines: [StatementLine], total: Int) -> some View {
        let moneyIn: Double = lines.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        let moneyOut: Double = lines.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) }
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Balance after the latest line").capsLabel()
                Text(store.money(lines[0].balanceAfter)).font(.hero(30)).foregroundStyle(lines[0].balanceAfter < 0 ? Theme.loss : Theme.ivory)
                    .lineLimit(1).minimumScaleFactor(0.6)
                StatStrip(cells: [
                    .init(label: "Came in", value: "+" + store.short(moneyIn), tint: Theme.gain),
                    .init(label: "Went out", value: "\u{2212}" + store.short(moneyOut)),
                    .init(label: "Lines", value: total > shown ? "\(shown) of \(total)" : "\(lines.count)")
                ])
            }
        }
    }

    private func feed(_ lines: [StatementLine]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groups(lines)) { (g: DayGroup) in
                dayHeader(g)
                ForEach(Array(g.lines.enumerated()), id: \.offset) { i, line in
                    entry(line, last: i == g.lines.count - 1)
                }
            }
        }
    }

    private func dayHeader(_ g: DayGroup) -> some View {
        let net: Double = g.lines.reduce(0) { $0 + $1.amount }
        let sign: String = net > 0 ? "+" : net < 0 ? "\u{2212}" : ""
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.gold).frame(width: 7, height: 7).frame(width: 34)
            Text(GameCalendar.dateString(week: g.week, dayOffset: g.day)).font(.serifTitle(17)).foregroundStyle(Theme.ivory)
            Spacer(minLength: 8)
            Text("Day \(sign)\(store.short(abs(net)))").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.change(net))
        }
        .padding(.top, 14).padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func entry(_ line: StatementLine, last: Bool) -> some View {
        let income: Bool = line.amount >= 0
        let sign: String = income ? "+" : "\u{2212}"
        return HStack(alignment: .top, spacing: 8) {
            IconCircle(glyph: income ? Glyph.arrowIn : Glyph.arrowOut, size: 34, tint: income ? Theme.gain : Theme.ivoryMuted)
                .background(Circle().fill(Theme.page))
                .frame(width: 34)
                .background(alignment: .top) { Rectangle().fill(Theme.border).frame(width: 1).padding(.top, 0).frame(maxHeight: .infinity) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(line.label.tidyText).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(3).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(sign + store.short(abs(line.amount))).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(income ? Theme.gain : Theme.ivory)
                }
                Text("Balance " + store.short(line.balanceAfter)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.tableLine).frame(height: 1) } }
        }
        .padding(.bottom, last ? 4 : 0)
        .accessibilityElement(children: .combine)
    }
}
