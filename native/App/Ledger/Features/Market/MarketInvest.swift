import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Invest: one portfolio for every owner (you and each holding's treasury): funds, crypto, shares still held, private stakes and the
/// fund manager. The hero is the total value and the result so far; the owner filter narrows it; Buy opens the buy flow.
struct MarketInvestPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void
    @State private var ownerKey: String = "all"

    var body: some View {
        if let e = store.engine {
            let cur: Currency = e.homeCurrency
            let all: MarketUI.Portfolio = store.memo("mk.portfolio") { MarketData.portfolio($0) } ?? MarketUI.Portfolio(positions: [])
            let owners: [MarketUI.OwnerInfo] = MarketData.owners(e)
            let chosen: MarketUI.Owner? = owners.first { (o: MarketUI.OwnerInfo) -> Bool in o.id == ownerKey }?.owner
            let p: MarketUI.Portfolio = all.only(chosen)
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                hero(p, chosen, cur, owners)
                if owners.count > 1 {
                    SegmentedPill(items: ["all"] + owners.map { (o: MarketUI.OwnerInfo) -> String in o.id },
                                  title: { (k: String) -> String in k == "all" ? "All" : (owners.first { (o: MarketUI.OwnerInfo) -> Bool in o.id == k }?.name ?? k) },
                                  selection: $ownerKey, identifier: { (k: String) -> String in "invest-owner-\(k)" })
                }
                positions(p, cur)
                MarketLabel(title: "Let someone invest for you")
                LedgerRow(leading: .glyph(Glyph.person), leadingTint: P.inkSoft, title: "Fund manager",
                          subtitle: e.fundManager.map { (m: FinanceManager.Account) -> String in "\(m.name) \u{00B7} \(m.mandate.title) mandate" } ?? "A professional invests for a yearly fee",
                          identifier: "invest-fund-manager", action: { open(.fundManager) })
                Text("Gains are taxed at the year end. Prices can fall as well as rise.").textStyle(.caption, tint: P.inkFaint)
                    .padding(.top, Theme.Space.s)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryAction(title: "Buy", identifier: "invest-buy") { open(.buy(assetID: nil, owner: chosen)) }
                    .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
                    .background(P.ground.opacity(0.96))
            }
            .accessibilityIdentifier("market-invest")
        }
    }

    private func hero(_ p: MarketUI.Portfolio, _ owner: MarketUI.Owner?, _ cur: Currency, _ owners: [MarketUI.OwnerInfo]) -> some View {
        let name: String? = owner.flatMap { (o: MarketUI.Owner) -> String? in owners.first { (x: MarketUI.OwnerInfo) -> Bool in x.owner == o }?.name }
        var parts: [String] = []
        if p.cost > 0.5 {
            parts.append(MarketFormat.money(p.pnl, cur) + (p.pnlShare.map { (s: Double) -> String in " (" + MarketFormat.percent(s) + ")" } ?? "") + " in all")
        }
        if let w = p.weekMove { parts.append(MarketFormat.money(w, cur) + " this week") }
        let context: String = p.positions.isEmpty ? "Nothing invested yet. Funds and crypto are a tap away." : parts.joined(separator: " \u{00B7} ")
        let series: [Double] = owner == nil || owner == .you ? MarketData.investedHistory(store) : []
        return MarketHero(label: name.map { (n: String) -> String in "Invested by \(n)" } ?? "Invested", value: cur.tidyShort(p.value), context: context,
                          contextTint: p.cost > 0.5 ? P.change(p.pnl) : nil, series: series,
                          seriesTint: (series.last ?? 0) >= (series.first ?? 0) ? P.gain : P.loss, identifier: "invest-hero")
    }

    @ViewBuilder private func positions(_ p: MarketUI.Portfolio, _ cur: Currency) -> some View {
        if p.positions.isEmpty {
            EmptyState(glyph: Glyph.invest, title: "No positions", message: "What you and your holdings buy shows here, with what you paid and how it is doing.")
        } else {
            MarketLabel(title: "Positions", note: "\(p.positions.count) \u{00B7} value \u{00B7} result")
            let total: Double = max(1, p.value)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(p.positions.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.Position)) in
                    if pair.offset > 0 { Hairline().padding(.leading, Theme.Icon.large + Theme.Space.m) }
                    PositionRow(position: pair.element, cur: cur, fraction: pair.element.value / total) { open(.position(pair.element.id)) }
                }
            }
        }
    }
}

/// One position: owner and what it is, its value, the result in gain or loss, and a thin allocation bar.
struct PositionRow: View {
    var position: MarketUI.Position
    var cur: Currency
    var fraction: Double
    var action: () -> Void
    @Environment(\.outsidePalette) private var P

    static func unitsText(_ u: Double) -> String { u >= 100 ? String(format: "%.0f", u) : (u >= 1 ? String(format: "%.2f", u) : String(format: "%.4f", u)) }

