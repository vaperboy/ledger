import SwiftUI
import Charts
import GameCore
import Finance
import Events
import Businesses
import Simulation

/// The Stats app, one page in three parts: how things are going (net worth, its trend and the few levers that need attention), a few fun
/// facts about the run, and a few things good to know (the economy and what the run has cost). Reports, Activity and the trophies are
/// their own apps; nothing here links to them.
struct StatsView: View {
    @EnvironmentObject var store: GameStore
    @State private var period = 90

    private static let periods: [Int] = [30, 90, 365]

    var body: some View {
        if let e = store.engine {
            PhonePageScroll(spacing: Theme.Space.xl) {
                goingCard(e)
                funFacts(e)
                goodToKnow(e)
            }
        }
    }

    // MARK: How things are going

    /// Net worth now with the month's change in words, the trend, and at most four levers (the ones that need attention first).
    private func goingCard(_ e: GameEngine) -> some View {
        let nw: NetWorth = e.netWorth
        let h: DayHistory = e.dayHistory
        let month: (amount: Double, share: Double?)? = DayHistory.change(h.netWorth, days: 30)
        let series: [Double] = e.netWorthSeries(days: period)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Figure(label: "Net worth now", value: store.short(nw.total), note: monthNote(month), tint: nw.total < 0 ? Theme.loss : nil, size: .display, live: nw.total)
            NetWorthChart(engine: e, days: period, height: 120)
            SegmentedChoice(items: Self.periods, title: { (d: Int) -> String in d == 30 ? "1M" : d == 90 ? "3M" : "1Y" }, selection: $period)
                .accessibilityLabel("Chart period")
            FigureRow(items: [
                KeyFigures.Item(label: "Cash", value: store.short(h.cash.last ?? 0)),
                KeyFigures.Item(label: "Invested", value: store.short(h.invested.last ?? 0)),
                KeyFigures.Item(label: "Companies", value: store.short(h.companies.last ?? 0))
            ])
            playing(e)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(series.count >= 2 ? "" : "The chart fills in day by day")
    }

    private func monthNote(_ change: (amount: Double, share: Double?)?) -> String {
        guard let c = change else { return "Your record starts to show after a few days" }
        if abs(c.amount) < 0.5 { return "Level over the past month" }
        let sign: String = c.amount > 0 ? "Up " : "Down "
        return sign + store.short(abs(c.amount)) + " in the past month"
    }

    @ViewBuilder private func playing(_ e: GameEngine) -> some View {
        let all: [PlayingRow] = e.playingPanel()
        let rows: [PlayingRow] = Array((all.filter { $0.tone == "weak" } + all.filter { $0.tone != "weak" }).prefix(4))
        if !rows.isEmpty {
            LedgerSection("How you are playing") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { (i: Int, r: PlayingRow) in
                        if i > 0 { Hairline() }
                        LedgerRow(title: r.title, subtitle: r.why, value: r.value,
                                  valueTint: r.tone == "good" ? Theme.gain : r.tone == "weak" ? Theme.warn : Theme.ink, density: .compact, identifier: "stats-playing-" + r.id)
                    }
                }
            }
        }
    }

    // MARK: Fun facts

    private struct Fact: Identifiable {
        var id: String
        var glyph: String
        var title: String
        var value: String
    }

    private func facts(_ e: GameEngine) -> [Fact] {
        let s = e.state
        let best: Double = max(s.stats.peakNetWorth, e.netWorth.total)
        let m: MilestoneProgress = e.milestoneProgress
        var out: [Fact] = [Fact(id: "days", glyph: Glyph.clock, title: "Days in business", value: "\(s.week * 7 + s.day)")]
        if best > 0 { out.append(Fact(id: "best", glyph: Glyph.stats, title: "Best net worth so far", value: store.short(best))) }
        if m.bestWeek > 0 { out.append(Fact(id: "week", glyph: Glyph.arrowIn, title: "Best single week", value: store.short(m.bestWeek))) }
        if m.bestStreak > 1 { out.append(Fact(id: "run", glyph: Glyph.check, title: "Longest run of growing weeks", value: "\(m.bestStreak)")) }
        if s.stats.companiesSold > 0 { out.append(Fact(id: "sold", glyph: Glyph.bank, title: "Companies sold", value: "\(s.stats.companiesSold)")) }
        if s.stats.dividendsReceived > 0 { out.append(Fact(id: "div", glyph: Glyph.arrowIn, title: "Dividends you received", value: store.short(s.stats.dividendsReceived))) }
        return Array(out.prefix(5))
    }

    private func funFacts(_ e: GameEngine) -> some View {
        let list: [Fact] = facts(e)
        return LedgerSection("Fun facts") {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, f: Fact) in
                    if i > 0 { Hairline() }
                    LedgerRow(leading: .glyph(f.glyph), title: f.title, value: f.value, density: .compact)
                }
            }
        }
    }

    // MARK: Good to know

    private func goodToKnow(_ e: GameEngine) -> some View {
        let eco = e.state.economy
        let phase: String = eco.phase
        let st = e.state.stats
        return LedgerSection(title: "Good to know", trailing: {
            AcctPill(text: "Economy: " + phase.capitalized, tone: phase == "boom" ? .good : phase == "recession" ? .bad : phase == "slowdown" ? .warn : .neutral)
        }) {
            if phase == "recession" || phase == "slowdown" {
                Text(phase == "recession" ? "The economy is in recession. Customer demand and rates show how it reaches you." : "The economy is slowing. Customer demand and rates show how it reaches you.")
                    .textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
            FigureRow(items: [
                KeyFigures.Item(label: "Customer demand", value: signedPct(eco.demand - 1), tint: Theme.change(eco.demand - 1)),
                KeyFigures.Item(label: "Inflation", value: pct(eco.inflation)),
                KeyFigures.Item(label: "Central bank rate", value: pct(eco.policyRate))
            ])
            FigureRow(items: [
                KeyFigures.Item(label: "Tax paid", value: store.short(st.taxPaid)),
                KeyFigures.Item(label: "Wages paid", value: store.short(st.wagesPaid)),
                KeyFigures.Item(label: "Interest paid", value: store.short(st.interestPaid))
            ])
        }
    }

    private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    private func signedPct(_ x: Double) -> String { String(format: "%@%.0f%%", x >= 0 ? "+" : "\u{2212}", abs(x) * 100) }
}
