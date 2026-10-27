import SwiftUI
import GameCore
import Countries
import Investments
import Simulation

/// Shares, crypto and funds, and your fund manager: the Deposits tab of the Bank Investments account. Startups, private equity and stakes in groups are
/// ventures with their own workflows and live in the Projects tab; a summary row here opens them.
struct InvestContent: View {
    @EnvironmentObject var store: GameStore
    @State private var kind: Brokerage.Kind = .stock
    @State private var selected: Quote?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let list = e.quotes(kind)
            let held = list.reduce(0) { $0 + $1.value }
            let mine = list.filter { $0.value > 0 }
            let rest = list.filter { $0.value <= 0 }
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPill(items: [Brokerage.Kind.stock, .crypto, .fund], title: { $0 == .stock ? "Shares" : $0 == .crypto ? "Crypto" : "Funds" }, selection: $kind)
                HeroFigure(label: kind == .stock ? "Your shares" : kind == .crypto ? "Your crypto" : "Your funds", value: cur.tidyDisplay(held),
                           note: kind == .crypto ? "Very volatile: you can lose most of it" : "")
                holdings(mine, rest, cur)
                FundManagerCard(engine: e)
                VenturesLinkRow(engine: e)
            }
            .sheet(item: $selected) { q in TradeSheet(quote: q).presentationDetents([.medium, .large]) }
        }
    }

    @ViewBuilder private func holdings(_ mine: [Quote], _ rest: [Quote], _ cur: Currency) -> some View {
        if !mine.isEmpty {
            CardSection(title: "You hold", trailing: { Text("tap to buy or sell").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) { quoteList(mine, cur) }
        } else {
            NoteCard(text: "You hold nothing here yet. Tap a name below to buy.")
        }
        CardSection(title: mine.isEmpty ? "Market" : "Other names", trailing: { if mine.isEmpty { Text("tap to buy").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) } }) {
            if rest.isEmpty { Text("Nothing else is listed.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
            else { quoteList(rest, cur) }
        }
    }

    private func quoteList(_ list: [Quote], _ cur: Currency) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, q in
                if i > 0 { CardLine() }
                Button { selected = q; Haptics.tap() } label: { quoteRow(q, cur) }.buttonStyle(.plain)
            }
        }
    }

    private func quoteRow(_ q: Quote, _ cur: Currency) -> some View {
        let up: Bool = (q.weekChange ?? 0) >= 0
        return HStack(spacing: Theme.Space.m) {
            Text(String(q.symbol.prefix(4))).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.gold)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(q.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(q.value > 0 ? "You hold \(cur.tidyShort(q.value))" : q.symbol).font(.system(size: 12)).foregroundStyle(q.value > 0 ? Theme.gold : Theme.ivoryMuted)
            }
            Spacer(minLength: 6)
            if !q.history.isEmpty { Sparkline(values: Array(q.history.suffix(26)), tint: up ? Theme.gain : Theme.loss).frame(width: 56, height: 24) }
            VStack(alignment: .trailing, spacing: 2) {
                Text(cur.tidyDisplay(q.price)).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                if let w = q.weekChange { Text(String(format: "%+.1f%%", w * 100)).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.change(w)) }
            }
            GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct TradeSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var quote: Quote
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let live = e.quotes(quote.kind).first { $0.id == quote.id } ?? quote
            let fee = max(cur.scaledPrice(29), amount * 0.001)
            let cash = e.state.cash
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AppHeader(title: quote.symbol, subtitle: live.name)
                        HeroFigure(label: "Price", value: cur.tidyDisplay(live.price),
                                   note: live.weekChange.map { String(format: "%+.1f%% this week", $0 * 100) } ?? "")
                        if live.quantity > 0 { FigureCard(items: heldItems(live, cur)) }
                        buyCard(cur, fee, cash)
                        if live.quantity > 0 { sellCard(live, cur) }
                    }
                    .padding(Theme.Space.margin)
                }
                .ledgerBackground()
                .toolbar(.hidden, for: .navigationBar)
                .confirmAction($pending)
            }
        }
    }

    private func heldItems(_ live: Quote, _ cur: Currency) -> [FigureCard.Item] {
        let result: Double = live.value - live.costBasis
        return [
            .init(label: "You hold", value: cur.tidyShort(live.value)),
            .init(label: "You paid", value: cur.tidyShort(live.costBasis)),
            .init(label: "Result if sold", value: (result >= 0 ? "+" : "−") + cur.tidyShort(abs(result)), tint: Theme.change(result)),
        ]
    }

    private func buyCard(_ cur: Currency, _ fee: Double, _ cash: Double) -> some View {
        let note: String = amount > 0 ? "Broker fee about \(cur.tidyShort(fee)). Gains are taxed at year end." : "A small broker fee applies. Gains are taxed at year end."
        let blocked: Bool = amount <= 0 || amount > cash
        return CardSection(title: "Buy", trailing: { Text("current account \(cur.tidyShort(cash))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
            AmountField(title: "Amount to buy", currency: cur, amount: $amount)
            if amount > cash { Text("More than the current account holds. Move money from savings in Bank first.").font(.system(size: 12)).foregroundStyle(Theme.caution) }
            else { Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            QuietButton(title: amount > 0 ? "Buy \(cur.tidyShort(amount))" : "Enter an amount", fullWidth: true) { buy(cur, fee) }
                .disabled(blocked).opacity(blocked ? 0.4 : 1)
        }
    }

    private func sellCard(_ live: Quote, _ cur: Currency) -> some View {
        CardSection(title: "Sell", trailing: { Text("fee comes off the proceeds").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
            HStack(spacing: 8) {
                ForEach([0.25, 0.5, 1.0], id: \.self) { f in
                    QuietButton(title: f == 1 ? "Sell all" : "Sell \(Int(f * 100))%", tint: Theme.roseGold, fullWidth: true) { sell(live, f, cur) }
                }
            }
        }
    }

    /// Buying and selling shares is routine and reversible: it runs at once (the fee was previewed on the sheet) unless the amount is
    /// large against cash, more than 10% of it, when the confirmation shows the cost and risk first.
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
            case .ok?: Haptics.success(); store.show("Bought \(cur.tidyShort(a)) of \(quote.symbol).", tone: "good"); amount = 0
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
            if after < before { Haptics.success(); store.show("Sold \(cur.tidyShort(before - after)) of \(quote.symbol), less the broker fee.", tone: "good") }
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
