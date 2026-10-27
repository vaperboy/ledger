import SwiftUI
import Charts
import GameCore
import Countries
import Investments
import Simulation

/// Shares, crypto and funds, and your fund manager: the Deposits tab of the Bank Investments account. Laid out as a portfolio statement:
/// a value trend with an allocation bar, then holdings and the rest of the market as sharp tables. A name opens its own sheet, and Buy and
/// Sell are sheets of their own. Startups, private equity and stakes in groups live in the Projects tab; a summary row here opens them.
struct InvestContent: View {
    @EnvironmentObject var store: GameStore
    @State private var kind: Brokerage.Kind = .stock
    @State private var selected: Quote?

    private static let holdingColumns: [TableColumn] = [TableColumn(title: "Holding"), TableColumn(title: "Value", width: 78), TableColumn(title: "Week", width: 54)]
    private static let marketColumns: [TableColumn] = [TableColumn(title: "Name"), TableColumn(title: "Price", width: 78), TableColumn(title: "Week", width: 54)]

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let list = e.quotes(kind)
            let mine = list.filter { $0.value > 0 }
            let rest = list.filter { $0.value <= 0 }
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPill(items: [Brokerage.Kind.stock, .crypto, .fund], title: { $0 == .stock ? "Shares" : $0 == .crypto ? "Crypto" : "Funds" }, selection: $kind)
                PortfolioPanel(kind: kind, holdings: mine, cur: cur)
                holdingsBlock(mine, cur)
                marketBlock(rest, empty: mine.isEmpty, cur)
                FundManagerCard(engine: e)
                VenturesLinkRow(engine: e)
            }
            .sheet(item: $selected) { q in TradeSheet(quote: q).presentationDetents([.medium, .large]) }
        }
    }

    @ViewBuilder private func holdingsBlock(_ mine: [Quote], _ cur: Currency) -> some View {
        if mine.isEmpty {
            NoteCard(text: "You hold nothing here yet. Tap a name below to look at it and buy.")
        } else {
            sectionLabel("You hold", hint: "tap a row to buy or sell")
            SharpTable {
                TableHeader(columns: Self.holdingColumns)
                ForEach(mine) { q in tableRow(q, Self.holdingColumns, first: cur.tidyShort(q.value)) }
            }
        }
    }

    @ViewBuilder private func marketBlock(_ rest: [Quote], empty: Bool, _ cur: Currency) -> some View {
        sectionLabel(empty ? "Market" : "Other names", hint: empty ? "tap a name to look at it" : "")
        if rest.isEmpty {
            Text("Nothing else is listed.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
        } else {
            SharpTable {
                TableHeader(columns: Self.marketColumns)
                ForEach(rest) { q in tableRow(q, Self.marketColumns, first: cur.tidyDisplay(q.price)) }
            }
        }
    }

    private func sectionLabel(_ title: String, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).capsLabel()
            Spacer(minLength: 8)
            if !hint.isEmpty { Text(hint).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
        }
        .padding(.horizontal, 2).padding(.top, 4)
    }

    private func tableRow(_ q: Quote, _ columns: [TableColumn], first: String) -> some View {
        let w: Double? = q.weekChange
        let weekText: String = w.map { String(format: "%+.1f%%", $0 * 100) } ?? "-"
        let weekTint: Color = w.map { Theme.change($0) } ?? Theme.ivoryFaint
        return TableRow(columns: columns, title: q.name, note: q.symbol, values: [first, weekText], valueTints: [Theme.ivory, weekTint]) { selected = q }
    }
}

/// The portfolio statement of one asset kind: the value held, its trend over the weeks every holding has history for, and an allocation bar.
private struct PortfolioPanel: View {
    var kind: Brokerage.Kind
    var holdings: [Quote]
    var cur: Currency

    private struct Point: Identifiable { var id: Int; var value: Double }
    private struct Slice: Identifiable { var id: String; var name: String; var share: Double; var tint: Color }

    private static let palette: [Color] = [Theme.gold, Theme.gain, Theme.roseGold, Theme.ivoryMuted, Theme.caution, Theme.loss]

    var body: some View {
        let held: Double = holdings.reduce(0) { $0 + $1.value }
        let points: [Point] = trend()
        let first: Double = points.first?.value ?? 0
        let delta: Double = (points.last?.value ?? 0) - first
        Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                header(held, delta, hasTrend: points.count >= 2 && first > 0, pct: first > 0 ? delta / first : 0)
                if points.count >= 2 { chart(points) }
                if held > 0 { allocation(held) }
                if kind == .crypto { Text("Very volatile: you can lose most of it.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
            }
        }
    }

