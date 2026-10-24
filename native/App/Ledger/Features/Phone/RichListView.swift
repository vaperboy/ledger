import SwiftUI
import GameCore
import Events
import Simulation

/// The richest people of your country, and you among them; below it the yearly business awards. Original: RICH57.page and V.awards56.
struct RichListView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            let st = RichList.standing(e.state, data: e.data, context: e.context)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    KeyFigures(items: [
                        .init(label: "Your place", value: st.rank.map { "#\($0)" } ?? "–", tint: Theme.gold,
                              sub: movement(st)),
                        .init(label: "Net worth", value: store.short(max(0, st.netWorth))),
                        .init(label: "Best place", value: st.best.map { "#\($0)" } ?? "–")
                    ], columns: 3)
                    if let r = st.rank, r > 100 {
                        Text("Number 100 has \(store.short(st.hundredth)). \(store.short(max(0, st.hundredth - st.netWorth))) to go.")
                            .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    } else if st.rank == nil {
                        Text("You need a positive net worth to be placed on the list.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    }
                    LedgerSection("The top ten") { people(st.top) }
                    if !st.around.isEmpty {
                        LedgerSection(st.rank.map { $0 <= 100 } ?? false ? "Around you" : "The way in") { people(st.around) }
                    }
                    awards(e.state)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Rich list")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func movement(_ st: RichList.Standing) -> String {
        guard let r = st.rank, let p = st.previous, p != r else { return "" }
        return p > r ? "▲ \(p - r) since last month" : "▼ \(r - p) since last month"
    }

    private func people(_ list: [RichList.Person]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                if i > 0 { Hairline() }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    Text(p.isYou && p.rank == 0 ? "·" : "\(p.rank)").font(.caption.monospacedDigit()).foregroundStyle(p.isYou ? Theme.gold : Theme.ivoryFaint).frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 14.5)).foregroundStyle(p.isYou ? Theme.gold : Theme.ivory)
                        Text(p.isYou ? "You" : p.source).font(.caption).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    Text(store.short(max(0, p.wealth))).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func awards(_ s: GameState) -> some View {
        let years = Awards.years(s).reversed()
        LedgerSection(title: "Business awards", trailing: { Text("\(Awards.wonCount(s)) won").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
            if years.isEmpty {
                Text("The first business awards are held at the end of the year, once you have been in business for half a year.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(Array(years.prefix(4)), id: \.year) { y in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(y.year)").capsLabel(Theme.ivoryFaint).padding(.bottom, 4)
                            ForEach(Array(y.results.enumerated()), id: \.offset) { i, r in
                                if i > 0 { Hairline() }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(Awards.name(r.kind)).font(.system(size: 14.5)).foregroundStyle(r.won ? Theme.gold : Theme.ivory)
                                        Spacer()
                                        Text(r.won ? "Won" : "Not this time").font(.caption).foregroundStyle(r.won ? Theme.gain : Theme.ivoryFaint)
                                    }
                                    Text(r.won ? "\(r.company): \(r.why)" : "Won by \(r.other). You were in the running.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }
}