    var body: some View {
        let p: MarketUI.Position = position
        var sub: [String] = [p.ownerName]
        if let u = p.units { sub.append(Self.unitsText(u) + " units") } else { sub.append(p.assetClass.word) }
        if p.costKnown { sub.append("paid " + cur.tidyShort(p.cost)) }
        let note: String = p.pnlShare.map { (s: Double) -> String in MarketFormat.percent(s) } ?? ""
        return MarketBarRow(glyph: p.assetClass.glyph, title: p.name, subtitle: sub.joined(separator: " \u{00B7} "), value: cur.tidyShort(p.value),
                            valueNote: note, valueNoteTint: P.change(p.pnl), fraction: fraction, identifier: "invest-position-\(p.id)", action: action)
    }
}

// MARK: One position

/// A position on its own: its value and the result since bought, the price line where there is one, the figures, and Sell. Buy more is a
/// quiet link under it.
struct PositionPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var positionID: String
    @State private var next: MarketRoute?

    var body: some View {
        Group {
            if let e = store.engine, let p = MarketData.position(e, id: positionID) {
                let cur: Currency = e.homeCurrency
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    hero(p, cur)
                    figures(p, cur)
                    notes(p)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { actions(p).padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s).background(P.ground.opacity(0.96)) }
                .appScreen(title: p.name, subtitle: "\(p.ownerName) \u{00B7} \(p.assetClass.word)")
                .navigationDestination(item: $next) { (r: MarketRoute) in MarketDestination(route: r) }
            } else {
                EmptyState(glyph: Glyph.invest, title: "Nothing held here any more", message: "It was sold or has ended.")
                    .appScreen(title: "Position", subtitle: "Market \u{00B7} Invest")
            }
        }
        .accessibilityIdentifier("market-page-position")
    }

    private func hero(_ p: MarketUI.Position, _ cur: Currency) -> some View {
        var context: String = ""
        if let s = p.pnlShare { context = MarketFormat.money(p.pnl, cur) + " (" + MarketFormat.percent(s) + ") since bought" }
        if let w = p.weekChange { context += (context.isEmpty ? "" : " \u{00B7} ") + MarketFormat.percent(w) + " this week" }
        let up: Bool = (p.history.last ?? 0) >= (p.history.first ?? 0)
        return MarketHero(label: "Value", value: cur.tidyDisplay(p.value), context: context, contextTint: p.pnlShare == nil ? nil : P.change(p.pnl),
                          series: p.history, seriesTint: up ? P.gain : P.loss, identifier: "position-hero")
    }

    private func figures(_ p: MarketUI.Position, _ cur: Currency) -> some View {
        var items: [KeyFigures.Item] = []
        if let u = p.units, u > 0 {
            items.append(KeyFigures.Item(label: "Units", value: PositionRow.unitsText(u)))
            items.append(KeyFigures.Item(label: "Price now", value: cur.tidyDisplay(p.value / u)))
            if p.costKnown { items.append(KeyFigures.Item(label: "Paid per unit", value: cur.tidyDisplay(p.cost / u))) }
        } else {
            items.append(KeyFigures.Item(label: "Kind", value: p.assetClass.word))
            if !p.symbol.isEmpty { items.append(KeyFigures.Item(label: p.assetClass == .startup ? "Stage" : "Detail", value: p.symbol)) }
        }
        if p.costKnown { items.append(KeyFigures.Item(label: "You paid", value: cur.tidyShort(p.cost))) }
        items.append(KeyFigures.Item(label: "Held by", value: p.ownerName))
        return FigureRow(items: items, columns: 3, combineCells: true).padding(.top, Theme.Space.l)
    }

    @ViewBuilder private func notes(_ p: MarketUI.Position) -> some View {
        switch p.assetClass {
        case .crypto: Text("Very volatile: crypto can lose most of its value.").textStyle(.caption, tint: P.warn)
        case .shares: Text("Listed shares are no longer sold to new buyers; what you hold can be sold.").textStyle(.caption, tint: P.inkFaint)
        case .startup: Text("A stake in someone else's startup sells at about 72% of its fair value.").textStyle(.caption, tint: P.inkFaint)
        case .privateEquity: Text("A fund stake sells in one piece on the secondary market, at a discount to its value.").textStyle(.caption, tint: P.inkFaint)
        case .groupStake, .partnership: Text("This stake pays its share of profit; it is not sold here.").textStyle(.caption, tint: P.inkFaint)
        case .managed: Text("Your fund manager invests this for a yearly fee.").textStyle(.caption, tint: P.inkFaint)
        case .fund:
            if case .holding = p.owner {
                Text("The holding's treasury holds this. Selling costs 0.66%; the cash stays in the holding.").textStyle(.caption, tint: P.inkFaint)
            }
        }
    }

    @ViewBuilder private func actions(_ p: MarketUI.Position) -> some View {
        VStack(spacing: Theme.Space.xs) {
            if p.assetClass == .managed {
                PrimaryAction(title: "Manage", identifier: "position-manage") { next = .fundManager }
            } else if p.sellable {
                PrimaryAction(title: "Sell", identifier: "position-sell") { next = .sell(p.id) }
            }
            if let a = p.assetID {
                Button("Buy more") { Haptics.tap(); next = .buy(assetID: a, owner: p.owner) }
                    .buttonStyle(TertiaryButtonStyle())
                    .accessibilityIdentifier("position-buy-more")
            }
        }
    }
}
