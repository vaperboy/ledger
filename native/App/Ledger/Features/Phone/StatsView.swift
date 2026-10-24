import SwiftUI
import GameCore
import Finance
import Simulation

struct StatsView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine {
            let s = e.state
            let nw = e.netWorth
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            Text("Best net worth").capsLabel()
                            Text(store.money(max(s.stats.peakNetWorth, nw.total))).font(.hero(34)).minimumScaleFactor(0.6).lineLimit(1)
                            HStack(spacing: Theme.Space.l) {
                                Stat(label: "Now", value: store.short(nw.total), tint: nw.total < 0 ? Theme.loss : Theme.ivory)
                                Stat(label: "Weeks played", value: "\(s.week)")
                                Stat(label: "Companies sold", value: "\(s.stats.companiesSold)")
                            }
                        }
                    }
                    TrophiesPreview()
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            SectionLabel("What it cost")
                            ListRow(symbol: "building.columns.fill", tint: Theme.ivoryMuted, title: "Tax paid", trailing: store.short(s.stats.taxPaid))
                            ListRow(symbol: "person.2.fill", tint: Theme.ivoryMuted, title: "Wages paid", trailing: store.short(s.stats.wagesPaid))
                            ListRow(symbol: "percent", tint: Theme.ivoryMuted, title: "Interest paid", trailing: store.short(s.stats.interestPaid))
                            ListRow(symbol: "xmark.octagon.fill", tint: s.stats.bankruptcies > 0 ? Theme.loss : Theme.ivoryMuted, title: "Bankruptcies", trailing: "\(s.stats.bankruptcies)")
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            HStack { SectionLabel("The economy"); Spacer(); Chip(text: s.economy.phase.capitalized, tint: phaseTint(s.economy.phase)) }
                            ListRow(symbol: "cart.fill", tint: Theme.ivoryMuted, title: "Customer demand", trailing: String(format: "%+.0f%%", (s.economy.demand - 1) * 100), trailingTint: Theme.change(s.economy.demand - 1))
                            ListRow(symbol: "chart.line.uptrend.xyaxis", tint: Theme.ivoryMuted, title: "Inflation", trailing: pct(s.economy.inflation))
                            ListRow(symbol: "building.columns", tint: Theme.ivoryMuted, title: "Central bank rate", trailing: pct(s.economy.policyRate))
                            ListRow(symbol: "fuelpump.fill", tint: Theme.ivoryMuted, title: "Fuel price", trailing: String(format: "%+.0f%%", (s.economy.fuel - 1) * 100), trailingTint: Theme.change(1 - s.economy.fuel))
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Stats")
        }
    }
    private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    private func phaseTint(_ p: String) -> Color { p == "boom" ? Theme.gain : p == "recession" ? Theme.loss : p == "slowdown" ? Theme.caution : Theme.ivoryMuted }
}