    private func header(_ held: Double, _ delta: Double, hasTrend: Bool, pct: Double) -> some View {
        let name: String = kind == .stock ? "Your shares" : kind == .crypto ? "Your crypto" : "Your funds"
        let glyph: String = kind == .stock ? Glyph.stats : kind == .crypto ? Glyph.luxury : Glyph.richList
        let sign: String = delta >= 0 ? "+" : "\u{2212}"
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            IconCircle(glyph: glyph, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).capsLabel()
                Text(cur.tidyDisplay(held)).font(.system(size: 28, weight: .regular, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
            Spacer(minLength: 6)
            if hasTrend {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sign + cur.tidyShort(abs(delta))).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.change(delta))
                    Text(String(format: "%+.1f%% over the period", pct * 100)).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func chart(_ points: [Point]) -> some View {
        let lo: Double = points.map(\.value).min() ?? 0
        let hi: Double = points.map(\.value).max() ?? 1
        let pad: Double = max((hi - lo) * 0.15, hi * 0.002)
        let up: Bool = (points.last?.value ?? 0) >= (points.first?.value ?? 0)
        let tint: Color = up ? Theme.gain : Theme.loss
        return Chart(points) { p in
            AreaMark(x: .value("Week", p.id), yStart: .value("Floor", lo - pad), yEnd: .value("Value", p.value)).foregroundStyle(tint.opacity(0.10))
            LineMark(x: .value("Week", p.id), y: .value("Value", p.value)).foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                AxisValueLabel { if let d = v.as(Double.self) { Text(cur.tidyShort(d)).font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint) } }
            }
        }
        .frame(height: 96)
    }

    private func allocation(_ held: Double) -> some View {
        let slices: [Slice] = slicesOf(held)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Allocation").font(.system(size: 10.5)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.ivoryFaint)
            GeometryReader { geo in
                let usable: CGFloat = geo.size.width - CGFloat(slices.count - 1) * 2
                HStack(spacing: 2) {
                    ForEach(slices) { s in
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(s.tint).frame(width: max(3, usable * s.share))
                    }
                }
            }
            .frame(height: 8)
            ForEach(slices) { s in
                HStack(spacing: 8) {
                    Circle().fill(s.tint).frame(width: 7, height: 7)
                    Text(s.name).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(String(format: "%.0f%%", s.share * 100)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func slicesOf(_ held: Double) -> [Slice] {
        let sorted: [Quote] = holdings.sorted { $0.value > $1.value }
        let top: [Quote] = Array(sorted.prefix(5))
        var out: [Slice] = []
        for (i, q) in top.enumerated() {
            out.append(Slice(id: q.id, name: q.name, share: held > 0 ? q.value / held : 0, tint: Self.palette[i % Self.palette.count]))
        }
        let otherValue: Double = sorted.dropFirst(5).reduce(0) { $0 + $1.value }
        if otherValue > 0 { out.append(Slice(id: "other", name: "Other", share: otherValue / held, tint: Theme.ivoryDim)) }
        return out
    }

    /// Value of today's holdings at each past week's price, over the weeks every held name has history for.
    private func trend() -> [Point] {
        let n: Int = holdings.map { $0.history.count }.min() ?? 0
        if n < 2 { return [] }
        return (0..<n).map { i in
            let total: Double = holdings.reduce(0) { $0 + $1.quantity * $1.history[$1.history.count - n + i] }
            return Point(id: i, value: total)
        }
    }
}

/// One name: its price trend and what you hold, with Buy and Sell opening sheets of their own.
struct TradeSheet: View {
    enum Side: String, Identifiable { case buy, sell; var id: String { rawValue } }
    @EnvironmentObject var store: GameStore
    var quote: Quote
    @State private var side: Side?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let live = e.quotes(quote.kind).first { $0.id == quote.id } ?? quote
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AppHeader(title: quote.symbol, subtitle: live.name)
                        priceBlock(live, cur)
                        if live.quantity > 0 { FigureCard(items: heldItems(live, cur)) }
                        actions(live)
                    }
                    .padding(Theme.Space.margin)
                }
                .ledgerBackground()
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $side) { s in TradeTicket(quote: quote, side: s).presentationDetents([.medium, .large]) }
            }
        }
    }

    private func priceBlock(_ live: Quote, _ cur: Currency) -> some View {
        let hist: [Double] = Array(live.history.suffix(52))
        let up: Bool = (live.weekChange ?? 0) >= 0
        let note: String = live.weekChange.map { String(format: "%+.1f%% this week", $0 * 100) } ?? "No history yet"
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Price").capsLabel()
                Text(cur.tidyDisplay(live.price)).font(.system(size: 28, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text(note).font(.system(size: 12.5)).foregroundStyle(Theme.change(live.weekChange ?? 0))
                if hist.count >= 2 { Sparkline(values: hist, tint: up ? Theme.gain : Theme.loss).frame(height: 56) }
            }
        }
    }

    private func heldItems(_ live: Quote, _ cur: Currency) -> [FigureCard.Item] {
        let result: Double = live.value - live.costBasis
        return [
            .init(label: "You hold", value: cur.tidyShort(live.value)),
            .init(label: "You paid", value: cur.tidyShort(live.costBasis)),
            .init(label: "Result if sold", value: (result >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(result)), tint: Theme.change(result)),
        ]
    }

    private func actions(_ live: Quote) -> some View {
        HStack(spacing: 10) {
            QuietButton(title: "Buy", fullWidth: true) { side = .buy }
            if live.quantity > 0 { QuietButton(title: "Sell", tint: Theme.roseGold, fullWidth: true) { side = .sell } }
        }
    }
}

