import SwiftUI
import GameCore
import Countries
import Investments
import Simulation

/// Shares, crypto and funds, and your fund manager: a section of Group > Money. Startups, private equity and stakes in groups are
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
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                SegmentedChoice(items: [Brokerage.Kind.stock, .crypto, .fund], title: { $0 == .stock ? "Shares" : $0 == .crypto ? "Crypto" : "Funds" }, selection: $kind)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind == .stock ? "Your shares" : kind == .crypto ? "Your crypto" : "Your funds").capsLabel()
                    Text(cur.tidyDisplay(held)).font(.hero(36)).minimumScaleFactor(0.6).lineLimit(1)
                    if kind == .crypto { Chip(text: "Very volatile: you can lose most of it", tint: Theme.caution, symbol: "exclamationmark.triangle.fill").padding(.top, 2) }
                }
                if !mine.isEmpty {
                    LedgerSection(title: "You hold", trailing: { Text("tap to buy or sell").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) { quoteList(mine, cur) }
                } else {
                    Text("You hold nothing here yet. Tap a name below to buy.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                }
                LedgerSection(title: mine.isEmpty ? "Market" : "Other names", trailing: { if mine.isEmpty { Text("tap to buy").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) } }) {
                    if rest.isEmpty { Text("Nothing else is listed.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                    else { quoteList(rest, cur) }
                }
                FundManagerCard(engine: e)
                VenturesLinkRow(engine: e)
            }
            .sheet(item: $selected) { q in TradeSheet(quote: q).presentationDetents([.medium, .large]) }
        }
    }

    private func quoteList(_ list: [Quote], _ cur: Currency) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, q in
                if i > 0 { Hairline() }
                Button { selected = q; Haptics.tap() } label: {
                    HStack(spacing: Theme.Space.m) {
                        Text(String(q.symbol.prefix(4))).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.gold)
                            .frame(width: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.name).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(1)
                            Text(q.value > 0 ? "You hold \(cur.tidyShort(q.value))" : q.symbol).font(.caption).foregroundStyle(q.value > 0 ? Theme.gold : Theme.ivoryFaint)
                        }
                        Spacer(minLength: 6)
                        if !q.history.isEmpty { Sparkline(values: Array(q.history.suffix(26)), tint: (q.weekChange ?? 0) >= 0 ? Theme.gain : Theme.loss).frame(width: 56, height: 24) }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(cur.tidyDisplay(q.price)).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
                            if let w = q.weekChange { Text(String(format: "%+.1f%%", w * 100)).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.change(w)) }
                        }
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
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
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(live.name).capsLabel()
                            Text(cur.tidyDisplay(live.price)).font(.hero(36))
                            if let w = live.weekChange { Chip(text: String(format: "%+.1f%% this week", w * 100), tint: Theme.change(w), symbol: w >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill") }
                        }
                        if live.quantity > 0 {
                            KeyFigures(items: [
                                .init(label: "You hold", value: cur.tidyShort(live.value)),
                                .init(label: "You paid", value: cur.tidyShort(live.costBasis)),
                                .init(label: "Result if sold", value: (live.value - live.costBasis >= 0 ? "+" : "−") + cur.tidyShort(abs(live.value - live.costBasis)), tint: Theme.change(live.value - live.costBasis)),
                            ])
                        }
                        LedgerSection(title: "Buy", trailing: { Text("current account \(cur.tidyShort(cash))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                AmountField(title: "Amount to buy", currency: cur, amount: $amount)
                                if amount > cash { Text("More than the current account holds. Move money from savings in Bank first.").font(.caption).foregroundStyle(Theme.caution) }
                                else if amount > 0 { Text("Broker fee about \(cur.tidyShort(fee)). Gains are taxed at year end.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                                else { Text("A small broker fee applies. Gains are taxed at year end.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                                Button(amount > 0 ? "Buy \(cur.tidyShort(amount))" : "Enter an amount") { buy(cur, fee) }
                                    .buttonStyle(GoldButtonStyle()).disabled(amount <= 0 || amount > cash)
                            }
                        }
                        if live.quantity > 0 {
                            LedgerSection(title: "Sell", trailing: { Text("fee comes off the proceeds").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
                                HStack {
                                    ForEach([0.25, 0.5, 1.0], id: \.self) { f in
                                        Button(f == 1 ? "Sell all" : "Sell \(Int(f * 100))%") { sell(live, f, cur) }
                                            .buttonStyle(QuietButtonStyle(tint: Theme.roseGold))
                                    }
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.margin)
                }
                .ledgerBackground()
                .navigationTitle(quote.symbol).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmAction($pending)
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
        LedgerSection("Ventures") {
            Button { store.jump(to: .projects); Haptics.tap() } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Startups, private equity and stakes").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text(total > 0 ? "Managed in Projects > Ventures" : "Found or back a startup, commit to a fund: Projects > Ventures").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    if total > 0 { Text(cur.tidyShort(total)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory) }
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }.padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}
