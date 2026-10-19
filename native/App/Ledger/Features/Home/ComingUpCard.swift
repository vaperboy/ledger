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
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        SectionLabel("Coming up").padding(Theme.Space.l)
                        Spacer()
                        Chip(text: o.shortfall > 0 ? "Short by \(store.short(o.shortfall))" : "Covered", tint: o.shortfall > 0 ? Theme.loss : Theme.gain).padding(.trailing, Theme.Space.l)
                    }
                    ForEach(o.upcoming.prefix(3)) { u in
                        Divider().overlay(Theme.hairline)
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.title).font(.bodyText).foregroundStyle(Theme.ivory)
                                Text(u.daysAway <= 0 ? "Due today" : u.daysAway == 1 ? "Tomorrow" : "In \(u.daysAway) days · \(u.dateText)").font(.caption).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer()
                            Text(store.short(u.amount)).font(.figure(16)).foregroundStyle(Theme.ivory)
                        }.padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
                    }
                    NavigationLink { FinanceView() } label: {
                        HStack { Text("Finance & taxes").font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: "chevron.right") }
                            .foregroundStyle(Theme.gold).padding(Theme.Space.l)
                    }
                }
            }
        }
    }
}
