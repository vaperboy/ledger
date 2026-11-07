import SwiftUI
import GameCore
import Events
import Simulation

/// Shown when the bank has taken everything. The save is kept. The hero is the final net worth with why the run ended; under it, unboxed,
/// how long it lasted, what became of every company and the lifetime totals in `stats`. One action, pinned: back to the start screen.
struct GameOverView: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 42

    var body: some View {
        let s = engine.state
        let over = s.gameOver
        let endWeek = over["week"].isNull ? s.week : over["week"].int
        let endWorth: Double = over["nw"].isNull ? engine.netWorth.total : over["nw"].double
        let reason: String = over["reason"].string == "insolvent"
            ? "You owe more than you own and the bank has ended it."
            : "Your account stayed empty for too long. The bank has stopped lending."
        let weeks = max(1, endWeek + 1)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("The ledger is closed").textStyle(.label, tint: Theme.inkFaint)
                    Text(store.short(endWorth))
                        .font(.hero(heroSize))
                        .foregroundStyle(endWorth < 0 ? Theme.loss : Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("\(s.player.name)'s net worth at the end").textStyle(.body, tint: Theme.inkSoft)
                    Text(reason).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Theme.Space.xxl)
                group("The run") {
                    FigureRow(items: [
                        .init(label: "Lasted", value: duration(weeks: weeks)),
                        .init(label: "Ended", value: GameCalendar.dateString(week: endWeek)),
                        .init(label: "Best net worth", value: store.short(max(s.stats.peakNetWorth, 0))),
                    ], columns: 3)
                }
                companiesGroup(s)
                totalsGroup(s)
            }
            .padding(.horizontal, Theme.Space.page).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Theme.Space.s) {
                Button("Back to the start screen") { Haptics.tap(); store.quitToMenu() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("game-over-start")
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.s)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Theme.page)
            .overlay(alignment: .top) { Hairline() }
        }
        .ledgerBackground()
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title).textStyle(.label, tint: Theme.inkFaint)
            content()
        }
    }

    /// What became of every company: one stacked bar, then the counts.
    private func companiesGroup(_ s: GameState) -> some View {
        let businesses = s.companies.filter { $0.type != "hold" }
        let standing = businesses.filter { $0.status.isLive }.count
        let sold = businesses.filter { $0.status == .sold }.count
        let bust = businesses.filter { $0.status == .bust }.count
        return group("Companies") {
            if businesses.isEmpty {
                Text("You never started or bought a company.").textStyle(.body, tint: Theme.inkSoft)
            } else {
                outcomeBar(standing: standing, sold: sold, bust: bust)
                FigureRow(items: [
                    .init(label: "Standing", value: "\(standing)", tint: standing > 0 ? Theme.gain : Theme.ink),
                    .init(label: "Sold", value: "\(sold)"),
                    .init(label: "Went bust", value: "\(bust)", tint: bust > 0 ? Theme.loss : Theme.ink),
                ], columns: 3)
            }
        }
    }

    private func outcomeBar(standing: Int, sold: Int, bust: Int) -> some View {
        let total = CGFloat(max(1, standing + sold + bust))
        return GeometryReader { g in
            HStack(spacing: 2) {
                if standing > 0 { Rectangle().fill(Theme.gain).frame(width: g.size.width * CGFloat(standing) / total) }
                if sold > 0 { Rectangle().fill(Theme.inkSoft).frame(width: g.size.width * CGFloat(sold) / total) }
                if bust > 0 { Rectangle().fill(Theme.loss).frame(width: g.size.width * CGFloat(bust) / total) }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    /// Lifetime totals as plain rows, and the trophies reached.
    private func totalsGroup(_ s: GameState) -> some View {
        let trophies = Trophies.entries(s)
        let reached = trophies.filter { $0.reachedWeek != nil }.count
        let rows: [(glyph: String, title: String, value: String)] = [
            (Glyph.team, "Wages paid", store.short(s.stats.wagesPaid)),
            (Glyph.reports, "Tax paid", store.short(s.stats.taxPaid)),
            (Glyph.arrowIn, "Dividends you received", store.short(s.stats.dividendsReceived)),
            (Glyph.bank, "Interest paid", store.short(s.stats.interestPaid)),
            (Glyph.achievements, "Trophies", "\(reached) of \(trophies.count)"),
        ]
        return group("Over the whole run") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { (i: Int, r: (glyph: String, title: String, value: String)) in
                    if i > 0 { Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m) }
                    LedgerRow(leading: .glyph(r.glyph), leadingTint: Theme.inkSoft, title: r.title, value: r.value)
                }
            }
        }
    }

    /// "1 year 3 months", "14 weeks": from the week count, at 52 weeks a year.
    private func duration(weeks: Int) -> String {
        if weeks < 13 { return "\(weeks) week\(weeks == 1 ? "" : "s")" }
        let years = weeks / 52, months = (weeks % 52) * 12 / 52
        var parts: [String] = []
        if years > 0 { parts.append("\(years) year\(years == 1 ? "" : "s")") }
        if months > 0 { parts.append("\(months) month\(months == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }
}
