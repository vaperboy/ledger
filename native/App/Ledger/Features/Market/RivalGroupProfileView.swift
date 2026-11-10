import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct RivalGroupProfileView: View {
    @EnvironmentObject var store: GameStore
    var groupID: String
    @State private var next: MarketRoute?

    var body: some View {
        ScrollView {
            if let e = store.engine, let g = RivalGroups.group(e.state, id: groupID), !g.gone {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    identity(e, g)
                    meaning(e, g)
                    strategy(g)
                    competes(e, g)
                    moves(g)
                }
                .environment(\.insideCard, true)
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.page)
                .frame(maxWidth: 900).frame(maxWidth: .infinity)
            } else {
                NoteCard(text: "This group no longer exists.", glyph: Glyph.info).padding(Theme.Space.l)
            }
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .appScreen(title: "Rival group", subtitle: "Who owns it and how it competes")
        .navigationDestination(item: $next) { (r: MarketRoute) in MarketDestination(route: r) }
    }

    private func identity(_ e: GameEngine, _ g: RivalGroups.Group) -> some View {
        let cur = e.homeCurrency
        let items: [KeyFigures.Item] = [
            .init(label: "Sites", value: "\(g.branches)"),
            .init(label: "Yearly sales", value: cur.tidyShort(g.revenue), sub: "estimate"),
            .init(label: "Yearly profit", value: cur.tidyShort(g.profit), tint: g.profit < 0 ? Theme.loss : Theme.ivory, sub: "estimate"),
            .init(label: "Cash", value: g.cashWord, tint: g.cash <= 0 ? Theme.loss : Theme.ivory),
            .init(label: "Debt", value: g.debtWord, tint: g.debtWord == "Very high" ? Theme.caution : Theme.ivory),
        ]
        return Card(padding: Theme.Space.l, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    ThumbnailView(kind: .logo, key: "group|\(g.id)", size: 44, shape: .square, glyph: Glyph.group, initials: g.name)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(g.name).textStyle(.title, tint: Theme.ink).lineLimit(2)
                        Text("Owner \(g.owner) · \(g.strategyName)").textStyle(.caption, tint: Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                if g.inTrouble {
                    HStack(spacing: Theme.Space.s) {
                        GlyphView(glyph: Glyph.warning, size: 16, weight: 1.5, tint: Theme.caution)
                        Text("In money trouble: may sell cheaply").textStyle(.caption, tint: Theme.warn, weight: .medium)
                    }
                }
                CardLine()
                FigureStrip(items: items, columns: 3)
            }
        }
    }

    @ViewBuilder private func meaning(_ e: GameEngine, _ g: RivalGroups.Group) -> some View {
        let mine = e.rivalsOfGroup(g.id)
        let overlap: [Company] = e.state.companies.filter { $0.status == .open && g.trades.contains($0.type) && g.countries.contains($0.countryCode) }
        MoreBlock("What it means for you", card: false) {
            if overlap.isEmpty && mine.isEmpty {
                NoteCard(text: "It does not compete with any of your companies right now.", glyph: Glyph.check)
            }
            ForEach(overlap) { c in
                Button { Haptics.tap(); next = .company(c.id) } label: {
                    CardRow(glyph: Glyph.home, title: c.name, subtitle: "Same trade in \(e.cityName(c)): \(e.tradeName(c))")
                }.buttonStyle(PressableStyle())
            }
            if !mine.isEmpty {
                Text("Rivals it owns in your markets").capsLabel(Theme.ivoryFaint).padding(.horizontal, Theme.Space.xxs)
                ForEach(Array(mine.enumerated()), id: \.offset) { _, m in
                    Button { Haptics.tap(); next = .rival(companyID: m.company.id, rivalID: m.rival.id) } label: {
                        CardRow(glyph: Glyph.market, title: m.rival.name, subtitle: "competes with \(m.company.name)")
                    }.buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func strategy(_ g: RivalGroups.Group) -> some View {
        MoreBlock("How it plays") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(g.strategyText).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                CardLine()
                HStack(spacing: Theme.Space.s) {
                    GlyphView(glyph: Glyph.goals, size: 16, weight: 1.5)
                    Text("Ambition: \(g.ambition)").textStyle(.body, tint: Theme.ink, weight: .medium)
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        AcctPill(text: text)
    }

    private func tagBlock(_ title: String, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).textStyle(.caption, tint: Theme.inkFaint)
            WrapRow {
                ForEach(names, id: \.self) { n in tag(n) }
            }
        }
    }

    private func competes(_ e: GameEngine, _ g: RivalGroups.Group) -> some View {
        let trades: [String] = g.trades.map { e.data.catalog[$0]?.name ?? $0 }
        let countries: [String] = g.countries.map { e.data.countries[$0]?.name ?? $0 }
        return MoreBlock("Where it competes") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                tagBlock("Trades", trades)
                CardLine()
                tagBlock("Countries", countries)
            }
        }
    }

    private func moveRow(_ m: (week: Int, text: String), last: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(spacing: 0) {
                Circle().fill(Theme.gold).frame(width: 7, height: 7).padding(.top, Theme.Space.xs)
                if !last { Rectangle().fill(Theme.divider).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("Week \(m.week)").textStyle(.caption, tint: Theme.inkFaint)
                Text(m.text).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, last ? 0 : 10)
        }
    }

    private func moves(_ g: RivalGroups.Group) -> some View {
        let list = Array(g.moves.prefix(10))
        return MoreBlock("Recent moves") {
            if list.isEmpty {
                Text("No moves seen yet. Groups act about once a month.").textStyle(.caption, tint: Theme.inkFaint)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { (i: Int, m: (week: Int, text: String)) in moveRow(m, last: i == list.count - 1) }
                }
            }
        }
    }
}
