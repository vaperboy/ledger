import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The profile of one rival group (C5, original `grp27`): who owns it, its strategy and ambition, how big and how healthy it looks, where
/// and in what trades it competes, the rivals of yours it owns, and its recent moves. Opened from the Market screen's group list.
/// Read-only: what you can do about a rival (price war, buying a distressed one) stays on the rival's own page under Market.
struct RivalGroupProfileView: View {
    @EnvironmentObject var store: GameStore
    var groupID: String

    var body: some View {
        ScrollView {
            if let e = store.engine, let g = RivalGroups.group(e.state, id: groupID), !g.gone {
                let cur = e.homeCurrency
                let mine = e.rivalsOfGroup(g.id)
                let overlap = e.state.companies.filter { $0.status.isLive && g.trades.contains($0.type) && g.countries.contains($0.countryCode) }
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(g.name).font(.serifTitle(26)).foregroundStyle(Theme.ivory)
                        Text("Owner \(g.owner) · \(g.strategyName)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        if g.inTrouble { Chip(text: "In money trouble: may sell cheaply", tint: Theme.caution) }
                    }
                    KeyFigures(items: [
                        .init(label: "Sites", value: "\(g.branches)"),
                        .init(label: "Yearly sales", value: cur.tidyShort(g.revenue), sub: "estimate"),
                        .init(label: "Yearly profit", value: cur.tidyShort(g.profit), tint: g.profit < 0 ? Theme.loss : Theme.ivory, sub: "estimate"),
                        .init(label: "Cash", value: g.cashWord, tint: g.cash <= 0 ? Theme.loss : Theme.ivory),
                        .init(label: "Debt", value: g.debtWord, tint: g.debtWord == "Very high" ? Theme.caution : Theme.ivory),
                    ])
                    LedgerSection("What it means for you") {
                        VStack(alignment: .leading, spacing: 6) {
                            if overlap.isEmpty && mine.isEmpty {
                                Text("It does not compete with any of your companies right now.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                            }
                            ForEach(overlap) { c in
                                Button { Haptics.tap(); store.openCompany(c.id, section: .market) } label: {
                                    GroupLinkRow(title: c.name, sub: "Same trade in \(e.cityName(c)): \(e.tradeName(c))")
                                }.buttonStyle(.plain)
                            }
                            if !mine.isEmpty {
                                Text("Rivals it owns in your markets").capsLabel(Theme.ivoryFaint).padding(.top, 4)
                                ForEach(Array(mine.enumerated()), id: \.offset) { _, m in
                                    FlatRow(label: m.rival.name, value: m.company.name, sub: "competes with")
                                }
                            }
                        }
                    }
                    LedgerSection("How it plays") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(g.strategyText).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                            Text("Ambition: \(g.ambition)").font(.system(size: 12.5)).foregroundStyle(Theme.ivory)
                        }
                    }
                    LedgerSection("Where it competes") {
                        VStack(alignment: .leading, spacing: 6) {
                            FlatRow(label: "Trades", value: g.trades.map { e.data.catalog[$0]?.name ?? $0 }.joined(separator: ", "), rule: false)
                            FlatRow(label: "Countries", value: g.countries.map { e.data.countries[$0]?.name ?? $0 }.joined(separator: ", "))
                        }
                    }
                    LedgerSection("Recent moves") {
                        if g.moves.isEmpty {
                            Text("No moves seen yet. Groups act about once a month.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(g.moves.prefix(10).enumerated()), id: \.offset) { _, m in
                                    Text("Week \(m.week): \(m.text)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 900).frame(maxWidth: .infinity)
            } else {
                Text("This group no longer exists.").foregroundStyle(Theme.ivoryMuted).padding(Theme.Space.margin)
            }
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .appScreen(title: "Rival group", subtitle: "Who owns it and how it competes", tab: .group)
    }
}
