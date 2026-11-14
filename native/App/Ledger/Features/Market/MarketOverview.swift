import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The one Market home: your share, your companies in their markets, movers, opportunities and threats.
struct MarketOverviewPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void

    var body: some View {
        if let e = store.engine {
            let lines: [MarketUI.CompanyLine] = store.memo("mk.lines") { MarketData.companyLines($0) } ?? []
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                hero(lines)
                companies(lines)
                movers(e)
                signals("Opportunities", store.memo("mk.opps") { MarketData.opportunities($0) } ?? [])
                signals("Threats", store.memo("mk.threats") { MarketData.threats($0) } ?? [])
                MarketLabel(title: "Analyst")
                LedgerRow(leading: .glyph(Glyph.person), leadingTint: P.inkSoft, title: "Data analyst",
                          value: e.hasDataAnalyst ? "Hired" : "Hire", identifier: "market-data-analyst", action: { open(.dataAnalyst) })
            }
        }
    }

    private func hero(_ lines: [MarketUI.CompanyLine]) -> some View {
        let share: Double? = store.memo("mk.share") { MarketData.combinedShare($0) } ?? nil
        let best: MarketUI.CompanyLine? = lines.filter { (l: MarketUI.CompanyLine) -> Bool in l.rank != nil }
            .min { (a: MarketUI.CompanyLine, b: MarketUI.CompanyLine) -> Bool in (a.rank ?? 99) < (b.rank ?? 99) }
        let value: String
        if let share {
            value = share < 0.001 ? "Under 0.1%" : String(format: share < 0.1 ? "%.1f%%" : "%.0f%%", share * 100)
        } else {
            value = lines.isEmpty ? "No market yet" : lines.count.countText("market")
        }
        let ranked: String = best.map { (l: MarketUI.CompanyLine) -> String in "#\(l.rank ?? 0) of \(l.players) in \(l.trade.lowercased()), \(l.city)" } ?? ""
        let context: String = share == nil && !lines.isEmpty ? "Share unknown" : ranked
        return MarketHero(label: share == nil ? "Your markets" : "Your share of your markets", value: value, context: context, identifier: "market-overview-hero")
    }

    @ViewBuilder private func companies(_ lines: [MarketUI.CompanyLine]) -> some View {
        if lines.isEmpty {
            EmptyState(glyph: Glyph.market, title: "No market yet")
        } else {
            MarketLabel(title: "Your companies")
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.CompanyLine)) in
                    if pair.offset > 0 { Hairline() }
                    companyRow(pair.element)
                }
            }
        }
    }

    private func companyRow(_ l: MarketUI.CompanyLine) -> some View {
        let rank: String = l.rank.map { (r: Int) -> String in "#\(r) of \(l.players)" } ?? "\(l.players) in the market"
        var notes: [String] = []
        if let g = l.priceGap { notes.append(abs(g) < 0.03 ? "price as market" : "price " + MarketFormat.percent(g, decimals: 0)) }
        if let r = l.ratingGap { notes.append(String(format: "\u{2605} %+.1f", r)) }
        let arrow: String = l.trend.map { (t: Double) -> String in t > 0.05 ? "\u{2191} " : (t < -0.05 ? "\u{2193} " : "") } ?? ""
        let tint: Color? = l.trend.map { (t: Double) -> Color in P.change(t) }
        return LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: store.engine?.state.company(l.id)?.type ?? "", glyph: Glyph.home)),
                         title: l.name, subtitle: "\(l.trade) \u{00B7} \(l.city) \u{00B7} \(rank)", value: arrow + l.shareText, valueTint: tint,
                         valueNote: notes.joined(separator: " \u{00B7} "), lineLimit: 1, identifier: "market-company-\(l.id)",
                         action: { open(.company(l.id)) })
    }

    @ViewBuilder private func movers(_ e: GameEngine) -> some View {
        let list: [MarketUI.Mover] = store.memo("mk.movers") { MarketData.movers($0) } ?? []
        if !list.isEmpty {
            MarketLabel(title: "Movers", note: "this week")
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.Mover)) in
                    if pair.offset > 0 { Hairline() }
                    moverRow(pair.element, e.homeCurrency)
                }
            }
        }
    }

    private func moverRow(_ m: MarketUI.Mover, _ cur: Currency) -> some View {
        let change: String = m.points ? MarketFormat.points(m.change) : MarketFormat.percent(m.change)
        let note: String = m.amount.map { (a: Double) -> String in MarketFormat.money(a, cur) } ?? ""
        return HStack(spacing: Theme.Space.m) {
            Image(systemName: m.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: Theme.Icon.small, weight: .medium))
                .foregroundStyle(P.change(m.change))
                .frame(width: Theme.Icon.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(m.title.tidyText).textStyle(.headline).lineLimit(1)
                Text(m.detail.tidyText).textStyle(.caption).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(change).textStyle(.headline, tint: P.change(m.change), numeric: true)
                if !note.isEmpty { Text(note).textStyle(.caption, tint: P.inkFaint, numeric: true) }
            }
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func signals(_ title: String, _ list: [MarketUI.Signal]) -> some View {
        if !list.isEmpty {
            MarketLabel(title: title)
            VStack(spacing: Theme.Space.s) {
                ForEach(list) { (s: MarketUI.Signal) in
                    MarketSignalTile(signal: s) { follow(s.target) }
                }
            }
        }
    }

    private func follow(_ t: MarketUI.Signal.Target) {
        switch t {
        case .rival(let c, _): open(.company(c))
        case .company(let id): open(.company(id))
        case .asset(let id): open(.buy(assetID: id, owner: nil))
        case .country(let code): open(.country(code))
        case .nothing: break
        }
    }
}
