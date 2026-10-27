import SwiftUI
import GameCore
import Countries
import Investments
import Simulation

/// A round outlined action button with its label under it (Deposit, Send, Transfer, Buy, Sell). Never filled: only Next Day is.
struct BankRoundButton: View {
    var glyph: String
    var title: String
    var tint: Color = Theme.gold
    var badge: Int = 0
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                GlyphView(glyph: glyph, size: 22, weight: 1.6, tint: tint)
                    .frame(width: 56, height: 56)
                    .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                    .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: 2, y: -2) }
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.ivory).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

enum BankTradeSide: String, Identifiable { case buy, sell; var id: String { rawValue } }

/// One name on its own page: price and trend, what you hold, and round Buy / Sell buttons that open the step flows.
struct BankAssetScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var quote: Quote
    @State private var side: BankTradeSide?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let live: Quote = e.quotes(quote.kind).first { $0.id == quote.id } ?? quote
            VStack(spacing: 0) {
                AppHeader(title: live.symbol, subtitle: live.name, onBack: { dismiss() }, backLabel: "Back")
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        priceCard(live, cur)
                        if live.quantity > 0 { heldCard(live, cur) }
                        HStack(spacing: 0) {
                            BankRoundButton(glyph: BankGlyph.deposit, title: "Buy") { side = .buy }
                            if live.quantity > 0 { BankRoundButton(glyph: BankGlyph.withdraw, title: "Sell", tint: Theme.roseGold) { side = .sell } }
                        }
                        .frame(maxWidth: live.quantity > 0 ? .infinity : 140, alignment: .leading)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 40)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .ledgerBackground()
            .fullScreenCover(item: $side) { s in BankTradeFlow(quote: live, side: s) }
        }
    }

    private func priceCard(_ live: Quote, _ cur: Currency) -> some View {
        let hist: [Double] = Array(live.history.suffix(52))
        let up: Bool = (live.weekChange ?? 0) >= 0
        let note: String = live.weekChange.map { String(format: "%+.1f%% this week", $0 * 100) } ?? "No history yet"
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("PRICE").capsLabel()
                Text(cur.tidyDisplay(live.price)).font(.system(size: 30, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text(note).font(.system(size: 12.5)).foregroundStyle(Theme.change(live.weekChange ?? 0))
                if hist.count >= 2 { Sparkline(values: hist, tint: up ? Theme.gain : Theme.loss).frame(height: 90) }
                if live.kind == .crypto { Text("Very volatile: you can lose most of it.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
            }
        }
    }

    private func heldCard(_ live: Quote, _ cur: Currency) -> some View {
        let result: Double = live.value - live.costBasis
        let sign: String = result >= 0 ? "+" : "\u{2212}"
        return StatStrip(cells: [
            .init(label: "You hold", value: cur.tidyShort(live.value)),
            .init(label: "You paid", value: cur.tidyShort(live.costBasis)),
            .init(label: "Result if sold", value: sign + cur.tidyShort(abs(result)), tint: Theme.change(result)),
        ], ruled: false)
        .padding(.vertical, 12).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Buy or Sell in steps: 1 how much, 2 review (every figure from `buyQuote` / `sellQuote`), then the result. The review is the confirmation.
struct BankTradeFlow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var quote: Quote
    var side: BankTradeSide
    @State private var step = 1
    @State private var amount = 0.0
    @State private var fraction = 0.5
    @State private var done: String?
    @State private var problem: String?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let tq: TradeQuote = side == .buy ? e.buyQuote(quote.kind, symbol: quote.symbol, amount: amount)
                                              : e.sellQuote(quote.kind, symbol: quote.symbol, fraction: fraction)
            VStack(spacing: 0) {
                AppHeader(title: (side == .buy ? "Buy " : "Sell ") + quote.symbol, subtitle: quote.name, onBack: { back() }, backLabel: step == 1 || done != nil ? "Close" : "Back")
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
                ScrollView {
                    content(e, tq, cur)
                        .padding(.horizontal, 18).padding(.bottom, 40)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .ledgerBackground()
        }
    }

    private func back() {
        if done != nil || step == 1 { dismiss() } else { step = 1; problem = nil }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ tq: TradeQuote, _ cur: Currency) -> some View {
        if let done {
            doneCard(done)
        } else if step == 1 {
            if side == .buy { buyAmount(tq, cur) } else { sellAmount(e, tq, cur) }
        } else {
            review(tq, cur)
        }
    }

    // MARK: Step 1

    private func buyAmount(_ tq: TradeQuote, _ cur: Currency) -> some View {
        let blocked: Bool = amount <= 0 || tq.refusal != nil
        return VStack(alignment: .leading, spacing: 14) {
            Card(padding: 16, radius: Theme.Radius.hero) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("HOW MUCH").capsLabel()
                        Spacer()
                        Text("available \(cur.tidyShort(tq.available))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                    AmountField(title: "Amount to buy", currency: cur, amount: $amount)
                    Text("Smallest order \(cur.tidyShort(tq.minimumPurchase)). The broker fee is added to the price.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            if amount > 0, let r = tq.refusal { Text(r).font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true) }
            QuietButton(title: "Review", fullWidth: true) { step = 2 }.disabled(blocked).opacity(blocked ? 0.4 : 1)
        }
    }

    private func sellAmount(_ e: GameEngine, _ tq: TradeQuote, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW MUCH TO SELL").capsLabel().padding(.horizontal, 2)
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                let q = e.sellQuote(quote.kind, symbol: quote.symbol, fraction: f)
                ChoiceCard(title: f == 1 ? "Sell all" : "Sell \(Int(f * 100))%", subtitle: "about \(cur.tidyShort(q.cashChange)) after the fee",
                           trailing: cur.tidyShort(q.amount), selected: fraction == f) { fraction = f }
            }
            QuietButton(title: "Review", fullWidth: true) { step = 2 }
        }
    }

    // MARK: Step 2

    private func review(_ tq: TradeQuote, _ cur: Currency) -> some View {
        let buying: Bool = side == .buy
        return VStack(alignment: .leading, spacing: 14) {
            Card(padding: 16, radius: Theme.Radius.hero) {
                VStack(spacing: 0) {
                    line(buying ? "You buy" : "You sell", cur.tidyDisplay(tq.amount))
                    line("Price", cur.tidyDisplay(quote.price))
                    line("Units", String(format: "%.4f", tq.units))
                    line("Broker fee", cur.tidyDisplay(tq.fee), tint: Theme.loss)
                    Hairline().padding(.vertical, 6)
                    line(buying ? "Leaves your accounts" : "Reaches your account", cur.tidyDisplay(tq.cashChange), tint: buying ? Theme.ivory : Theme.gain, strong: true)
                    line("Current account and savings after", cur.tidyDisplay(tq.cashAfter))
                }
            }
            Text(riskNote(buying)).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            if let r = problem ?? tq.refusal { Text(r).font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true) }
            QuietButton(title: buying ? "Confirm purchase" : "Confirm sale", tint: buying ? Theme.gold : Theme.roseGold, fullWidth: true) { confirm(tq, cur) }
                .disabled(tq.refusal != nil).opacity(tq.refusal != nil ? 0.4 : 1)
        }
    }

    private func riskNote(_ buying: Bool) -> String {
        let crypto: String = quote.kind == .crypto ? " Crypto can lose most of its value." : ""
        return buying ? "The price can fall as well as rise.\(crypto) A gain is taxed at the year end." : "A gain is taxed at the year end.\(crypto)"
    }

    private func line(_ label: String, _ value: String, tint: Color = Theme.ivory, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13.5)).foregroundStyle(strong ? Theme.ivory : Theme.ivoryMuted)
            Spacer(minLength: 8)
            Text(value).font(.system(size: strong ? 16 : 14, weight: strong ? .medium : .regular).monospacedDigit()).foregroundStyle(tint)
        }
        .padding(.vertical, 5)
    }

    private func confirm(_ tq: TradeQuote, _ cur: Currency) {
        if side == .buy {
            switch store.act({ $0.buyInvestment(quote.kind, symbol: quote.symbol, amount: tq.amount) }) {
            case .ok?: Haptics.success(); done = "Bought \(cur.tidyDisplay(tq.amount)) of \(quote.symbol). The fee was \(cur.tidyDisplay(tq.fee))."
            case .tooSmall?: Haptics.warning(); problem = "Too small an order."
            case .delisted?: Haptics.warning(); problem = "Trading in \(quote.symbol) has stopped."
            default: Haptics.warning(); problem = "Not enough money for that."
            }
        } else {
            let before: Double = store.engine?.quotes(quote.kind).first { $0.id == quote.id }?.value ?? 0
            store.act { $0.sellInvestment(quote.kind, symbol: quote.symbol, fraction: fraction) }
            let after: Double = store.engine?.quotes(quote.kind).first { $0.id == quote.id }?.value ?? 0
            if after < before { Haptics.success(); done = "Sold \(cur.tidyDisplay(before - after)) of \(quote.symbol), less the broker fee." }
            else { Haptics.warning(); problem = "Nothing was sold: trading in \(quote.symbol) has stopped." }
        }
        if let done { store.show(done, tone: "good") }
    }

    private func doneCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                GlyphView(glyph: "M5 12 L10 17 L19 7", size: 18, weight: 2, tint: Theme.gain)
                Text(text).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.gain.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.gain.opacity(0.45), lineWidth: 1))
            QuietButton(title: "Done", fullWidth: true) { dismiss() }
        }
    }
}
