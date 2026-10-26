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
        let businesses = s.companies.filter { $0.type != "hold" }
        let standing = businesses.filter { $0.status.isLive }.count
        let sold = businesses.filter { $0.status == .sold }.count
        let bust = businesses.filter { $0.status == .bust }.count
        let trophies = Trophies.entries(s)
        let reached = trophies.filter { $0.reachedWeek != nil }.count
        let endWorth: Double = over["nw"].isNull ? engine.netWorth.total : over["nw"].double
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                VStack(spacing: Theme.Space.m) {
                    Image(systemName: "building.columns").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Theme.roseGold)
                    Text("The ledger is closed").font(.serifTitle(28)).foregroundStyle(Theme.ivory)
                    Text(over["reason"].string == "insolvent"
                         ? "You owe more than you own and the bank has ended it."
                         : "Your account stayed empty for too long. The bank has stopped lending.")
                        .font(.bodyText).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                LedgerSection("\(s.player.name)'s run") {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("\(GameCalendar.dateString(week: 0)) to \(GameCalendar.dateString(week: endWeek)) · \(duration(weeks: endWeek + 1))")
                            .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                        KeyFigures(items: [
                            .init(label: "Best net worth", value: store.short(max(s.stats.peakNetWorth, 0))),
                            .init(label: "At the end", value: store.short(endWorth), tint: endWorth < 0 ? Theme.loss : Theme.ivory),
                            .init(label: "Weeks", value: "\(endWeek + 1)"),
                        ])
                    }
                }

                LedgerSection("Companies") {
                    if businesses.isEmpty {
                        Text("You never started or bought a company.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                    } else {
                        KeyFigures(items: [
                            .init(label: "In the run", value: "\(businesses.count)"),
                            .init(label: "Still standing", value: "\(standing)"),
                            .init(label: "Sold", value: "\(sold)"),
                            .init(label: "Went bust", value: "\(bust)", tint: bust > 0 ? Theme.loss : Theme.ivory),
                        ], columns: 4)
                    }
                }

                LedgerSection("Over the whole run") {
                    VStack(spacing: 0) {
                        ValueRow(label: "Wages paid", value: store.short(s.stats.wagesPaid)).padding(.vertical, 7)
                        Hairline()
                        ValueRow(label: "Tax paid", value: store.short(s.stats.taxPaid)).padding(.vertical, 7)
                        Hairline()
                        ValueRow(label: "Dividends you received", value: store.short(s.stats.dividendsReceived)).padding(.vertical, 7)
                        Hairline()
                        ValueRow(label: "Interest paid", value: store.short(s.stats.interestPaid)).padding(.vertical, 7)
                        Hairline()
                        ValueRow(label: "Trophies", value: "\(reached) of \(trophies.count)").padding(.vertical, 7)
                    }
                }

                VStack(spacing: Theme.Space.s) {
                    Button { store.quitToMenu() } label: { Text("Back to the start screen") }.buttonStyle(GoldButtonStyle())
                    Text("This run stays saved. Starting a new game from the start screen replaces it.")
                        .font(.caption).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Space.m)
            }
            .padding(.horizontal, Theme.Space.margin).padding(.bottom, 40)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
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
