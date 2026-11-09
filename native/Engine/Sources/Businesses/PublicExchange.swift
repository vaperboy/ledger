import Foundation
import GameCore
import Countries
import Finance

public enum OrderRefusal: Equatable, Sendable {
    case unknown, halted, invalid, serverOnly, ownShares
    case outsideBand(low: Double, high: Double)
    case tooManyOrders
    case tooMany(canSell: Int)
    case positionLimit(maxValue: Double)
    case insider(String)
    case tooSmall(minimum: Double)
    case notEnoughCash(needed: Double)

    public var words: String {
        switch self {
        case .unknown: return "That share is not on the exchange."
        case .halted: return "Trading in that share has stopped."
        case .invalid: return "Enter a number of shares and a price."
        case .serverOnly: return "Orders in other players' companies go through the exchange server."
        case .ownShares: return "You cannot buy shares in your own company on the exchange."
        case .outsideBand(let low, let high): return "The price must stay between \(low) and \(high), the band around the value per share."
        case .tooManyOrders: return "You have too many open orders. Cancel one first."
        case .tooMany(let n): return n > 0 ? "You can offer at most \(n) shares: you keep a majority of your own company." : "You have no shares to offer."
        case .positionLimit: return "That would take your position above the limit for one share."
        case .insider(let why): return why
        case .tooSmall: return "That order is below the smallest the exchange takes."
        case .notEnoughCash: return "You do not have the money for that order."
        }
    }
}

public enum OrderResult: Equatable, Sendable { case placed(id: Int), refused(OrderRefusal) }

public enum ExchangeDividendResult: Equatable, Sendable {
    case ok(perShare: Double), notListed, tooSoon(daysLeft: Int), nothingToPay, tooMuch(maximum: Double), refused(String)
}

/// One line of the market screen.
public struct ExchangeRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public var close: Double
    public var change: Double
    public var nav: Double
    public var low: Double, high: Double
    public var dayLow: Double, dayHigh: Double
    public var volume: Int
    public var mine: Int
    public var openOrders: Int
    public var value: Double
    /// Why you cannot sell your own shares today (nil: you can).
    public var blocked: String?
    public var halted: Bool
    public var note: String
}

/// The public exchange: one closing auction a trading day (Monday to Friday), the World Bank and the World Index as server stocks, and the
/// holdings you take public. Rules are in `ExchangeRules`; everything that moves money goes through `Ledger`, so the books stay balanced.
///
/// How a share trades: you leave limit orders during the day; when the day closes, your orders meet the market. A server stock trades at its
/// close price (a small daily wobble round the server's market price). A holding of yours trades in a call auction against the market's own
/// flow, whose mood follows the stock market. Shares you sell come out of your stake in the cap table, never below 51%.
public enum PublicExchange {
    public static let worldBank = "srv:wb"
    public static let worldIndex = "srv:wi"
    public static let commodityPrefix = "com:"

    public static func commodityID(_ id: String) -> String { commodityPrefix + id }

    public static func today(_ s: GameState) -> Int { s.week * 7 + s.day }

    // MARK: Server stocks

    /// The server's market price of a server stock (nil before the market exists).
    public static func fair(_ s: GameState, _ id: String) -> Double? {
        let p: Double
        switch id {
        case worldBank: p = s.rest["stocks"]?["BANK"]["p"].double ?? 0
        case worldIndex: p = s.rest["idx"]?.double ?? 0
        default:
            guard id.hasPrefix(commodityPrefix) else { return nil }
            p = CommodityMarket.price(s, String(id.dropFirst(commodityPrefix.count))) ?? 0
        }
        return p > 0 ? ExchangeRules.round4(p) : nil
    }

    static func ensureServerStocks(_ s: GameState, _ book: inout ExchangeBook) {
        let listed = [(worldBank, "World Bank", "srv"), (worldIndex, "World Index", "srv")] + CommodityMarket.listed.map { (commodityID($0.id), $0.name, "com") }
        for (id, name, kind) in listed where book.instruments[id] == nil {
            guard let f = fair(s, id) else { continue }
            book.instruments[id] = ExchangeInstrument(id: id, name: name, kind: kind, shares: Int(1e9), nav: f, close: f, previousClose: f, closeDay: -1, listedDay: 0,
                                                      holdingID: 0, volume: 0, dividendDay: -1, dividendPerShare: 0, halted: false, history: [f])
        }
    }

