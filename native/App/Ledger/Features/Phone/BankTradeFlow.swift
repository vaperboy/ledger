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
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        priceCard(live, cur)
                        if live.quantity > 0 { heldCard(live, cur) }
                    }
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden).noSidewaysDrag()
                .safeAreaInset(edge: .bottom, spacing: 0) { tradeBar(live) }
            }
            .ledgerBackground()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .swipeBackEnabled()
            .navigationDestination(item: $side) { (s: BankTradeSide) in BankTradeFlow(quote: live, side: s) }
        }
    }

    /// Buy is the filled action, pinned under the page; Sell sits beside it once something is held (shares can only be sold).
    @ViewBuilder private func tradeBar(_ live: Quote) -> some View {
        let canBuy: Bool = live.kind != .stock
        let canSell: Bool = live.quantity > 0
        if canBuy || canSell {
            HStack(spacing: Theme.Space.m) {
                if canSell {
                    Button { Haptics.tap(); side = .sell } label: { Text("Sell") }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
                if canBuy {
                    Button { Haptics.tap(); side = .buy } label: { Text("Buy") }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .background(P.page)
            .overlay(alignment: .top) { Hairline() }
        }
    }

    /// The price leads with the week's change and the trend under it; no box.
    private func priceCard(_ live: Quote, _ cur: Currency) -> some View {
        let hist: [Double] = Array(live.history.suffix(52))
        let note: String = live.weekChange.map { String(format: "%+.1f%% this week", $0 * 100) } ?? "No history yet"
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            MoneyHero(label: "Price", value: cur.tidyDisplay(live.price), context: note, contextTint: P.change(live.weekChange ?? 0))
            if hist.count >= 2 { Sparkline(values: hist, tint: (live.weekChange ?? 0) >= 0 ? P.gain : P.loss).frame(height: 120).padding(.top, Theme.Space.s) }
            if live.kind == .crypto { Text("Very volatile: you can lose most of it.").textStyle(.caption, tint: P.caution) }
        }
    }

    private func heldCard(_ live: Quote, _ cur: Currency) -> some View {
        let result: Double = live.value - live.costBasis
        let sign: String = result >= 0 ? "+" : "\u{2212}"
        return MoneyGroup("Your holding") {
            FigureRow(items: [
                .init(label: "You hold", value: cur.tidyShort(live.value)),
                .init(label: "You paid", value: cur.tidyShort(live.costBasis)),
                .init(label: "Result if sold", value: sign + cur.tidyShort(abs(result)), tint: P.change(result)),
            ])
            .padding(.top, Theme.Space.xs)
        }
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
                        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden).noSidewaysDrag()
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(tq, cur) }
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

    // MARK: Pinned action

    /// The step's one action, pinned under the page: Review, then Confirm, then Done.
    private func actionBar(_ tq: TradeQuote, _ cur: Currency) -> some View {
        Group {
            if done != nil {
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("bank-trade-done")
            } else if step == 1 {
                let reason: String? = side == .buy ? (amount <= 0 ? "Type an amount or pick one above." : tq.refusal) : nil
                PrimaryAction(title: "Review", blockedReason: reason, identifier: "bank-trade-review") { step = 2 }
            } else {
                PrimaryAction(title: side == .buy ? "Confirm purchase" : "Confirm sale", blockedReason: tq.refusal, identifier: "bank-trade-confirm") { confirm(tq, cur) }
            }
        }
        .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(P.page)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: Step 1

    /// The amount is the hero: typed large, or one of the quick amounts that fit what you have.
    private func buyAmount(_ tq: TradeQuote, _ cur: Currency) -> some View {
        let avail: Double = tq.available
        let quick: [Double] = [1_000, 10_000, 100_000].map { $0 * cur.rate }.filter { $0 <= avail }
        var presets: [MoneyAmountHero.Preset] = quick.map { MoneyAmountHero.Preset(title: cur.tidyShort($0), amount: $0) }
        if avail > 0, let e = store.engine {
            let fee: Double = e.buyQuote(quote.kind, symbol: quote.symbol, amount: avail).fee
            presets.append(MoneyAmountHero.Preset(title: "All", amount: max(0, (avail - fee * 1.01).rounded(.down))))
        }
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            MoneyAmountHero(label: "How much to buy", currency: cur, amount: $amount,
                            note: "You have \(cur.tidyShort(avail)). Smallest order \(cur.tidyShort(tq.minimumPurchase)); the broker fee is added.",
                            presets: presets)
            if amount > 0 && tq.refusal == nil {
                Text("\(String(format: "%.4f", tq.units)) \(quote.symbol) \u{00B7} fee \(cur.tidyShort(tq.fee))").textStyle(.caption, tint: P.inkSoft, numeric: true)
            }
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
        }
    }

    // MARK: Step 2

    private func review(_ tq: TradeQuote, _ cur: Currency) -> some View {
        let buying: Bool = side == .buy
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            MoneyHero(label: buying ? "Leaves your accounts" : "Reaches your account", value: cur.tidyDisplay(tq.cashChange), tint: buying ? nil : P.gain)
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
        EmptyState(glyph: Glyph.check, title: text, tint: P.gain)
    }
}
