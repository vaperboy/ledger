import SwiftUI
import GameCore
import Finance
import Simulation

/// Your record: best net worth first, then the state of the economy around you, what the run has cost so far, and the latest trophies.
struct StatsView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine {
            let s = e.state
            let nw = e.netWorth
            let phase = s.economy.phase
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HeroFigure(label: "Best net worth", value: store.money(max(s.stats.peakNetWorth, nw.total)))
                    FigureCard(items: [
                        .init(label: "Now", value: store.short(nw.total), tint: nw.total < 0 ? Theme.loss : Theme.ivory),
                        .init(label: "Weeks played", value: "\(s.week)"),
                        .init(label: "Companies sold", value: "\(s.stats.companiesSold)")
                    ])
                    CardSection(title: "The economy", trailing: { Chip(text: phase.capitalized, tint: phaseTint(phase)) }) {
                        if phase == "recession" || phase == "slowdown" {
                            Text(phase == "recession" ? "The economy is in recession. Customer demand and rates below show how it reaches you." : "The economy is slowing. Customer demand and rates below show how it reaches you.")
                                .font(.system(size: 13)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                            CardLine()
                        }
                        VStack(spacing: 0) {
                            FlatRow(label: "Customer demand", value: String(format: "%+.0f%%", (s.economy.demand - 1) * 100), tint: Theme.change(s.economy.demand - 1), rule: false)
                            FlatRow(label: "Inflation", value: pct(s.economy.inflation))
                            FlatRow(label: "Central bank rate", value: pct(s.economy.policyRate))
                            FlatRow(label: "Fuel price", value: String(format: "%+.0f%%", (s.economy.fuel - 1) * 100), tint: Theme.change(1 - s.economy.fuel))
                        }
                    }
                    CardSection("What it has cost") {
                        VStack(spacing: 0) {
                            FlatRow(label: "Tax paid", value: store.short(s.stats.taxPaid), rule: false)
                            FlatRow(label: "Wages paid", value: store.short(s.stats.wagesPaid))
                            FlatRow(label: "Interest paid", value: store.short(s.stats.interestPaid))
                            FlatRow(label: "Bankruptcies", value: "\(s.stats.bankruptcies)", tint: s.stats.bankruptcies > 0 ? Theme.loss : Theme.ivory)
                        }
                    }
                    TrophiesPreview()
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
        }
    }
    private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    private func phaseTint(_ p: String) -> Color { p == "boom" ? Theme.gain : p == "recession" ? Theme.loss : p == "slowdown" ? Theme.caution : Theme.ivoryMuted }
}