    // MARK: Listing

    /// Register a holding that has gone public. The value is what the holding is worth now; the first price is that value per share.
    @discardableResult
    public static func register(_ s: inout GameState, holdingID: Int, value: Double) -> Bool {
        guard let co = s.company(holdingID), value > 0 else { return false }
        var book = ExchangeBook(s)
        let id = "co:\(holdingID)"
        if book.instruments[id] != nil { return false }
        let total = CapTable.table(co).total
        let nav = ExchangeRules.round4(value / Double(total))
        book.instruments[id] = ExchangeInstrument(id: id, name: co.name, kind: "own", shares: total, nav: nav, close: nav, previousClose: nav, closeDay: -1, listedDay: today(s),
                                                  holdingID: holdingID, volume: 0, dividendDay: -1, dividendPerShare: 0, halted: false, history: [nav])
        book.write(to: &s)
        return true
    }

    public static func isRegistered(_ s: GameState, holdingID: Int) -> Bool { ExchangeBook(s).instruments["co:\(holdingID)"] != nil }

    /// Another player's listing, mirrored from the server so a position in it counts in net worth at the last close.
    public static func mirror(_ s: inout GameState, listingID: String, name: String, shares: Int, nav: Double, close: Double, held: Int, cost: Double) {
        var book = ExchangeBook(s)
        let id = "ext:\(listingID)"
        var inst = book.instruments[id] ?? ExchangeInstrument(id: id, name: name, kind: "ext", shares: shares, nav: nav, close: close, previousClose: close, closeDay: -1, listedDay: 0,
                                                              holdingID: 0, volume: 0, dividendDay: -1, dividendPerShare: 0, halted: false, history: [])
        inst.previousClose = inst.close; inst.name = name; inst.shares = shares; inst.nav = nav; inst.close = close
        book.instruments[id] = inst
        if held > 0 { book.positions[id] = ExchangePosition(instrument: id, shares: held, cost: cost, since: book.positions[id]?.since ?? today(s)) } else { book.positions[id] = nil }
        book.write(to: &s)
    }

    // MARK: Orders

    public static func placeOrder(_ s: inout GameState, instrument id: String, side: ExchangeSide, shares: Int, limit: Double, currency: Currency?) -> OrderResult {
        var book = ExchangeBook(s)
        ensureServerStocks(s, &book)
        guard let inst = book.instruments[id] else { return .refused(.unknown) }
        if inst.halted { return .refused(.halted) }
        if inst.kind == "ext" { return .refused(.serverOnly) }
        let px = ExchangeRules.round4(limit)
        guard shares > 0, px > 0 else { return .refused(.invalid) }
        if !ExchangeRules.inBand(price: px, nav: inst.nav, rules: s.worldRules) { let b = ExchangeRules.band(nav: inst.nav, rules: s.worldRules); return .refused(.outsideBand(low: b.low, high: b.high)) }
        if book.orders.count >= ExchangeRules.maxOpenOrders { return .refused(.tooManyOrders) }
        let held = book.positions[id]?.shares ?? 0
        switch side {
        case .sell:
            if inst.isOwn {
                guard let co = s.company(inst.holdingID) else { return .refused(.halted) }
                let t = CapTable.table(co)
                let can = ExchangeRules.ownerSellable(owned: t.you, openSells: book.openSells(id), total: t.total)
                if shares > can { return .refused(.tooMany(canSell: can)) }
                if let why = ExchangeRules.insiderBlock(listedDay: inst.listedDay, disclosureDay: inst.dividendDay, today: today(s)) { return .refused(.insider(why)) }
            } else {
                let can = ExchangeRules.holderSellable(owned: held, openSells: book.openSells(id))
                if shares > can { return .refused(.tooMany(canSell: can)) }
            }
        case .buy:
            if inst.isOwn { return .refused(.ownShares) }
            let cap = ExchangeRules.serverPositionLimit(currency)
            if Double(held + book.openBuys(id) + shares) * px > cap { return .refused(.positionLimit(maxValue: cap)) }
            let notional = Double(shares) * px
            if notional < ExchangeRules.minimumOrder(currency) { return .refused(.tooSmall(minimum: ExchangeRules.minimumOrder(currency))) }
            let need = notional + ExchangeRules.fee(notional, currency: currency)
            if Payments.liquid(s) - book.committed < need { return .refused(.notEnoughCash(needed: need)) }
        }
        let oid = s.makeID()
        book.orders.append(ExchangeOpenOrder(id: oid, instrument: id, side: side, shares: shares, limit: px, seq: book.nextSeq, day: today(s)))
        book.nextSeq += 1
        book.write(to: &s)
        return .placed(id: oid)
    }

