import SwiftUI
import GameCore
import Simulation

/// The whole group at a glance: every company's contribution, and the owner's money flows between them.
struct GroupView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        NavigationStack {
            if let e = store.engine {
                let cos = e.state.liveCompanies.filter { $0.type != "hold" }
                ScrollView {
                    VStack(spacing: Theme.Space.l) {
                        let nw = e.netWorth
                        Card {
                            VStack(alignment: .leading, spacing: Theme.Space.m) {
                                SectionLabel("Group value")
                                Text(store.money(nw.companies)).font(.figure(32)).foregroundStyle(Theme.ivory)
                                ValueRow(label: "Cash held by companies", value: store.short(cos.reduce(0) { $0 + max(0, $1.cash) }))
                                ValueRow(label: "Companies", value: "\(cos.count)")
                                ValueRow(label: "Staff", value: "\(cos.reduce(0) { $0 + $1.staff.count })")
                            }
                        }
                        if cos.isEmpty {
                            Card { Text("You have no companies yet. Start one from the Phone.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                        }
                        ForEach(cos) { co in
                            Button { store.openCompanyID = co.id; store.tab = .companies } label: {
                                Card {
                                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                                        HStack(spacing: Theme.Space.m) { IconBadge(symbol: "building.2.fill", tint: co.cash < 0 ? Theme.loss : Theme.gold, size: 38); Text(co.name).font(.heading); Spacer(); StatusChip(company: co) }
                                        MiniBars(values: e.monthlyProfitSeries(co)).frame(height: 36)
                                        HStack {
                                            Stat(label: "Cash", value: store.short(co.cash, in: co), tint: co.cash < 0 ? Theme.loss : Theme.ivory)
                                            Spacer()
                                            Stat(label: "Last week", value: store.short(co.lastWeekRevenue, in: co))
                                        }
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .ledgerBackground()
                .navigationTitle("Group")
            }
        }
    }
}
