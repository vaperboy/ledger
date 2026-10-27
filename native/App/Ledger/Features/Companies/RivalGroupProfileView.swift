import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The profile of one rival group (C5, original `grp27`): who owns it, its strategy and ambition, how big and how healthy it looks, where
/// and in what trades it competes, the rivals of yours it owns, and its recent moves. Opened from the Market screen's group list.
/// Read-only: what you can do about a rival (price war, buying a distressed one) stays on the rival's own page under Market.
/// Laid out as a dossier: an identity card with the money figures, what it means for you, the strategy, tags for its trades and
/// countries, and a timeline of its moves.
struct RivalGroupProfileView: View {
    @EnvironmentObject var store: GameStore
    var groupID: String

    var body: some View {
        ScrollView {
            if let e = store.engine, let g = RivalGroups.group(e.state, id: groupID), !g.gone {
                VStack(alignment: .leading, spacing: 16) {
                    identity(e, g)
                    meaning(e, g)
                    strategy(g)
                    competes(e, g)
                    moves(g)
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 900).frame(maxWidth: .infinity)
            } else {
                NoteCard(text: "This group no longer exists.", glyph: Glyph.info).padding(18)
            }
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .appScreen(title: "Rival group", subtitle: "Who owns it and how it competes", tab: .group)
    }

    // MARK: Identity and money

    private func identity(_ e: GameEngine, _ g: RivalGroups.Group) -> some View {
        let cur = e.homeCurrency
        let items: [KeyFigures.Item] = [
            .init(label: "Sites", value: "\(g.branches)"),
            .init(label: "Yearly sales", value: cur.tidyShort(g.revenue), sub: "estimate"),
            .init(label: "Yearly profit", value: cur.tidyShort(g.profit), tint: g.profit < 0 ? Theme.loss : Theme.ivory, sub: "estimate"),
            .init(label: "Cash", value: g.cashWord, tint: g.cash <= 0 ? Theme.loss : Theme.ivory),
            .init(label: "Debt", value: g.debtWord, tint: g.debtWord == "Very high" ? Theme.caution : Theme.ivory),
        ]
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconCircle(glyph: Glyph.group, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory).lineLimit(2)
                        Text("Owner \(g.owner) · \(g.strategyName)").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer(minLength: 0)
                }
                if g.inTrouble {
                    HStack(spacing: 8) {
                        GlyphView(glyph: Glyph.warning, size: 16, weight: 1.5, tint: Theme.caution)
                        Text("In money trouble: may sell cheaply").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.caution)
                    }
                }
                CardLine()
                FigureStrip(items: items, columns: 3)
            }
        }
    }

    // MARK: What it means for you

    @ViewBuilder private func meaning(_ e: GameEngine, _ g: RivalGroups.Group) -> some View {
        let mine = e.rivalsOfGroup(g.id)
        let overlap: [Company] = e.state.companies.filter { $0.status.isLive && g.trades.contains($0.type) && g.countries.contains($0.countryCode) }
        MoreBlock(title: "What it means for you", card: false) {
            if overlap.isEmpty && mine.isEmpty {
                NoteCard(text: "It does not compete with any of your companies right now.", glyph: Glyph.check)
            }
            ForEach(overlap) { c in
                Button { Haptics.tap(); store.openCompany(c.id, section: .market) } label: {
                    CardRow(glyph: Glyph.home, title: c.name, subtitle: "Same trade in \(e.cityName(c)): \(e.tradeName(c))")
                }.buttonStyle(.plain)
            }
            if !mine.isEmpty {
                Text("Rivals it owns in your markets").capsLabel(Theme.ivoryFaint).padding(.horizontal, 2)
                ForEach(Array(mine.enumerated()), id: \.offset) { _, m in
                    CardRow(glyph: Glyph.market, title: m.rival.name, subtitle: "competes with \(m.company.name)", chevron: false)
                }
            }
        }
    }

    // MARK: How it plays

    private func strategy(_ g: RivalGroups.Group) -> some View {
        MoreBlock("How it plays") {
            VStack(alignment: .leading, spacing: 8) {
                Text(g.strategyText).font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                CardLine()
                HStack(spacing: 8) {
                    GlyphView(glyph: Glyph.goals, size: 16, weight: 1.5)
                    Text("Ambition: \(g.ambition)").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory)
                }
            }
        }
    }

    // MARK: Where it competes

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.ivory)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
    }

    private func tagBlock(_ title: String, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            WrapRow {
                ForEach(names, id: \.self) { n in tag(n) }
            }
        }
    }

    private func competes(_ e: GameEngine, _ g: RivalGroups.Group) -> some View {
        let trades: [String] = g.trades.map { e.data.catalog[$0]?.name ?? $0 }
        let countries: [String] = g.countries.map { e.data.countries[$0]?.name ?? $0 }
        return MoreBlock("Where it competes") {
            VStack(alignment: .leading, spacing: 12) {
                tagBlock("Trades", trades)
                CardLine()
                tagBlock("Countries", countries)
            }
        }
    }

    // MARK: Recent moves

    private func moveRow(_ m: (week: Int, text: String), last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(Theme.gold).frame(width: 7, height: 7).padding(.top, 5)
                if !last { Rectangle().fill(Theme.divider).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("Week \(m.week)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                Text(m.text).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, last ? 0 : 10)
        }
    }

    private func moves(_ g: RivalGroups.Group) -> some View {
        let list = Array(g.moves.prefix(10))
        return MoreBlock("Recent moves") {
            if list.isEmpty {
                Text("No moves seen yet. Groups act about once a month.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { (i: Int, m: (week: Int, text: String)) in moveRow(m, last: i == list.count - 1) }
                }
            }
        }
    }
}
