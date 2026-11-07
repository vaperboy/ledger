import SwiftUI
import GameCore
import Countries
import Investments
import Simulation

/// A round outlined action button with its label under it (Deposit, Send, Transfer, Buy, Sell). Never filled: only Next Day is.
struct BankRoundButton: View {
    @Environment(\.outsidePalette) private var P
    var glyph: String
    var title: String
    var tint: Color? = nil
    var badge: Int = 0
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                GlyphView(glyph: glyph, size: 22, weight: 1.6, tint: tint ?? P.accent)
                    .frame(width: 56, height: 56)
                    .overlay(Circle().strokeBorder(P.lineStrong, lineWidth: 1))
                    .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: 2, y: -2) }
                Text(title).textStyle(.caption, tint: P.ink).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

enum BankTradeSide: String, Identifiable { case buy, sell; var id: String { rawValue } }

/// One name on its own page: price and trend, what you hold, and round Buy / Sell buttons that open the step flows.
struct BankAssetScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
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
                            if live.kind != .stock { BankRoundButton(glyph: BankGlyph.deposit, title: "Buy") { side = .buy } }
                            if live.quantity > 0 { BankRoundButton(glyph: BankGlyph.withdraw, title: "Sell", tint: Theme.roseGold) { side = .sell } }
                        }
                        .frame(maxWidth: live.quantity > 0 && live.kind != .stock ? .infinity : 140, alignment: .leading)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 20)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden).noSidewaysDrag()
            }
            .ledgerBackground()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .swipeBackEnabled()
            .navigationDestination(item: $side) { (s: BankTradeSide) in BankTradeFlow(quote: live, side: s) }
        }
    }

    private func priceCard(_ live: Quote, _ cur: Currency) -> some View {
        let hist: [Double] = Array(live.history.suffix(52))
        let up: Bool = (live.weekChange ?? 0) >= 0
        let note: String = live.weekChange.map { String(format: "%+.1f%% this week", $0 * 100) } ?? "No history yet"
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("PRICE").capsLabel()
                Text(cur.tidyDisplay(live.price)).textStyle(.display, numeric: true)
                Text(note).font(.system(size: 12.5)).foregroundStyle(P.change(live.weekChange ?? 0))
                if hist.count >= 2 { Sparkline(values: hist, tint: up ? P.gain : P.loss).frame(height: 90) }
                if live.kind == .crypto { Text("Very volatile: you can lose most of it.").textStyle(.caption, tint: P.caution) }
            }
        }
    }

    private func heldCard(_ live: Quote, _ cur: Currency) -> some View {
        let result: Double = live.value - live.costBasis
        let sign: String = result >= 0 ? "+" : "\u{2212}"
        return StatStrip(cells: [
            .init(label: "You hold", value: cur.tidyShort(live.value)),
            .init(label: "You paid", value: cur.tidyShort(live.costBasis)),
            .init(label: "Result if sold", value: sign + cur.tidyShort(abs(result)), tint: P.change(result)),
        ], ruled: false)
        .padding(.vertical, 12).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }
}

/// Buy or Sell in steps: 1 how much, 2 review (every figure from `buyQuote` / `sellQuote`), then the result. The review is the confirmation.
struct BankTradeFlow: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
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
                AppHeader(title: (side == .buy ? "Buy " : "Sell ") + quote.symbol, subtitle: quote.name, onBack: { back() }, backLabel: "Back")
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
                ScrollView {
                    content(e, tq, cur)
                        .padding(.horizontal, 18).padding(.bottom, 20)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden).noSidewaysDrag()
                .scrollDismissesKeyboard(.interactively)
            }
            .ledgerBackground()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .swipeBackEnabled(canStep: { step > 1 && done == nil }, step: { back() })
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
        let reason: String? = amount <= 0 ? "Enter an amount." : tq.refusal
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection(title: "How much", rule: false, trailing: {
                Text("available \(cur.tidyShort(tq.available))").textStyle(.caption, tint: P.inkFaint)
            }) {
                AmountField(title: "Amount to buy", currency: cur, amount: $amount)
                Text("Smallest order \(cur.tidyShort(tq.minimumPurchase)). The broker fee is added to the price.").textStyle(.caption, tint: P.inkFaint)
            }
            PrimaryAction(title: "Review", blockedReason: reason, identifier: "bank-trade-review") { step = 2 }
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
            PrimaryAction(title: "Review", identifier: "bank-trade-review") { step = 2 }
        }
    }

    // MARK: Step 2

    private func review(_ tq: TradeQuote, _ cur: Currency) -> some View {
        let buying: Bool = side == .buy
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Figure(label: buying ? "Leaves your accounts" : "Reaches your account", value: cur.tidyDisplay(tq.cashChange), tint: buying ? P.ink : P.gain, size: .display)
            VStack(spacing: 0) {
                line(buying ? "You buy" : "You sell", cur.tidyDisplay(tq.amount))
                line("Price", cur.tidyDisplay(quote.price))
                line("Units", String(format: "%.4f", tq.units))
                line("Broker fee", cur.tidyDisplay(tq.fee), tint: P.loss)
                Hairline()
                line("Current account and savings after", cur.tidyDisplay(tq.cashAfter), strong: true)
            }
            Text(riskNote(buying)).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
            if let r = problem { Text(r).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true) }
            PrimaryAction(title: buying ? "Confirm purchase" : "Confirm sale", blockedReason: tq.refusal, identifier: "bank-trade-confirm") { confirm(tq, cur) }
        }
    }

    private func riskNote(_ buying: Bool) -> String {
        let crypto: String = quote.kind == .crypto ? " Crypto can lose most of its value." : ""
        return buying ? "The price can fall as well as rise.\(crypto) A gain is taxed at the year end." : "A gain is taxed at the year end.\(crypto)"
    }

    private func line(_ label: String, _ value: String, tint: Color? = nil, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).textStyle(.body, tint: strong ? P.ink : P.inkSoft)
            Spacer(minLength: 8)
            Text(value).textStyle(strong ? .headline : .body, tint: tint ?? P.ink, numeric: true)
        }
        .padding(.vertical, Theme.Space.s)
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
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            EmptyState(glyph: Glyph.check, title: text, tint: P.gain)
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("bank-trade-done")
        }
    }
}