    @discardableResult
    public static func cancelOrder(_ s: inout GameState, orderID: Int) -> Bool {
        var book = ExchangeBook(s)
        guard let k = book.orders.firstIndex(where: { $0.id == orderID }) else { return false }
        book.orders.remove(at: k)
        book.write(to: &s)
        return true
    }

    // MARK: Dividends of a listed company

    /// The listed holding pays `amount` in all to its shareholders (you by your stake, the market by the rest). Once a quarter at most, and
    /// only out of retained profit, like any dividend.
    public static func declareDividend(_ s: inout GameState, holdingID: Int, amount: Double, context: FinanceContext) -> ExchangeDividendResult {
        var book = ExchangeBook(s)
        guard var inst = book.instruments["co:\(holdingID)"], !inst.halted, let co = s.company(holdingID) else { return .notListed }
        let now = today(s)
        if inst.dividendDay >= 0, now - inst.dividendDay < ExchangeRules.dividendGapDays { return .tooSoon(daysLeft: ExchangeRules.dividendGapDays - (now - inst.dividendDay)) }
        if amount <= 0 { return .nothingToPay }
        let most = Payments.maximumDividend(co, state: s, context: context)
        if amount > most { return .tooMuch(maximum: most) }
        let r = Payments.payDividend(&s, companyID: holdingID, amount: amount, context: context)
        switch r {
        case .ok: break
        case .noRetainedProfit: return .refused("The company has no retained profit to pay out.")
        case .notEnoughCash: return .refused("The company needs to keep cash for two weeks of costs.")
        case .needsBoard: return .refused("The board must vote for this dividend first.")
        }
        let dps = amount / Double(max(1, inst.shares))
        inst.dividendDay = now
        inst.dividendPerShare = dps
        inst.close = max(0.0001, ExchangeRules.round4(inst.close - dps))   // ex-dividend: the price starts the day lower by what was paid
        book.instruments[inst.id] = inst
        book.write(to: &s)
        return .ok(perShare: dps)
    }

    // MARK: The day

