import SwiftUI
import GameCore
import Finance
import Simulation

struct TaxView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine {
            let t = e.state.tax
            let cur = e.homeCurrency
            let est = PersonalFinance.taxEstimate(e.state, context: e.context)
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            SectionLabel("This year, so far")
                            Text(cur.format(est)).font(.figure(32))
                            Text("Estimated personal tax on what you have earned this year. It is settled at year end; advance payments are taken during the year.")
                                .font(.caption).foregroundStyle(Theme.ivoryMuted)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SectionLabel("Your income")
                            ValueRow(label: "Salary", value: cur.format(t.salary))
                            ValueRow(label: "Dividends", value: cur.format(t.dividends))
                            ValueRow(label: "Investment gains", value: cur.format(t.gains), tint: Theme.change(t.gains) == Theme.ivoryMuted ? Theme.ivory : Theme.change(t.gains))
                            ValueRow(label: "Interest", value: cur.format(t.interest))
                            ValueRow(label: "Sole-trader profit", value: cur.format(PersonalFinance.soleTraderIncome(e.state)))
                            Divider().overlay(Theme.hairline)
                            ValueRow(label: "Advance tax paid", value: cur.format(t.advancePaid))
                            ValueRow(label: "Tax falling due", value: cur.format(t.pending), tint: t.pending > 0 ? Theme.caution : Theme.ivory)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SectionLabel("Companies")
                            ForEach(e.state.liveCompanies.filter { $0.type != "hold" }) { co in
                                ValueRow(label: co.name, value: "set aside " + store.short(co.taxAccrued, in: co))
                            }
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Tax")
        }
    }
}
