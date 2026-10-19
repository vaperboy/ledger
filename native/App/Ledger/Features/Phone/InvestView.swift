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
            let held = list.reduce(0) { $0 + $1.value }
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    SectionTabs(items: [Brokerage.Kind.stock, .crypto, .fund], title: { $0 == .stock ? "Shares" : $0 == .crypto ? "Crypto" : "Funds" }, selection: $kind)
                        .padding(.horizontal, -Theme.Space.l)
                    GlassCard {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(kind == .stock ? "Your shares" : kind == .crypto ? "Your crypto" : "Your funds").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                            Text(cur.display(held)).font(.figure(30, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                            if kind == .crypto { Chip(text: "Very volatile: you can lose most of it", tint: Theme.caution, symbol: "exclamationmark.triangle.fill") }
                        }
                    }
                    Card {
                        LazyVStack(spacing: Theme.Space.m) {
                            ForEach(list) { q in
                                Button { selected = q } label: {
                                    HStack(spacing: Theme.Space.m) {
                                        Text(String(q.symbol.prefix(3))).font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
                                            .frame(width: 40, height: 40)
                                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.gold.opacity(0.13)))
                                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.gold.opacity(0.28), lineWidth: 0.75))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(q.name).font(.bodyText.weight(.medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                                            Text(q.value > 0 ? "You hold \(cur.short(q.value))" : q.symbol).font(.caption).foregroundStyle(q.value > 0 ? Theme.gold : Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 6)
                                        if !q.history.isEmpty { Sparkline(values: Array(q.history.suffix(26)), tint: (q.weekChange ?? 0) >= 0 ? Theme.gain : Theme.loss).frame(width: 60, height: 26) }
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(cur.display(q.price)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
                                            if let w = q.weekChange { Text(String(format: "%+.1f%%", w * 100)).font(.caption2.weight(.semibold)).foregroundStyle(Theme.change(w)) }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
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
                        GlassCard {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                Text(live.name).font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                                Text(cur.display(live.price)).font(.figure(30, weight: .bold))
                                if let w = live.weekChange { Chip(text: String(format: "%+.1f%% this week", w * 100), tint: Theme.change(w), symbol: w >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill") }
                            }
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
