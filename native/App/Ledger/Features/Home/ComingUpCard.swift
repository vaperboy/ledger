import SwiftUI
import Simulation
import Finance

/// The next few bills, taxes and instalments across all companies, with whether the money is there.
struct ComingUpCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let o = engine.financeOverview()
        if !o.upcoming.isEmpty {
            LedgerSection(title: "Coming up", trailing: {
                Chip(text: o.shortfall > 0 ? "Short by \(store.short(o.shortfall))" : "Covered", tint: o.shortfall > 0 ? Theme.loss : Theme.gain)
            }) {
                VStack(spacing: 0) {
                    ForEach(Array(o.upcoming.prefix(3).enumerated()), id: \.element.id) { i, u in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.title).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(1)
                                Text(u.daysAway <= 0 ? "Due today" : u.daysAway == 1 ? "Tomorrow" : "In \(u.daysAway) days · \(u.dateText)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Text(store.short(u.amount)).font(.figure(14.5, weight: .regular)).foregroundStyle(Theme.ivory)
                        }.padding(.vertical, 9)
                        if i < min(o.upcoming.count, 3) - 1 { Hairline() }
                    }
                    NavigationLink { FinanceView() } label: {
                        Text("Finance and taxes  →").font(.system(size: 12)).foregroundStyle(Theme.gold)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                }
            }
        }
    }
}
