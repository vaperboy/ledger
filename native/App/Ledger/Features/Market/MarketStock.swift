import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// One share on the exchange: its price line, the figures, and the order ticket. The ticket says, before anything is placed, what will
/// happen if you place it, in the engine's own refusal words when it would be turned down.
struct MarketStockPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @Environment(\.dismiss) private var dismiss
    var instrumentID: String
    @State private var side: ExchangeSide = .buy
    @State private var sharesText = ""
    @State private var limitText = ""
    @State private var seeded = false
    @State private var next: MarketRoute?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case shares, limit }

    var body: some View {
        Group {
            if let e = store.engine, let row = e.exchangeMarket.first(where: { (r: ExchangeRow) -> Bool in r.id == instrumentID }) {
                let cur: Currency = e.homeCurrency
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    hero(e, row, cur)
                    figures(e, row, cur)
                    ticket(e, row, cur)
                    orders(e, row, cur)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { placeBar(e, row, cur) }
                .appScreen(title: row.name, subtitle: "Market \u{00B7} Exchange")
                .onAppear { seed(row, cur) }
                .navigationDestination(item: $next) { (r: MarketRoute) in MarketDestination(route: r) }
            } else {
                EmptyState(glyph: Glyph.stats, title: "Not on the exchange", message: "This share is gone.")
                    .appScreen(title: "Share", subtitle: "Market \u{00B7} Exchange")
            }
        }
    }

    // MARK: Parts

    private func hero(_ e: GameEngine, _ row: ExchangeRow, _ cur: Currency) -> some View {
        let history: [Double] = ExchangeUI.history(e, row.id)
        var context: String = MarketFormat.percent(row.change, decimals: 2) + " on the day"
        if row.mine > 0 { context += " \u{00B7} you hold \(row.mine.formatted())" }
        return MarketHero(label: "Last close", value: ExchangeUI.price(row.close, cur), context: context, contextTint: P.change(row.change),
                          series: history, seriesTint: row.change >= 0 ? P.gain : P.loss, identifier: "stock-hero")
    }

    private func figures(_ e: GameEngine, _ row: ExchangeRow, _ cur: Currency) -> some View {
        ExchangeCard {
            ExchangeBandBar(low: row.low, high: row.high, dayLow: row.dayLow, dayHigh: row.dayHigh, close: row.close)
            ValueRow(label: "Value per share", value: ExchangeUI.price(row.nav, cur), tint: P.ink)
            ValueRow(label: "Price band", value: ExchangeUI.price(row.low, cur) + " to " + ExchangeUI.price(row.high, cur), tint: P.ink)
            ValueRow(label: "Next close can land", value: ExchangeUI.price(row.dayLow, cur) + " to " + ExchangeUI.price(row.dayHigh, cur), tint: P.ink)
            ValueRow(label: "Traded at last close", value: row.volume.formatted() + " shares", tint: P.ink)
            if row.mine > 0 { ValueRow(label: "Your shares", value: row.mine.formatted() + " \u{00B7} " + cur.tidyShort(row.value), tint: P.accent) }
            Text("The closing price moves at most \(Int(ExchangeRules.dayMoveShare * 100))% a day and stays within \(Int(ExchangeRules.bandShare * 100))% of the value per share.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            if row.kind == "own", let id = Int(row.id.dropFirst(3)) {
                if let b = row.blocked {
                    Text(b.tidyText).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true)
                }
                QuietButton(title: "Results, blackout and dividends", fullWidth: true) { next = .listing(id) }
            }
        }
    }

    @ViewBuilder private func ticket(_ e: GameEngine, _ row: ExchangeRow, _ cur: Currency) -> some View {
        MarketLabel(title: "Order ticket", note: "Settled at " + ExchangeUI.closeWord(day: e.state.day))
        SegmentedPill(items: [ExchangeSide.buy, ExchangeSide.sell], title: { (s: ExchangeSide) -> String in s == .buy ? "Buy" : "Sell" },
                      selection: $side, identifier: { (s: ExchangeSide) -> String in "ticket-side-\(s.rawValue)" })
        ExchangeCard {
            field("Shares", text: $sharesText, unit: "shares", focused: .shares, pad: .numberPad)
            chips(row, e)
            field("Limit price", text: $limitText, unit: cur.country.currencySymbol, focused: .limit, pad: .decimalPad)
            HStack(spacing: Theme.Space.s) {
                priceChip("Band low", row.low, cur, .up)
                priceChip("Last close", row.close, cur, .toNearestOrEven)
                priceChip("Band high", row.high, cur, .down)
            }
        }
        consequence(e, row, cur)
    }

    private func field(_ title: String, text: Binding<String>, unit: String, focused: Field, pad: UIKeyboardType) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(title).textStyle(.body, tint: P.inkSoft)
            Spacer(minLength: Theme.Space.s)
            TextField("0", text: text)
                .keyboardType(pad)
                .focused($focus, equals: focused)
                .textStyle(.headline, numeric: true)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 80)
            Text(unit).textStyle(.caption, tint: P.inkFaint)
            if focus == focused {
                Button("Done") { focus = nil }.textStyle(.body, tint: P.accent, weight: .semibold).frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .overlay(alignment: .bottom) { Rectangle().fill(focus == focused ? P.focus : P.hairline).frame(height: focus == focused ? 1 : 0.5) }
    }

    /// Shortcuts for the share count: what you may sell, or a round lot to buy.
    private func chips(_ row: ExchangeRow, _ e: GameEngine) -> some View {
        let lots: [Int] = side == .sell ? sellLots(row, e) : [10, 100, 1000]
        return HStack(spacing: Theme.Space.s) {
            ForEach(lots, id: \.self) { (n: Int) in
                Button {
                    Haptics.choose()
                    sharesText = String(n)
                } label: { Text(n.formatted()) }
                    .buttonStyle(SmallOutlineButtonStyle())
            }
            if side == .sell && lots.isEmpty { Text("Nothing to sell").textStyle(.caption) }
            Spacer(minLength: 0)
        }
    }

    private func sellLots(_ row: ExchangeRow, _ e: GameEngine) -> [Int] {
        let can: Int = canSell(row, e)
        if can <= 0 { return [] }
        var out: [Int] = []
        for part in [4, 2, 1] { let n: Int = max(1, can / part); if !out.contains(n) { out.append(n) } }
        return out
    }

    private func canSell(_ row: ExchangeRow, _ e: GameEngine) -> Int {
        let book: ExchangeBook = ExchangeBook(e.state)
        if row.kind == "own", let id = Int(row.id.dropFirst(3)), let co = e.state.company(id) {
            let t: CapTable.Table = CapTable.table(co)
            return ExchangeRules.ownerSellable(owned: t.you, openSells: book.openSells(row.id), total: t.total)
        }
        return ExchangeRules.holderSellable(owned: row.mine, openSells: book.openSells(row.id))
    }

    private func priceChip(_ title: String, _ v: Double, _ cur: Currency, _ rule: FloatingPointRoundingRule) -> some View {
        Button {
            Haptics.choose()
            limitText = Self.plain(v, cur, rule)
        } label: { Text(title) }
            .buttonStyle(SmallOutlineButtonStyle())
            .accessibilityIdentifier("ticket-limit-\(title)")
    }

    // MARK: What will happen

    private func parsed(_ cur: Currency) -> (shares: Int, limit: Double) {
        let n: Int = Int(sharesText.filter { (c: Character) -> Bool in c.isNumber }) ?? 0
        let cleaned: String = limitText.replacingOccurrences(of: ",", with: ".").filter { (c: Character) -> Bool in c.isNumber || c == "." }
        return (n, (Double(cleaned) ?? 0) * cur.rate)
    }

    /// The engine tries the order on a copy of the game; nothing is placed. A refusal is its own words.
    private func trial(_ e: GameEngine, _ cur: Currency) -> OrderResult {
        let p = parsed(cur)
        var copy: GameEngine = e
        return copy.placeExchangeOrder(instrument: instrumentID, side: side, shares: p.shares, limit: p.limit)
    }

    private func consequence(_ e: GameEngine, _ row: ExchangeRow, _ cur: Currency) -> some View {
        let result: OrderResult = trial(e, cur)
        let p = parsed(cur)
        return ExchangeCard {
            Text("If you do this, this will happen").textStyle(.label, tint: P.inkFaint)
            switch result {
            case .refused(let why):
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.small, tint: P.caution)
                    Text(refusalText(why, e, cur).tidyText).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("ticket-refusal")
            case .placed:
                ForEach(Array(happenings(e, row, cur, shares: p.shares, limit: p.limit).enumerated()), id: \.offset) { (pair: (offset: Int, element: String)) in
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.small, tint: P.gain)
                        Text(pair.element.tidyText).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The engine's refusal words, with the figure it leaves out.
    private func refusalText(_ why: OrderRefusal, _ e: GameEngine, _ cur: Currency) -> String {
        switch why {
        case .outsideBand(let lo, let hi): return why.words + " Today that is " + ExchangeUI.price(lo, cur) + " to " + ExchangeUI.price(hi, cur) + "."
        case .notEnoughCash(let n): return why.words + " It needs " + cur.tidyShort(n) + " with the fee."
        case .tooSmall(let m): return why.words + " The smallest is " + cur.tidyShort(m) + "."
        case .positionLimit(let m): return why.words + " The most is " + cur.tidyShort(m) + "."
        default: return why.words
        }
    }

    private func happenings(_ e: GameEngine, _ row: ExchangeRow, _ cur: Currency, shares: Int, limit: Double) -> [String] {
        var out: [String] = []
        let when: String = ExchangeUI.closeWord(day: e.state.day)
        let px: Double = ExchangeRules.round4(limit)
        let gross: Double = Double(shares) * px
        let fee: Double = ExchangeRules.fee(gross, currency: cur)
        if side == .buy {
            out.append("Your order waits for \(when). It fills only if the price closes at or below " + ExchangeUI.price(px, cur) + ".")
            out.append("The most you pay is " + cur.tidyShort(gross + fee) + ", fee of " + cur.tidyShort(fee) + " included. The cash leaves your account only if it fills.")
            if px < row.dayLow { out.append("Your price is under the lowest close allowed next time (" + ExchangeUI.price(row.dayLow, cur) + "), so it cannot fill at the next close.") }
        } else {
            out.append("Your order waits for \(when). It fills only if the price closes at or above " + ExchangeUI.price(px, cur) + ".")
            let net: Double = gross - fee
            if row.kind == "own" {
                out.append("At least " + cur.tidyShort(net) + " comes to you after the fee. The shares leave your stake, and you always keep a majority. The whole sale counts as a gain for tax.")
            } else if let pos = ExchangeBook(e.state).positions[row.id], pos.shares > 0 {
                let basis: Double = pos.cost * Double(shares) / Double(pos.shares)
                let gain: Double = net - basis
                out.append("At least " + cur.tidyShort(net) + " comes to you after the fee: " + MarketFormat.money(gain, cur) + " against what they cost. Gains are taxed.")
            }
            if px > row.dayHigh { out.append("Your price is above the highest close allowed next time (" + ExchangeUI.price(row.dayHigh, cur) + "), so it cannot fill at the next close.") }
        }
        return out
    }

    // MARK: Place and cancel

    private func placeBar(_ e: GameEngine, _ row: ExchangeRow, _ cur: Currency) -> some View {
        let result: OrderResult = trial(e, cur)
        var blocked: String? = nil
        if case .refused(let why) = result { blocked = refusalText(why, e, cur).tidyText }
        let p = parsed(cur)
        return PrimaryAction(title: side == .buy ? "Place buy order" : "Place sell order", blockedReason: blocked, identifier: "ticket-place") {
            let r: OrderResult? = store.act { (g: inout GameEngine) -> OrderResult in
                g.placeExchangeOrder(instrument: instrumentID, side: side, shares: p.shares, limit: p.limit)
            }
            switch r {
            case .placed?:
                Haptics.success()
                store.show("Order placed. It is settled at \(ExchangeUI.closeWord(day: e.state.day)).")
                dismiss()
            case .refused(let why)?:
                Haptics.warning()
                store.show(why.words, tone: "warn")
            case nil: break
            }
        }
        .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
        .background(P.ground.opacity(0.96))
    }

    @ViewBuilder private func orders(_ e: GameEngine, _ row: ExchangeRow, _ cur: Currency) -> some View {
        let mine: [ExchangeOpenOrder] = e.exchangeOrders.filter { (o: ExchangeOpenOrder) -> Bool in o.instrument == row.id }
        if !mine.isEmpty {
            MarketLabel(title: "Open orders in this share", note: "\(mine.count)")
            VStack(spacing: Theme.Space.s) {
                ForEach(mine) { (o: ExchangeOpenOrder) in
                    ExchangeOrderCard(order: o, name: row.name, cur: cur, day: e.state.day) {
                        let ok: Bool? = store.act { (g: inout GameEngine) -> Bool in g.cancelExchangeOrder(id: o.id) }
                        if ok == true { Haptics.success(); store.show("Order cancelled.") }
                    }
                }
            }
        }
    }

    // MARK: Start values

    /// The limit starts at the last close, in the player's currency without a symbol.
    private func seed(_ row: ExchangeRow, _ cur: Currency) {
        guard !seeded else { return }
        seeded = true
        limitText = Self.plain(row.close, cur, .toNearestOrEven)
        if row.kind == "own" { side = .sell }
    }

    /// The price as typed, rounded the way the caller needs so the band edges stay inside the band.
    private static func plain(_ v: Double, _ cur: Currency, _ rule: FloatingPointRoundingRule) -> String {
        let local: Double = v / cur.rate
        if abs(local) >= 100 { return String(format: "%.0f", local.rounded(rule)) }
        return String(format: "%.2f", (local * 100).rounded(rule) / 100)
    }
}
