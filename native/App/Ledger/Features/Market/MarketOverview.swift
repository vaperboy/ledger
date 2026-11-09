import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Overview: where you stand in your markets (combined share and rank), what you have invested and how it moved, then the week's
/// biggest movers, the openings worth a look, the threats, and the latest in your markets. Each card opens the page it is about.
struct MarketOverviewPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void
    var show: (MarketUI.Tab) -> Void

    var body: some View {
        if let e = store.engine {
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                hero(e)
                invested(e)
                EnergyMarketRow()
                movers(e)
                signals("Opportunities", store.memo("mk.opps") { MarketData.opportunities($0) } ?? [])
                signals("Threats", store.memo("mk.threats") { MarketData.threats($0) } ?? [])
                latest(e)
            }
        }
    }

    // MARK: Hero

    /// Your combined share where it is measured, with your best place among the businesses of one of your markets; otherwise the number
    /// of markets and the one step that measures them.
    private func hero(_ e: GameEngine) -> some View {
        let lines: [MarketUI.CompanyLine] = store.memo("mk.lines") { MarketData.companyLines($0) } ?? []
        let share: Double? = store.memo("mk.share") { MarketData.combinedShare($0) } ?? nil
        let best: MarketUI.CompanyLine? = lines.filter { (l: MarketUI.CompanyLine) -> Bool in l.rank != nil }
            .min { (a: MarketUI.CompanyLine, b: MarketUI.CompanyLine) -> Bool in (a.rank ?? 99) < (b.rank ?? 99) }
        let value: String
        if let share {
            value = share < 0.001 ? "Under 0.1%" : String(format: share < 0.1 ? "%.1f%%" : "%.0f%%", share * 100)
        } else {
            value = lines.isEmpty ? "No market yet" : lines.count.countText("market")
        }
        let context: String = best.map { (l: MarketUI.CompanyLine) -> String in "#\(l.rank ?? 0) of \(l.players) in \(l.trade.lowercased()), \(l.city)" } ?? ""
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            MarketHero(label: share == nil ? "Your markets" : "Your share of your markets", value: value, context: context, identifier: "market-overview-hero")
            if share == nil && !lines.isEmpty {
                Button("Share unknown: hire an analyst") { Haptics.tap(); open(.dataAnalyst) }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .padding(.leading, -Theme.Space.s)
                    .accessibilityIdentifier("market-overview-analyst")
            }
        }
    }

    // MARK: Invested

    /// Everything invested by you and your holdings, with the week's move and the result so far; a tap opens Invest.
    private func invested(_ e: GameEngine) -> some View {
        let cur: Currency = e.homeCurrency
        let p: MarketUI.Portfolio = store.memo("mk.portfolio") { MarketData.portfolio($0) } ?? MarketUI.Portfolio.empty
        let series: [Double] = MarketData.investedHistory(e)
        let week: Double = p.weekMove ?? 0
        return Button {
            Haptics.tap()
            show(.invest)
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Invested").textStyle(.label, tint: P.inkFaint)
                    Text(cur.tidyShort(p.value)).textStyle(.figure).lineLimit(1).minimumScaleFactor(0.7)
                    if !p.positions.isEmpty {
                        HStack(spacing: Theme.Space.s) {
                            if p.weekMove != nil {
                                Text(MarketFormat.money(week, cur) + " this week").textStyle(.caption, tint: P.change(week), numeric: true)
                            }
                            Text(MarketFormat.money(p.pnl, cur) + " in all").textStyle(.caption, tint: P.change(p.pnl), numeric: true)
                        }
                        .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if series.count >= 2 && series.contains(where: { (v: Double) -> Bool in abs(v) > 0.5 }) {
                    Sparkline(values: series, tint: (series.last ?? 0) >= (series.first ?? 0) ? P.gain : P.loss, filled: false)
                        .frame(width: 88, height: 32)
                        .accessibilityHidden(true)
                }
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
            }
            .padding(.vertical, Theme.Space.m)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(AcctPressStyle())
        .accessibilityIdentifier("market-overview-invested")
    }

    // MARK: Movers

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

    // MARK: Opportunities and threats

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
        case .rival(let c, let r): open(.rival(companyID: c, rivalID: r))
        case .company(let id): open(.company(id))
        case .asset(let id): open(.buy(assetID: id, owner: nil))
        case .country(let code): open(.country(code))
        case .nothing: break
        }
    }

    // MARK: Latest

    @ViewBuilder private func latest(_ e: GameEngine) -> some View {
        let events: [MarketEvent] = MarketEventRows.relevant(e, companyID: nil, limit: 4)
        if !events.isEmpty {
            MarketLabel(title: "Latest in your markets")
            MarketEventRows(events: events, showsTitle: false)
        }
    }
}
