import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct MarketInvestPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void
    @State private var ownerKey: String = "all"

    var body: some View {
        if let e = store.engine {
            let cur: Currency = e.homeCurrency
            let all: MarketUI.Portfolio = store.memo("mk.portfolio") { MarketData.portfolio($0) } ?? MarketUI.Portfolio.empty
            let owners: [MarketUI.OwnerInfo] = MarketData.owners(e)
            let chosen: MarketUI.Owner? = owners.first { (o: MarketUI.OwnerInfo) -> Bool in o.id == ownerKey }?.owner
            let p: MarketUI.Portfolio = all.only(chosen)
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                if owners.count > 1 {
                    SegmentedPill(items: ["all"] + owners.map { (o: MarketUI.OwnerInfo) -> String in o.id },
                                  title: { (k: String) -> String in k == "all" ? "All" : (owners.first { (o: MarketUI.OwnerInfo) -> Bool in o.id == k }?.name ?? k) },
                                  selection: $ownerKey, identifier: { (k: String) -> String in "invest-owner-\(k)" })
                }
                positions(p, cur)
                MarketLabel(title: "Fund manager")
                LedgerRow(leading: .glyph(Glyph.person), leadingTint: P.inkSoft, title: e.fundManager?.name ?? "Fund manager",
                          subtitle: e.fundManager.map { (m: FinanceManager.Account) -> String in "\(m.mandate.title) mandate" } ?? "",
                          value: e.fundManager == nil ? "Hire" : "", identifier: "invest-fund-manager", action: { open(.fundManager) })
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryAction(title: "Buy", identifier: "invest-buy") { open(.buy(assetID: nil, owner: chosen)) }
                    .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
                    .background(P.ground.opacity(0.96))
            }
        }
    }

    @ViewBuilder private func positions(_ p: MarketUI.Portfolio, _ cur: Currency) -> some View {
        if p.positions.isEmpty {
            EmptyState(glyph: Glyph.invest, title: "No positions")
        } else {
            MarketLabel(title: "Positions", note: "\(p.positions.count)")
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
                EmptyState(glyph: Glyph.invest, title: "Nothing held here any more")
                    .appScreen(title: "Position", subtitle: "Market \u{00B7} Invest")
            }
        }
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
        case .crypto: Text("Very volatile").textStyle(.caption, tint: P.warn)
        case .startup: Text("Sells at 72% of value").textStyle(.caption)
        case .privateEquity: Text("Sells whole, at a discount").textStyle(.caption)
        case .fund:
            if case .holding = p.owner { Text("Selling costs 0.66%").textStyle(.caption) }
        case .deposit, .groupStake, .partnership, .managed:
            if let n = p.sellNote { Text(n.tidyText).textStyle(.caption).lineLimit(1) }
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
