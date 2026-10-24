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
                VStack(spacing: Theme.Space.l) {
                    SectionTabs(items: [Brokerage.Kind.stock, .crypto, .fund], title: { $0 == .stock ? "Shares" : $0 == .crypto ? "Crypto" : "Funds" }, selection: $kind)
                        .padding(.horizontal, -Theme.Space.margin)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind == .stock ? "Your shares" : kind == .crypto ? "Your crypto" : "Your funds").capsLabel()
                        Text(cur.display(held)).font(.hero(36)).minimumScaleFactor(0.6).lineLimit(1)
                        if kind == .crypto { Chip(text: "Very volatile: you can lose most of it", tint: Theme.caution, symbol: "exclamationmark.triangle.fill").padding(.top, 2) }
                    }
                    Card {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, q in
                                if i > 0 { Hairline() }
                                Button { selected = q } label: {
                                    HStack(spacing: Theme.Space.m) {
                                        Text(String(q.symbol.prefix(4))).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.gold)
                                            .frame(width: 40, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(q.name).font(.bodyText.weight(.medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                                            Text(q.value > 0 ? "You hold \(cur.tidyShort(q.value))" : q.symbol).font(.caption).foregroundStyle(q.value > 0 ? Theme.gold : Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 6)
                                        if !q.history.isEmpty { Sparkline(values: Array(q.history.suffix(26)), tint: (q.weekChange ?? 0) >= 0 ? Theme.gain : Theme.loss).frame(width: 60, height: 26) }
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(cur.display(q.price)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
                                            if let w = q.weekChange { Text(String(format: "%+.1f%%", w * 100)).font(.caption2.weight(.semibold)).foregroundStyle(Theme.change(w)) }
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    FundManagerCard(engine: e)
                    VenturesLinkRow(engine: e)
                }
                .sheet(item: $selected) { q in TradeSheet(quote: q).presentationDetents([.medium, .large]) }
        }
    }
}

struct TradeSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var quote: Quote
    @State private var amount = 0.0

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let live = e.quotes(quote.kind).first { $0.id == quote.id } ?? quote
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(live.name).capsLabel()
                            Text(cur.display(live.price)).font(.hero(36))
                            if let w = live.weekChange { Chip(text: String(format: "%+.1f%% this week", w * 100), tint: Theme.change(w), symbol: w >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill") }
                        }
                        if live.quantity > 0 {
                            Card {
                                VStack(spacing: Theme.Space.s) {
                                    ValueRow(label: "You hold", value: cur.display(live.value))
                                    ValueRow(label: "You paid", value: cur.display(live.costBasis))
                                    ValueRow(label: "Result if sold", value: (live.value - live.costBasis >= 0 ? "+" : "−") + cur.display(abs(live.value - live.costBasis)), tint: Theme.change(live.value - live.costBasis))
                                }
                            }
                        }
                        AmountField(title: "Amount to buy", currency: cur, amount: $amount)
                        Button("Buy") {
                            switch store.act({ $0.buyInvestment(quote.kind, symbol: quote.symbol, amount: amount) }) {
                            case .ok?: Haptics.success(); store.show("Bought \(quote.symbol).", tone: "good"); amount = 0
                            case .tooSmall?: store.show("Too small an order.", tone: "warn")
                            case .delisted?: store.show("Trading has stopped.", tone: "bad")
                            default: Haptics.warning(); store.show("Not enough cash.", tone: "warn")
                            }
                        }.buttonStyle(GoldButtonStyle())
                        Text("A small broker fee applies. Gains are taxed at year end.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        if live.quantity > 0 {
                            HStack {
                                ForEach([0.25, 0.5, 1.0], id: \.self) { f in
                                    Button(f == 1 ? "Sell all" : "Sell \(Int(f * 100))%") {
                                        let before = live.value
                                        store.act { $0.sellInvestment(quote.kind, symbol: quote.symbol, fraction: f) }
                                        let after = store.engine?.quotes(quote.kind).first { $0.id == quote.id }?.value ?? 0
                                        if after < before { Haptics.success(); store.show("Sold \(cur.tidyShort(before - after)) of \(quote.symbol), less the broker fee.", tone: "good") }
                                        else { Haptics.warning(); store.show("Nothing was sold: trading in \(quote.symbol) has stopped.", tone: "warn") }
                                    }
                                        .buttonStyle(QuietButtonStyle(tint: Theme.roseGold))
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.margin)
                }
                .ledgerBackground()
                .navigationTitle(quote.symbol).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
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
