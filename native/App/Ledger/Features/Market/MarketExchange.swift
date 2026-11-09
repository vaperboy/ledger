import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

// The public exchange inside the Market app: the list of shares with price, band and change, your orders, your positions and the
// holdings you can take public. Orders are placed on the share's own page (the ticket), see MarketStock.swift.

/// Wording and small helpers shared by the exchange screens.
enum ExchangeUI {
    static let weekdays: [String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// A share price: two decimals under a hundred, whole numbers above, in the player's currency.
    static func price(_ v: Double, _ cur: Currency) -> String {
        let local: Double = v / cur.rate
        if abs(local) >= 100 { return cur.tidyDisplay(v) }
        let sy: String = cur.country.currencySymbol
        let behind: Bool = (sy.count == 3 && sy.allSatisfy { (c: Character) -> Bool in c.isUppercase && c.isASCII }) || sy == "kr" || sy == "z\u{0142}"
        let digits: String = String(format: "%.2f", abs(local))
        let sign: String = local < -0.004 ? "\u{2212}" : ""
        return behind ? sign + digits + "\u{00A0}" + sy : sign + sy + digits
    }

    /// The close that settles an order placed on game day `day` (0 = Monday): the same day's on a trading day, else Monday's.
    static func closeWord(day: Int) -> String { day <= 4 ? "the close on \(weekdays[day])" : "the close on Monday" }

    static func daysWord(_ n: Int) -> String { n <= 0 ? "today" : (n == 1 ? "tomorrow" : "in \(n) days") }

    static func kindWord(_ kind: String) -> String {
        switch kind {
        case "srv": return "Index"
        case "own": return "Yours"
        default: return "Player"
        }
    }

    /// The history of one share, oldest first (the row has none).
    static func history(_ e: GameEngine, _ id: String) -> [Double] { ExchangeBook(e.state).instruments[id]?.history ?? [] }
}

// MARK: Small drawing pieces

/// Where today's close sits in the price band: the band is the track, the day's possible range is shaded, a dot marks the close.
struct ExchangeBandBar: View {
    var low: Double
    var high: Double
    var dayLow: Double
    var dayHigh: Double
    var close: Double
    @Environment(\.outsidePalette) private var P

    private func place(_ v: Double) -> CGFloat {
        guard high > low else { return 0.5 }
        return CGFloat(min(1, max(0, (v - low) / (high - low))))
    }

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let a: CGFloat = place(dayLow)
            let b: CGFloat = max(a + 0.02, place(dayHigh))
            ZStack(alignment: .leading) {
                Capsule().fill(P.inset).frame(height: 4)
                Capsule().fill(P.accent.opacity(0.30)).frame(width: max(4, (b - a) * w), height: 4).offset(x: a * w)
                Circle().fill(P.accent).frame(width: 9, height: 9).offset(x: min(max(0, place(close) * w - 4.5), max(0, w - 9)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

/// A coloured change figure in a soft rounded tag.
struct ExchangeChangeTag: View {
    var change: Double
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let tint: Color = P.change(change)
        Text(MarketFormat.percent(change, decimals: 2)).textStyle(.caption, tint: tint, numeric: true, weight: .semibold)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs + 1)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// A raised surface the exchange screens use for a share or an order.
struct ExchangeCard<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) { content() }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).stroke(P.line, lineWidth: 0.5))
    }
}

// MARK: The Exchange tab