    /// Runs once a day. On a trading day's close (Monday to Friday, worked out on the morning after) every share clears; dividends of the
    /// World Bank are paid in the first days of each quarter. `holdingValue` gives what a listed holding is worth now (nil: gone).
    public static func runDay(_ s: inout GameState, context: FinanceContext, holdingValue: (Int) -> Double?) {
        let now = today(s)
        var book = ExchangeBook(s)
        if book.lastRun == now { return }
        book.lastRun = now
        ensureServerStocks(s, &book)
        let cur = context.homeCurrency(s)
        var withhold = false
        let ended = s.day == 0 ? 6 : s.day - 1
        if ended <= 4 {
            for id in book.instruments.keys.sorted() {
                guard var inst = book.instruments[id], !inst.halted, inst.kind != "ext" else { continue }
                if inst.isServer {
                    guard let f = fair(s, id) else { continue }
                    inst.nav = f
                } else {
                    guard let co = s.company(inst.holdingID), co.status.isLive, let v = holdingValue(inst.holdingID), v > 0 else {
                        inst.halted = true
                        book.orders.removeAll { $0.instrument == id }
                        book.instruments[id] = inst
                        s.note("Trading in \(inst.name) has stopped: the company is gone.", tone: "bad")
                        continue
                    }
                    inst.shares = CapTable.table(co).total
                    let target = ExchangeRules.round4(v / Double(inst.shares))
                    inst.nav = ExchangeRules.round4(clamp(target, inst.nav * (1 - ExchangeRules.valueStepShare), inst.nav * (1 + ExchangeRules.valueStepShare)))
                }
                // Orders that the new value per share has left outside the band are cancelled.
                for o in book.orders where o.instrument == id && !ExchangeRules.inBand(price: o.limit, nav: inst.nav, rules: s.worldRules) {
                    book.orders.removeAll { $0.id == o.id }
                    s.note("Your order for \(inst.name) was cancelled: the price is outside the band after the value report.", tone: "n")
                }
                let previous = inst.close > 0 ? inst.close : inst.nav
                let bounds = ExchangeRules.closeBounds(previous: previous, nav: inst.nav, rules: s.worldRules)
                var price = ExchangeRules.round4(clamp(previous, bounds.low, bounds.high))
                var traded = 0
                if inst.isServer {
                    var r = HashedRandom("\(s.seed):xch:\(id):\(now)")
                    price = ExchangeRules.round4(clamp(inst.nav * (1 + (r.next() - 0.5) * 0.008), bounds.low, bounds.high))
                    for o in book.orders.filter({ $0.instrument == id }).sorted(by: { $0.seq < $1.seq }) {
                        let fill = o.side == .buy ? max(price, inst.nav) : min(price, inst.nav)
                        let crosses = o.side == .buy ? o.limit >= fill : o.limit <= fill
                        guard crosses else { continue }
                        if settleServer(&s, &book, inst, o, price: fill, today: now, currency: cur) { traded += o.shares; if o.side == .sell { withhold = true } }
                        book.orders.removeAll { $0.id == o.id }
                    }
                } else if let co = s.company(inst.holdingID) {
                    let table = CapTable.table(co)
                    var room = ExchangeRules.ownerSellable(owned: table.you, openSells: 0, total: table.total)
                    let blocked = ExchangeRules.insiderBlock(listedDay: inst.listedDay, disclosureDay: inst.dividendDay, today: now) != nil
                    var entered: [ExchangeOrder] = []
                    for o in book.orders.filter({ $0.instrument == id && $0.side == .sell }).sorted(by: { $0.seq < $1.seq }) where !blocked {
                        guard o.shares <= room else { book.orders.removeAll { $0.id == o.id }; s.note("Your sell order for \(inst.name) was cancelled: you must keep a majority.", tone: "n"); continue }
                        room -= o.shares
                        entered.append(ExchangeOrder(id: o.id, instrument: id, trader: "me", side: .sell, shares: o.shares, limit: o.limit, seq: o.seq))
                    }
                    let outside = table.total - table.you
                    let result = ExchangeRules.clear(crowd(s, inst, outside: outside, bounds: bounds, today: now) + entered, reference: previous, low: bounds.low, high: bounds.high)
                    if let p = result.price { price = p }
                    for f in result.fills where f.seller == "me" {
                        let moved = settleOwnSale(&s, inst, shares: f.shares, price: f.price, currency: cur)
                        if moved > 0 { traded += moved; withhold = true }
                        if let k = book.orders.firstIndex(where: { $0.id == f.sellOrder }) {
                            book.orders[k].shares -= moved
                            if book.orders[k].shares <= 0 || moved < f.shares { book.orders.remove(at: k) }
                        }
                    }
                }
                inst.previousClose = inst.close > 0 ? inst.close : price
                inst.close = price
                inst.closeDay = now - 1
                inst.volume = traded
                inst.history.append(price)
                if inst.history.count > 104 { inst.history.removeFirst(inst.history.count - 104) }
                book.instruments[id] = inst
            }
        }
        // World Bank dividend: a quarter's share of its yield to everyone who held it the day before.
        if s.week % 13 == 0, s.day == 3, let inst = book.instruments[worldBank], let pos = book.positions[worldBank], pos.shares > 0, pos.since < now {
            let dy = s.rest["stocks"]?["BANK"]["dy"].double ?? 0
            let d = jsRound(Double(pos.shares) * inst.close * dy / 4)
            if d > 0 {
                Ledger.move(&s, .me, d, why: "Dividend: \(inst.name)")
                s.tax.dividends += d
                s.stats.dividendsReceived += d
                withhold = true
            }
        }
        book.write(to: &s)
        if withhold { PersonalFinance.withholdNow(&s, context: context) }
    }

