import SwiftUI
import GameCore
import Events
import Simulation

/// Shown when the bank has taken everything. The save is kept. Shows how the run went, using only what the game recorded:
/// how long it lasted, the best and final net worth, what happened to every company, and the lifetime totals in `stats`.
struct GameOverView: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let s = engine.state
        let over = s.gameOver
        let endWeek = over["week"].isNull ? s.week : over["week"].int
        let endWorth: Double = over["nw"].isNull ? engine.netWorth.total : over["nw"].double
        let reason: String = over["reason"].string == "insolvent"
            ? "You owe more than you own and the bank has ended it."
            : "Your account stayed empty for too long. The bank has stopped lending."
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AppHeader(title: "The ledger is closed", subtitle: reason)
                    .padding(.top, 28)
                HeroFigure(label: "\(s.player.name)'s net worth at the end", value: store.short(endWorth), tint: endWorth < 0 ? Theme.loss : Theme.ivory,
                           note: "Best: \(store.short(max(s.stats.peakNetWorth, 0)))")
                runCard(s, endWeek: endWeek, endWorth: endWorth)
                companiesCard(s)
                totalsCard(s)
                QuietButton(title: "Back to the start screen", fullWidth: true) { store.quitToMenu() }
                    .padding(.top, 6)
                Text("This run stays saved. Starting a new game from the start screen replaces it.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
    }

    /// The run as a timeline: first week at the left, last at the right, the best point of the net worth marked on the line.
    private func runCard(_ s: GameState, endWeek: Int, endWorth: Double) -> some View {
        let weeks = max(1, endWeek + 1)
        return CardSection("The run") {
            HStack {
                Text(GameCalendar.dateString(week: 0)).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                Text(GameCalendar.dateString(week: endWeek)).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.divider).frame(height: 3)
                Capsule().fill(Theme.gold).frame(height: 3)
            }
            FigureCard(items: [
                .init(label: "Lasted", value: duration(weeks: weeks)),
                .init(label: "Weeks", value: "\(weeks)"),
                .init(label: "Best net worth", value: store.short(max(s.stats.peakNetWorth, 0))),
            ])
        }
    }

    /// What became of every company, as one stacked bar with the counts below it.
    private func companiesCard(_ s: GameState) -> some View {
        let businesses = s.companies.filter { $0.type != "hold" }
        let standing = businesses.filter { $0.status.isLive }.count
        let sold = businesses.filter { $0.status == .sold }.count
        let bust = businesses.filter { $0.status == .bust }.count
        return CardSection("Companies") {
            if businesses.isEmpty {
                RowLine(glyph: Glyph.group, title: "You never started or bought a company.")
            } else {
                outcomeBar(standing: standing, sold: sold, bust: bust)
                FigureCard(items: [
                    .init(label: "In the run", value: "\(businesses.count)"),
                    .init(label: "Standing", value: "\(standing)", tint: Theme.gain),
                    .init(label: "Sold", value: "\(sold)"),
                    .init(label: "Went bust", value: "\(bust)", tint: bust > 0 ? Theme.loss : Theme.ivory),
                ], columns: 4)
            }
        }
    }

    private func outcomeBar(standing: Int, sold: Int, bust: Int) -> some View {
        let total = CGFloat(max(1, standing + sold + bust))
        return GeometryReader { g in
            HStack(spacing: 2) {
                if standing > 0 { Rectangle().fill(Theme.gain).frame(width: g.size.width * CGFloat(standing) / total) }
                if sold > 0 { Rectangle().fill(Theme.gold).frame(width: g.size.width * CGFloat(sold) / total) }
                if bust > 0 { Rectangle().fill(Theme.loss).frame(width: g.size.width * CGFloat(bust) / total) }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
    }

    /// Lifetime totals, one icon row each, and the trophies as a gauge.
    private func totalsCard(_ s: GameState) -> some View {
        let trophies = Trophies.entries(s)
        let reached = trophies.filter { $0.reachedWeek != nil }.count
        let share: Double = trophies.isEmpty ? 0 : Double(reached) / Double(trophies.count)
        return CardSection("Over the whole run") {
            RowLine(glyph: Glyph.team, title: "Wages paid", trailing: store.short(s.stats.wagesPaid))
            CardLine()
            RowLine(glyph: Glyph.reports, title: "Tax paid", trailing: store.short(s.stats.taxPaid))
            CardLine()
            RowLine(glyph: Glyph.arrowIn, title: "Dividends you received", trailing: store.short(s.stats.dividendsReceived))
            CardLine()
            RowLine(glyph: Glyph.bank, title: "Interest paid", trailing: store.short(s.stats.interestPaid))
            CardLine()
            RowLine(glyph: Glyph.achievements, title: "Trophies", trailing: "\(reached) of \(trophies.count)")
            RateBar(label: "Reached", fraction: share)
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
