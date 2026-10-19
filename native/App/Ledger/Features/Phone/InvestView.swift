import SwiftUI
import GameCore
import Countries
import Investments
import Simulation

struct InvestView: View {
    @EnvironmentObject var store: GameStore
    @State private var kind: Brokerage.Kind = .stock
    @State private var selected: Quote?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let list = e.quotes(kind)
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    Picker("Kind", selection: $kind) {
                        Text("Shares").tag(Brokerage.Kind.stock); Text("Crypto").tag(Brokerage.Kind.crypto); Text("Funds").tag(Brokerage.Kind.fund)
                    }.pickerStyle(.segmented)
                    if kind == .crypto { Text("Crypto is very volatile. You can lose most of what you put in.").font(.caption).foregroundStyle(Theme.caution).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(list) { q in
                        Button { selected = q } label: {
                            Card(padding: Theme.Space.m) {
                                HStack(spacing: Theme.Space.m) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(q.symbol).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ivory)
                                        Text(q.name).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                                        if q.value > 0 { Text("You hold \(cur.short(q.value))").font(.caption2).foregroundStyle(Theme.gold) }
                                    }
                                    Spacer()
                                    if !q.history.isEmpty { Sparkline(values: Array(q.history.suffix(26)), tint: Theme.change((q.weekChange ?? 0))).frame(width: 70, height: 30) }
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(cur.format(q.price)).font(.system(.subheadline, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivory)
                                        if let w = q.weekChange { Text(String(format: "%+.1f%%", w * 100)).font(.caption2.weight(.semibold)).foregroundStyle(Theme.change(w)) }
                                    }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Invest")
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
                        Text(live.name).font(.heading)
                        ValueRow(label: "Price", value: cur.format(live.price))
                        if live.quantity > 0 {
                            ValueRow(label: "You hold", value: cur.format(live.value))
                            ValueRow(label: "You paid", value: cur.format(live.costBasis))
                            ValueRow(label: "Result if sold", value: (live.value - live.costBasis >= 0 ? "+" : "−") + cur.format(abs(live.value - live.costBasis)), tint: Theme.change(live.value - live.costBasis))
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
                                    Button(f == 1 ? "Sell all" : "Sell \(Int(f * 100))%") { store.act { $0.sellInvestment(quote.kind, symbol: quote.symbol, fraction: f) }; Haptics.success() }
                                        .buttonStyle(QuietButtonStyle(tint: Theme.roseGold))
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.l)
                }
                .ledgerBackground()
                .navigationTitle(quote.symbol).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
    }
}
