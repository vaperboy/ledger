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
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SectionLabel("You")
                            ValueRow(label: "Net worth", value: store.money(nw.total))
                            ValueRow(label: "Best net worth", value: store.money(max(s.stats.peakNetWorth, nw.total)))
                            ValueRow(label: "Weeks played", value: "\(s.week)")
                            ValueRow(label: "Companies sold", value: "\(s.stats.companiesSold)")
                            ValueRow(label: "Bankruptcies", value: "\(s.stats.bankruptcies)")
                            ValueRow(label: "Tax paid", value: store.money(s.stats.taxPaid))
                            ValueRow(label: "Wages paid", value: store.money(s.stats.wagesPaid))
                            ValueRow(label: "Interest paid", value: store.money(s.stats.interestPaid))
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SectionLabel("The economy")
                            ValueRow(label: "Phase", value: s.economy.phase.capitalized)
                            ValueRow(label: "Customer demand", value: String(format: "%+.0f%%", (s.economy.demand - 1) * 100))
                            ValueRow(label: "Inflation", value: pct(s.economy.inflation))
                            ValueRow(label: "Central bank rate", value: pct(s.economy.policyRate))
                            ValueRow(label: "Fuel price", value: String(format: "%+.0f%%", (s.economy.fuel - 1) * 100))
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Stats")
        }
    }
    private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
}
