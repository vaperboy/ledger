import SwiftUI
import Charts
import GameCore
import Countries
import Investments
import Simulation

/// Investments inside the Bank app (BankInvest.dc style): a portfolio ring of what you hold by kind, then the names of the chosen kind as
/// rows with a small trend line. A name opens its own page (`BankAssetScreen`) where Buy and Sell are step flows. Startups, private equity
/// and stakes in groups live in the Projects tab; a summary row here opens them.
struct InvestContent: View {
    @EnvironmentObject var store: GameStore
    @State private var kind: Brokerage.Kind = .stock
    @State private var selected: Quote?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let list: [Quote] = e.quotes(kind)
            let mine: [Quote] = list.filter { $0.value > 0 }
            let rest: [Quote] = list.filter { $0.value <= 0 }
            VStack(alignment: .leading, spacing: 14) {
                PortfolioRingCard(slices: Self.slices(e), cur: cur)
                SegmentedPill(items: [Brokerage.Kind.stock, .crypto, .fund], title: { $0 == .stock ? "Shares" : $0 == .crypto ? "Crypto" : "Funds" }, selection: $kind)
                if kind == .crypto { Text("Very volatile: you can lose most of it.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
                assets(title: "You hold", rows: mine, cur: cur, empty: "You hold nothing here yet. Open a name below to look at it and buy.")
                assets(title: mine.isEmpty ? "Market" : "Other names", rows: rest, cur: cur, empty: "Nothing else is listed.")
                FundManagerCard(engine: e)
                VenturesLinkRow(engine: e)
            }
            .fullScreenCover(item: $selected) { q in BankAssetScreen(quote: q) }
        }
    }

    /// What is held by kind, from the engine's own values.
    static func slices(_ e: GameEngine) -> [PortfolioRingCard.Slice] {
        let kinds: [(Brokerage.Kind, String, Color)] = [(.stock, "Shares", Theme.gold), (.crypto, "Crypto", Theme.roseGold), (.fund, "Funds", Theme.slateBlue)]
        return kinds.map { k in
            PortfolioRingCard.Slice(id: k.1, name: k.1, value: e.quotes(k.0).reduce(0) { $0 + $1.value }, tint: k.2)
        }
    }

    @ViewBuilder private func assets(title: String, rows: [Quote], cur: Currency, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).capsLabel().padding(.horizontal, 2)
            if rows.isEmpty {
                Text(empty).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { n, q in
                        if n > 0 { Hairline() }
                        Button { Haptics.tap(); selected = q } label: { AssetRow(quote: q, cur: cur) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
        }
    }
}

/// One name: round icon, name and symbol, a small trend line over what history there is, then the value held (or the price) and the week.
struct AssetRow: View {
    var quote: Quote
    var cur: Currency

    var body: some View {
        let hist: [Double] = Array(quote.history.suffix(26))
        let w: Double? = quote.weekChange
        let up: Bool = (w ?? 0) >= 0
        let main: String = quote.value > 0 ? cur.tidyShort(quote.value) : cur.tidyDisplay(quote.price)
        let weekText: String = w.map { String(format: "%+.1f%%", $0 * 100) } ?? "-"
        let glyph: String = quote.kind == .stock ? Glyph.stats : quote.kind == .crypto ? Glyph.luxury : Glyph.richList
        HStack(spacing: 10) {
            IconCircle(glyph: glyph, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.name.tidyText).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(quote.symbol).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            Spacer(minLength: 6)
            Sparkline(values: hist, tint: up ? Theme.gain : Theme.loss, filled: false).frame(width: 58, height: 24)
            VStack(alignment: .trailing, spacing: 1) {
                Text(main).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text(weekText).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(w.map { Theme.change($0) } ?? Theme.ivoryFaint)
            }
            .frame(minWidth: 62, alignment: .trailing)
        }
        .padding(.vertical, 9).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The portfolio ring: a donut of what you hold by kind with the total in the middle, and the shares beside it.
struct PortfolioRingCard: View {
    struct Slice: Identifiable { var id: String; var name: String; var value: Double; var tint: Color }
    var slices: [Slice]
    var cur: Currency
    var title = "PORTFOLIO"
    var centerLabel = "Invested"

    var body: some View {
        let total: Double = slices.reduce(0) { $0 + max(0, $1.value) }
        let live: [Slice] = slices.filter { $0.value > 0 }
        Card(padding: 16, radius: Theme.Radius.hero) {
            HStack(spacing: 18) {
                ring(total, live)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).capsLabel()
                    ForEach(slices) { s in
                        HStack(spacing: 8) {
                            Circle().fill(s.tint).frame(width: 8, height: 8)
                            Text(s.name).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                            Spacer(minLength: 4)
                            Text(total > 0 ? String(format: "%.0f%%", s.value / total * 100) : "-").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func ring(_ total: Double, _ live: [Slice]) -> some View {
        ZStack {
            if live.isEmpty {
                Circle().strokeBorder(Theme.border, lineWidth: 14)
            } else {
                Chart(live) { s in
                    SectorMark(angle: .value("Value", s.value), innerRadius: .ratio(0.78), angularInset: 1.5).foregroundStyle(s.tint)
                }
                .chartLegend(.hidden)
            }
            VStack(spacing: 0) {
                Text(centerLabel).font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint)
                Text(cur.tidyShort(total)).font(.system(size: 17, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: 128, height: 128)
    }
}

/// What you hold in ventures (startups, private equity, stakes in groups), with a link to the Projects tab where they are managed.
struct VenturesLinkRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let cur = engine.homeCurrency
        let founded = engine.foundedStartups.filter { $0.live }.reduce(0) { $0 + $1.valuation * $1.ownership / 100 }
        let stakes = engine.startupStakes.filter { $0.live }.reduce(0) { $0 + $1.value }
        let pe = engine.privateEquityFunds.filter { $0.live }.reduce(0) { $0 + $1.nav }
        let groups = engine.bigMeetingStakes.reduce(0) { $0 + $1.value } + engine.groupStakes.reduce(0) { $0 + $1.value }
        let total = founded + stakes + pe + groups
        CardSection("Ventures") {
            Button { store.jump(to: .projects); Haptics.tap() } label: {
                RowLine(glyph: Glyph.ventures, title: "Startups, private equity and stakes",
                        subtitle: total > 0 ? "Managed in Projects > Ventures" : "Found or back a startup, commit to a fund: Projects > Ventures",
                        trailing: total > 0 ? cur.tidyShort(total) : "", chevron: true)
            }.buttonStyle(.plain)
        }
    }
}