struct MarketExchangePage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void
    @State private var part: Part = .market

    enum Part: String, CaseIterable, Hashable { case market = "Shares", orders = "Orders", positions = "Positions", listing = "Go public" }

    var body: some View {
        if let e = store.engine {
            let cur: Currency = e.homeCurrency
            let rows: [ExchangeRow] = store.memo("mk.xch") { $0.exchangeMarket } ?? []
            let orders: [ExchangeOpenOrder] = e.exchangeOrders
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                hero(e, cur, rows)
                SegmentedPill(items: Part.allCases, title: { (p: Part) -> String in p == .orders && !orders.isEmpty ? "Orders \(orders.count)" : p.rawValue },
                              selection: $part, identifier: { (p: Part) -> String in "exchange-part-\(p.rawValue)" })
                switch part {
                case .market: shares(e, cur, rows)
                case .orders: openOrders(e, cur, rows, orders)
                case .positions: positions(e, cur, rows)
                case .listing: ExchangeListingList(open: open)
                }
            }
        }
    }

    // MARK: Hero

    private func hero(_ e: GameEngine, _ cur: Currency, _ rows: [ExchangeRow]) -> some View {
        let held: Double = PublicExchange.holdingsValue(e.state)
        let result: Double = PublicExchange.tradingResult(e.state)
        let index: ExchangeRow? = rows.first { (r: ExchangeRow) -> Bool in r.id == PublicExchange.worldIndex }
        let series: [Double] = ExchangeUI.history(e, PublicExchange.worldIndex)
        let day: Int = e.state.day
        let nextClose: String = day <= 4 ? "Next close: today, \(ExchangeUI.weekdays[day])" : "Next close: Monday"
        var context: String = "Trading result " + MarketFormat.money(result, cur) + " \u{00B7} " + nextClose
        if held < 0.5 && abs(result) < 0.5 { context = nextClose }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            MarketHero(label: "Held on the exchange", value: cur.tidyShort(held), context: context,
                       contextTint: abs(result) < 0.5 ? nil : P.change(result), identifier: "exchange-hero")
            if let idx = index, series.count >= 2 {
                ExchangeCard {
                    HStack(alignment: .firstTextBaseline) {
                        Text("World Index").textStyle(.label, tint: P.inkFaint)
                        Spacer(minLength: Theme.Space.s)
                        Text(ExchangeUI.price(idx.close, cur)).textStyle(.headline, numeric: true)
                        ExchangeChangeTag(change: idx.change)
                    }
                    Sparkline(values: series, tint: (series.last ?? 0) >= (series.first ?? 0) ? P.gain : P.loss, filled: true)
                        .frame(height: 56).accessibilityHidden(true)
                    Text("One closing auction a trading day. Orders wait for the close.").textStyle(.caption)
                }
            }
        }
    }

    // MARK: Shares

    @ViewBuilder private func shares(_ e: GameEngine, _ cur: Currency, _ rows: [ExchangeRow]) -> some View {
        if rows.isEmpty {
            EmptyState(glyph: Glyph.stats, title: "The exchange opens soon", message: "Shares appear here once the market has its first prices.")
        } else {
            VStack(spacing: Theme.Space.s) {
                ForEach(rows) { (r: ExchangeRow) in
                    ExchangeShareCard(row: r, cur: cur, history: ExchangeUI.history(e, r.id)) { open(.stock(r.id)) }
                }
            }
        }
    }

    // MARK: Orders

    @ViewBuilder private func openOrders(_ e: GameEngine, _ cur: Currency, _ rows: [ExchangeRow], _ orders: [ExchangeOpenOrder]) -> some View {
        if orders.isEmpty {
            EmptyState(glyph: Glyph.list, title: "No open orders", message: "Pick a share and leave an order. It is settled at the close of the trading day.")
        } else {
            MarketLabel(title: "Open orders", note: "\(orders.count) of \(ExchangeRules.maxOpenOrders)")
            VStack(spacing: Theme.Space.s) {
                ForEach(orders) { (o: ExchangeOpenOrder) in
                    let name: String = rows.first { (r: ExchangeRow) -> Bool in r.id == o.instrument }?.name ?? o.instrument
                    ExchangeOrderCard(order: o, name: name, cur: cur, day: e.state.day) {
                        let ok: Bool? = store.act { (g: inout GameEngine) -> Bool in g.cancelExchangeOrder(id: o.id) }
                        if ok == true { Haptics.success(); store.show("Order cancelled.") } else { store.show("That order is already settled.", tone: "warn") }
                    }
                }
            }
            Text("An order fills only if the closing price is at or better than your limit. Cash is taken when it fills.").textStyle(.caption)
        }
    }

    // MARK: Positions

    @ViewBuilder private func positions(_ e: GameEngine, _ cur: Currency, _ rows: [ExchangeRow]) -> some View {
        let book: ExchangeBook = ExchangeBook(e.state)
        let held: [ExchangePosition] = book.positions.values.filter { (p: ExchangePosition) -> Bool in p.shares > 0 }
            .sorted { (a: ExchangePosition, b: ExchangePosition) -> Bool in a.instrument < b.instrument }
        let mine: [ExchangeRow] = rows.filter { (r: ExchangeRow) -> Bool in r.kind == "own" && r.mine > 0 }
        if held.isEmpty && mine.isEmpty {
            EmptyState(glyph: Glyph.invest, title: "No shares yet", message: "Shares you buy on the exchange are listed here with what they cost and what they are worth.")
        } else {
            if !held.isEmpty {
                let total: Double = max(1, held.reduce(0) { (a: Double, p: ExchangePosition) -> Double in a + Double(p.shares) * (book.instruments[p.instrument]?.close ?? 0) })
                MarketLabel(title: "Positions", note: "Realised " + MarketFormat.money(book.realised, cur))
                allocation(held, book, total)
                VStack(spacing: Theme.Space.s) {
                    ForEach(held, id: \.instrument) { (p: ExchangePosition) in
                        if let inst = book.instruments[p.instrument] {
                            ExchangePositionCard(instrument: inst, position: p, cur: cur, fraction: Double(p.shares) * inst.close / total) { open(.stock(p.instrument)) }
                        }
                    }
                }
            }
            if !mine.isEmpty {
                MarketLabel(title: "Your listed companies")
                VStack(spacing: Theme.Space.s) {
                    ForEach(mine) { (r: ExchangeRow) in
                        ExchangeCard {
                            HStack {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    Text(r.name.tidyText).textStyle(.headline).lineLimit(1)
                                    Text("\(r.mine.formatted()) shares \u{00B7} worth \(cur.tidyShort(r.value))").textStyle(.caption, numeric: true)
                                }
                                Spacer(minLength: Theme.Space.s)
                                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { Haptics.tap(); open(.listing(Int(r.id.dropFirst(3)) ?? 0)) }
                        }
                    }
                }
            }
        }
    }

    /// One stacked bar for how the positions share the money.
    private func allocation(_ held: [ExchangePosition], _ book: ExchangeBook, _ total: Double) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(held.enumerated()), id: \.element.instrument) { (pair: (offset: Int, element: ExchangePosition)) in
                    let v: Double = Double(pair.element.shares) * (book.instruments[pair.element.instrument]?.close ?? 0)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(P.accent.opacity(max(0.25, 1 - 0.22 * Double(pair.offset))))
                        .frame(width: max(4, geo.size.width * CGFloat(v / total) - 2))
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: Cards

/// One share in the market list: name and kind, price and change, where the close sits in the band, and what you hold.
struct ExchangeShareCard: View {
    var row: ExchangeRow
    var cur: Currency
    var history: [Double]
    var action: () -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ExchangeCard {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(ExchangeUI.kindWord(row.kind).uppercased()).textStyle(.label, tint: row.kind == "own" ? P.accent : P.inkFaint)
                        Text(row.name.tidyText).textStyle(.headline).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    if history.count >= 2 {
                        Sparkline(values: Array(history.suffix(30)), tint: row.change >= 0 ? P.gain : P.loss, filled: false)
                            .frame(width: 64, height: 28).accessibilityHidden(true)
                    }
                    VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                        Text(ExchangeUI.price(row.close, cur)).textStyle(.figure, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                        ExchangeChangeTag(change: row.change)
                    }
                }
                ExchangeBandBar(low: row.low, high: row.high, dayLow: row.dayLow, dayHigh: row.dayHigh, close: row.close)
                HStack {
                    Text("Band " + ExchangeUI.price(row.low, cur) + " to " + ExchangeUI.price(row.high, cur)).textStyle(.caption, numeric: true).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    if row.mine > 0 {
                        Text("You hold \(row.mine.formatted())").textStyle(.caption, tint: P.accent, numeric: true, weight: .semibold)
                    }
                }
                if row.halted {
                    note("Trading has stopped.", P.loss)
                } else if let b = row.blocked {
                    note(b, P.caution)
                } else {
                    Text(row.note.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                if row.openOrders > 0 {
                    Text(row.openOrders == 1 ? "1 open order" : "\(row.openOrders) open orders").textStyle(.caption, tint: P.accent)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("exchange-share-\(row.id)")
    }

    private func note(_ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            LedgerGlyph(glyph: Glyph.lock, size: Theme.Icon.small, tint: tint)
            Text(text.tidyText).textStyle(.caption, tint: tint).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One open order with its plain meaning and a Cancel.
struct ExchangeOrderCard: View {
    var order: ExchangeOpenOrder
    var name: String
    var cur: Currency
    var day: Int
    var cancel: () -> Void
    @Environment(\.outsidePalette) private var P

    private var meaning: String {
        let when: String = ExchangeUI.closeWord(day: day)
        return order.side == .buy ? "Fills at \(when) if the price is at or below your limit." : "Fills at \(when) if the price is at or above your limit."
    }

    var body: some View {
        let buy: Bool = order.side == .buy
        ExchangeCard {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(buy ? "BUY" : "SELL").textStyle(.caption, tint: buy ? P.gain : P.loss, weight: .bold)
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs)
                    .background(Capsule().fill((buy ? P.gain : P.loss).opacity(0.14)))
                Text(name.tidyText).textStyle(.headline).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Text("\(order.shares.formatted()) at " + ExchangeUI.price(order.limit, cur)).textStyle(.body, numeric: true).lineLimit(1)
            }
            Text(meaning).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    cancel()
                } label: { Text("Cancel order") }
                    .buttonStyle(SmallOutlineButtonStyle())
                    .accessibilityIdentifier("exchange-cancel-\(order.id)")
            }
        }
    }
}

/// One position: shares, what they cost, what they are worth and the result.
struct ExchangePositionCard: View {
    var instrument: ExchangeInstrument
    var position: ExchangePosition
    var cur: Currency
    var fraction: Double
    var action: () -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let value: Double = Double(position.shares) * instrument.close
        let result: Double = value - position.cost
        let share: Double? = position.cost > 0.5 ? result / position.cost : nil
        Button {
            Haptics.tap()
            action()
        } label: {
            ExchangeCard {
                HStack(alignment: .firstTextBaseline) {
                    Text(instrument.name.tidyText).textStyle(.headline).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(cur.tidyShort(value)).textStyle(.headline, numeric: true)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(position.shares.formatted()) shares \u{00B7} paid " + cur.tidyShort(position.cost)).textStyle(.caption, numeric: true).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(MarketFormat.money(result, cur) + (share.map { (s: Double) -> String in " (" + MarketFormat.percent(s) + ")" } ?? ""))
                        .textStyle(.caption, tint: P.change(result), numeric: true, weight: .semibold).lineLimit(1)
                }
                ProgressLine(fraction: fraction, tint: P.accent.opacity(0.7), height: 3)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("exchange-position-\(instrument.id)")
    }
}

// MARK: Go public (the list)

/// The holdings you could take public, or have: one card each, opening the listing page.
struct ExchangeListingList: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void

    var body: some View {
        if let e = store.engine {
            let cur: Currency = e.homeCurrency
            let holdings: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.type == "hold" && c.status.isLive }
            if holdings.isEmpty {
                EmptyState(glyph: Glyph.group, title: "No holding company", message: "Only a holding company can go public. Open one under Companies, then come back.")
            } else {
                MarketLabel(title: "Holding companies")
                VStack(spacing: Theme.Space.s) {
                    ForEach(holdings, id: \.id) { (c: Company) in
                        let listed: Bool = e.isListed(companyID: c.id)
                        Button {
                            Haptics.tap()
                            open(.listing(c.id))
                        } label: {
                            ExchangeCard {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(c.name.tidyText).textStyle(.headline).lineLimit(1)
                                    Spacer(minLength: Theme.Space.s)
                                    Text(listed ? "Listed" : "Private").textStyle(.caption, tint: listed ? P.gain : P.inkFaint, weight: .semibold)
                                }
                                Text(detail(e, c, listed, cur)).textStyle(.caption, numeric: true).fixedSize(horizontal: false, vertical: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("exchange-holding-\(c.id)")
                    }
                }
            }
        }
    }
}

extension ExchangeListingList {
    fileprivate func detail(_ e: GameEngine, _ c: Company, _ listed: Bool, _ cur: Currency) -> String {
        let worth: String = "Worth " + cur.tidyShort(e.holdingValue(companyID: c.id))
        if listed { return worth + " \u{00B7} you hold \(Int(CapTable.table(c).youPct.rounded()))%" }
        return worth + " \u{00B7} " + ExchangeListingWords.short(e.exchangeListingCheck(holdingID: c.id), cur)
    }
}

/// The listing check in words.
enum ExchangeListingWords {
    static func short(_ r: ExchangeListOutcome, _ cur: Currency) -> String {
        switch r {
        case .ok: return "ready to list"
        case .notAHolding: return "not a holding"
        case .alreadyListed: return "listed"
        case .tooSmall(let n): return "needs a value of " + cur.tidyShort(n)
        case .tooYoung(let w): return "\(w.weeksText) too young"
        case .notEnoughMoney(let fee): return "needs " + cur.tidyShort(fee) + " for the fee"
        }
    }
}