/// The Buy or Sell sheet of one name. Buying and selling shares is routine and reversible: it runs at once (the fee was previewed here)
/// unless the amount is large against cash, more than 10% of it, when the confirmation shows the cost and risk first.
struct TradeTicket: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var quote: Quote
    var side: TradeSheet.Side
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let live = e.quotes(quote.kind).first { $0.id == quote.id } ?? quote
            let fee = max(cur.scaledPrice(29), amount * 0.001)
            let cash = e.state.cash
            let title: String = (side == .buy ? "Buy " : "Sell ") + quote.symbol
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AppHeader(title: title, subtitle: "\(live.name) at \(cur.tidyDisplay(live.price))")
                        if side == .buy { buyCard(cur, fee, cash) } else { sellCard(live, cur) }
                    }
                    .padding(Theme.Space.margin)
                }
                .ledgerBackground()
                .toolbar(.hidden, for: .navigationBar)
                .confirmAction($pending)
            }
        }
    }

    private func buyCard(_ cur: Currency, _ fee: Double, _ cash: Double) -> some View {
        let note: String = amount > 0 ? "Broker fee about \(cur.tidyShort(fee)). Gains are taxed at year end." : "A small broker fee applies. Gains are taxed at year end."
        let blocked: Bool = amount <= 0 || amount > cash
        return CardSection(title: "Amount", trailing: { Text("current account \(cur.tidyShort(cash))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
            AmountField(title: "Amount to buy", currency: cur, amount: $amount)
            if amount > cash { Text("More than the current account holds. Move money from savings in Bank first.").font(.system(size: 12)).foregroundStyle(Theme.caution) }
            else { Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            QuietButton(title: amount > 0 ? "Buy \(cur.tidyShort(amount))" : "Enter an amount", fullWidth: true) { buy(cur, fee) }
                .disabled(blocked).opacity(blocked ? 0.4 : 1)
        }
    }

    private func sellCard(_ live: Quote, _ cur: Currency) -> some View {
        CardSection(title: "How much", trailing: { Text("fee comes off the proceeds").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
            Text("You hold \(cur.tidyShort(live.value)).").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            HStack(spacing: 8) {
                ForEach([0.25, 0.5, 1.0], id: \.self) { f in
                    QuietButton(title: f == 1 ? "Sell all" : "Sell \(Int(f * 100))%", tint: Theme.roseGold, fullWidth: true) { sell(live, f, cur) }
                }
            }
        }
    }

    private func submit(_ p: PendingAction, size: Double? = nil) {
        let cash: Double = max(0, store.engine?.state.cash ?? 0)
        let value: Double = size ?? p.amount ?? 0
        if value > cash * 0.10 { pending = p } else { p.run() }
    }

    private func buy(_ cur: Currency, _ fee: Double) {
        let a = amount
        let p = PendingAction(title: "Buy \(cur.tidyShort(a)) of \(quote.symbol)?",
                                message: "Paid from your current account with a broker fee of about \(cur.tidyDisplay(fee)). The price can fall as well as rise" + (quote.kind == .crypto ? "; crypto can lose most of its value" : "") + ". A gain is taxed at year end.",
                                button: "Buy", amount: a, currency: cur) {
            switch store.act({ $0.buyInvestment(quote.kind, symbol: quote.symbol, amount: a) }) {
            case .ok?: Haptics.success(); store.show("Bought \(cur.tidyShort(a)) of \(quote.symbol).", tone: "good"); amount = 0; dismiss()
            case .tooSmall?: Haptics.warning(); store.show("Too small an order.", tone: "warn")
            case .delisted?: Haptics.warning(); store.show("Trading has stopped.", tone: "bad")
            default: Haptics.warning(); store.show("Not enough cash.", tone: "warn")
            }
        }
        submit(p)
    }

    private func sell(_ live: Quote, _ f: Double, _ cur: Currency) {
        let proceeds = live.value * f
        let p = PendingAction(title: f == 1 ? "Sell all of \(quote.symbol)?" : "Sell \(Int(f * 100))% of \(quote.symbol)?",
                                message: "About \(cur.tidyDisplay(proceeds)) at today's price, less the broker fee. A gain is taxed at year end.", button: "Sell") {
            let before = live.value
            store.act { $0.sellInvestment(quote.kind, symbol: quote.symbol, fraction: f) }
            let after = store.engine?.quotes(quote.kind).first { $0.id == quote.id }?.value ?? 0
            if after < before { Haptics.success(); store.show("Sold \(cur.tidyShort(before - after)) of \(quote.symbol), less the broker fee.", tone: "good"); dismiss() }
            else { Haptics.warning(); store.show("Nothing was sold: trading in \(quote.symbol) has stopped.", tone: "warn") }
        }
        submit(p, size: proceeds)
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