    /// Fills a server stock order at the close. Returns false (and tells the player) when it could not be settled.
    private static func settleServer(_ s: inout GameState, _ book: inout ExchangeBook, _ inst: ExchangeInstrument, _ o: ExchangeOpenOrder, price: Double, today now: Int, currency cur: Currency) -> Bool {
        let gross = jsRound(Double(o.shares) * price)
        let fee = ExchangeRules.fee(gross, currency: cur)
        var pos = book.positions[inst.id] ?? ExchangePosition(instrument: inst.id, shares: 0, cost: 0, since: now)
        switch o.side {
        case .buy:
            if Double(pos.shares + o.shares) * price > ExchangeRules.serverPositionLimit(cur) { s.note("Your order for \(inst.name) was cancelled: it is over the position limit.", tone: "n"); return false }
            if Payments.liquid(s) < gross + fee { s.note("Your order for \(inst.name) was cancelled: not enough money at the close.", tone: "n"); return false }
            Ledger.move(&s, .me, -(gross + fee), why: "Bought \(o.shares) \(inst.name)")
            pos.shares += o.shares; pos.cost += gross + fee; pos.since = now
            book.positions[inst.id] = pos
            s.note("Closing auction: bought \(o.shares) \(inst.name) at \(price).", tone: "good")
            return true
        case .sell:
            guard pos.shares >= o.shares, pos.shares > 0 else { s.note("Your sell order for \(inst.name) was cancelled: you no longer hold the shares.", tone: "n"); return false }
            let basis = pos.cost * Double(o.shares) / Double(pos.shares)
            Ledger.move(&s, .me, gross - fee, why: "Sold \(o.shares) \(inst.name)")
            s.tax.gains += gross - fee - basis
            book.realised += gross - fee - basis
            pos.shares -= o.shares; pos.cost -= basis
            book.positions[inst.id] = pos.shares > 0 ? pos : nil
            s.note("Closing auction: sold \(o.shares) \(inst.name) at \(price).", tone: "good")
            return true
        }
    }

    /// The owner's shares leave the cap table for the market, and the money (less the fee) is the owner's; the whole of it counts as gain.
    private static func settleOwnSale(_ s: inout GameState, _ inst: ExchangeInstrument, shares: Int, price: Double, currency cur: Currency) -> Int {
        guard let i = s.companyIndex(inst.holdingID) else { return 0 }
        let gross = jsRound(Double(shares) * price)
        let moved = CapTable.sellFromYou(&s, i, shares: shares, to: "Exchange investors", paid: gross)
        guard moved > 0 else { return 0 }
        let part = jsRound(Double(moved) * price)
        let net = part - min(part, ExchangeRules.fee(part, currency: cur))
        Payments.ownerReceivesSale(&s, from: s.companies[i], amount: net, gain: net, label: "Sold \(moved) shares of \(inst.name) on the exchange")
        s.note("Closing auction: sold \(moved) shares of \(inst.name) at \(price).", tone: "good", companyID: inst.holdingID)
        return moved
    }

    /// The market's own orders for one auction: five levels each side round the previous close, shifted by the stock market's mood.
    static func crowd(_ s: GameState, _ inst: ExchangeInstrument, outside: Int, bounds: (low: Double, high: Double), today now: Int) -> [ExchangeOrder] {
        let moods: [String: Double] = ["bull": 0.01, "recovery": 0.005, "correction": -0.01, "bear": -0.02, "crash": -0.05]
        let mood = moods[s.rest["mkt"]?["regime"].string ?? "bull"] ?? 0
        var r = HashedRandom("\(s.seed):xch:\(inst.id):crowd:\(now)")
        let ref = inst.close > 0 ? inst.close : inst.nav
        var out: [ExchangeOrder] = []
        for k in 0..<5 {
            let lot = max(1, Int(Double(inst.shares) * 0.004 * (0.6 + 0.8 * r.next())))
            let sellLot = min(lot, max(0, outside / 5))
            let pb = ExchangeRules.round4(ref * (1 + mood - 0.01 - 0.02 * Double(k)))
            let ps = ExchangeRules.round4(ref * (1 + mood + 0.01 + 0.02 * Double(k)))
            if pb >= bounds.low, pb <= bounds.high { out.append(ExchangeOrder(id: -(k + 1), instrument: inst.id, trader: "crowd:b\(k)", side: .buy, shares: lot, limit: pb, seq: 0)) }
            if sellLot > 0, ps >= bounds.low, ps <= bounds.high { out.append(ExchangeOrder(id: -(k + 11), instrument: inst.id, trader: "crowd:s\(k)", side: .sell, shares: sellLot, limit: ps, seq: 0)) }
        }
        return out
    }

    // MARK: Reading

    /// What the shares you hold on the exchange are worth at the last close (your own listed holdings are in your companies, not here).
    public static func holdingsValue(_ s: GameState) -> Double {
        guard let j = s.rest["xch"], !j.isNull else { return 0 }
        var total = 0.0
        for (k, p) in j["p"].object.sorted(by: { $0.key < $1.key }) where j["i"][k]["k"].string != "own" { total += p["q"].double * j["i"][k]["c"].double }
        return total
    }

    /// Gains on shares you bought: sold (realised) and still held (at the last close).
    public static func tradingResult(_ s: GameState) -> Double {
        let book = ExchangeBook(s)
        var open = 0.0
        for (k, p) in book.positions { open += Double(p.shares) * (book.instruments[k]?.close ?? 0) - p.cost }
        return book.realised + open
    }

    public static func market(_ s: GameState, context: FinanceContext) -> [ExchangeRow] {
        var book = ExchangeBook(s)
        ensureServerStocks(s, &book)
        let now = today(s)
        return book.instruments.values.sorted { $0.kind != $1.kind ? $0.kind > $1.kind : $0.name < $1.name }.map { i in
            let b = ExchangeRules.band(nav: i.nav, rules: s.worldRules), d = ExchangeRules.closeBounds(previous: i.close, nav: i.nav, rules: s.worldRules)
            let mine = i.isOwn ? (s.company(i.holdingID).map { CapTable.table($0).you } ?? 0) : (book.positions[i.id]?.shares ?? 0)
            let blocked = i.isOwn ? ExchangeRules.insiderBlock(listedDay: i.listedDay, disclosureDay: i.dividendDay, today: now) : nil
            let note: String
            switch i.kind {
            case "srv": note = i.id == worldBank ? "Pays a dividend each quarter." : "Follows the whole market. No dividend."
            case "com": note = "Raw material priced by world supply and demand. No dividend."
            case "own": note = "Results in \(ExchangeRules.nextResultsDay(listedDay: i.listedDay, today: now) - now) days."
            default: note = "Another player's company."
            }
            return ExchangeRow(id: i.id, name: i.name, kind: i.kind, close: i.close, change: i.change, nav: i.nav, low: b.low, high: b.high, dayLow: d.low, dayHigh: d.high,
                               volume: i.volume, mine: mine, openOrders: book.orders.filter { $0.instrument == i.id }.count, value: Double(mine) * i.close, blocked: blocked,
                               halted: i.halted, note: note)
        }
    }

    public static func openOrders(_ s: GameState) -> [ExchangeOpenOrder] { ExchangeBook(s).orders.sorted { $0.seq < $1.seq } }
}
