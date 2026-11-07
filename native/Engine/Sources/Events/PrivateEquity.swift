import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Private equity funds you commit money to. Each year four funds raise money (buyout, growth, infrastructure, venture). You commit an amount;
/// the fund calls it in over its first four years, invests it, charges 2% a year on what you committed while it invests (1% after) and 20% of
/// the profit above an 8% a year hurdle, pays back from year four and winds up after ten years. The value moves with the fund's own deals and
/// with the stock market; venture funds swing most. Miss a capital call and you lose half your stake. You can sell a stake early on the secondary
/// market at a discount. Gains are taxed when money comes back above what you paid in. Counted in net worth as funds (`Valuation`).
/// Original: features/world/private_equity.js (round 56, `PE56`).
///
/// State: `rest["pe56"]` = { offers: [...], y: year, mine: [fund...] }. The original gates it behind "Ledger Pro"; the native game has no Pro tier, so it is open.
public enum PrivateEquity {
    public struct Style: Equatable { public var name: String, blurb: String; var r: Double, v: Double, beta: Double }
    public static let styles: [String: Style] = [
        "buyout": Style(name: "Buyout", blurb: "Buys mature companies with borrowed money, makes them better and sells them.", r: 0.14, v: 0.16, beta: 0.8),
        "growth": Style(name: "Growth", blurb: "Minority stakes in fast-growing companies.", r: 0.16, v: 0.24, beta: 1),
        "infra": Style(name: "Infrastructure", blurb: "Ports, power lines, fibre and toll roads. Steady and slow.", r: 0.09, v: 0.07, beta: 0.3),
        "venture": Style(name: "Venture", blurb: "Many young companies. Most fail, a few return the fund.", r: 0.18, v: 0.42, beta: 1.2),
    ]
    public static let order = ["buyout", "growth", "infra", "venture"]
    static let roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

    public struct Offer: Identifiable, Equatable {
        public var id: String
        public var style: String, name: String
        /// What you can see of the manager's past record (a noisy read of how good they are).
        public var seenQuality: Double
        public var minimum: Double
        public var trackRecord: String { PrivateEquity.track(seenQuality) }
        public var description: String { styles[style]?.blurb ?? "" }
    }
    public struct Fund: Identifiable, Equatable {
        public var id: Int
        public var style: String, name: String
        public var startWeek: Int
        public var committed: Double, called: Double, nav: Double, distributed: Double, paidIn: Double, fees: Double
        public var live: Bool, sold: Bool
        public var multiple: Double { paidIn > 0 ? (nav + distributed) / paidIn : 0 }
        public var finalMultiple: Double { paidIn > 0 ? distributed / paidIn : 0 }
        public var toBeCalled: Double { max(0, committed - called) }
    }

    static func track(_ q: Double) -> String { q >= 0.75 ? "Top quartile" : q >= 0.55 ? "Above median" : q >= 0.4 ? "Median" : "Below median" }

    // MARK: Reading

    static func yearsIn(_ f: JSONValue, _ s: GameState) -> Double { Double(s.week - f["w0"].int) / 52 }

    /// This year's funds, drawn from the game seed (the same every time you look). Original: `offersFor`.
    static func makeOffers(_ s: GameState, year y: Int, minimumScale cur: Currency) -> [JSONValue] {
        order.enumerated().map { i, k in
            var r = HashedRandom("\(s.seed):pe:\(y):\(k)")
            let q = (0.25 + r.next() * 0.7) * 100
            let qq = jsRound(q) / 100
            let root = ["Nordic", "Atlas", "Meridian", "Crown", "Harbor", "Summit", "Vanguard", "Orion"][Int(r.next() * 8) % 8]
            let nm = root + " " + (k == "infra" ? "Infrastructure" : k == "venture" ? "Ventures" : "Capital") + " " + roman[Int(r.next() * 6) + 1]
            let seen = clamp(qq + (r.next() - 0.5) * 0.3, 0.05, 0.98)
            return .object(["id": .string("pe\(y)\(i)"), "k": .string(k), "n": .string(nm), "q": .number(qq), "seen": .number(seen), "min": .number(cur.scaledPrice(k == "venture" ? 500_000 : k == "infra" ? 2_500_000 : 1_000_000)), "y": .number(Double(y))])
        }
    }
    /// A new set of funds every calendar year.
    public static func refresh(_ s: inout GameState, context fc: FinanceContext) {
        var pe = s.rest["pe56"] ?? .object(["offers": .array([]), "y": .null, "mine": .array([])])
        let y = GameCalendar.year(week: s.week)
        if pe["y"].isNull || pe["y"].int != y {
            pe["y"] = .number(Double(y))
            pe["offers"] = .array(makeOffers(s, year: y, minimumScale: fc.homeCurrency(s)))
            s.rest["pe56"] = pe
        }
    }
    public static func offers(_ s: inout GameState, context fc: FinanceContext) -> [Offer] {
        refresh(&s, context: fc)
        return (s.rest["pe56"]?["offers"].array ?? []).map { Offer(id: $0["id"].string, style: $0["k"].string, name: $0["n"].string, seenQuality: $0["seen"].double, minimum: $0["min"].double) }
    }
    /// This year's funds already drawn (read only; `weekly` keeps them current).
    public static func offersOnTable(_ s: GameState) -> [Offer] {
        (s.rest["pe56"]?["offers"].array ?? []).map { Offer(id: $0["id"].string, style: $0["k"].string, name: $0["n"].string, seenQuality: $0["seen"].double, minimum: $0["min"].double) }
    }
    public static func funds(_ s: GameState) -> [Fund] {
        (s.rest["pe56"]?["mine"].array ?? []).map {
            Fund(id: $0["id"].int, style: $0["k"].string, name: $0["n"].string, startWeek: $0["w0"].int, committed: $0["com"].double, called: $0["called"].double, nav: $0["nav"].double,
                 distributed: $0["dist"].double, paidIn: $0["paid"].double, fees: $0["fee"].double, live: $0["st"].string == "live", sold: $0["st"].string == "sold")
        }
    }
    public static func yearOfFund(_ f: Fund, _ s: GameState) -> Int { Int(Double(s.week - f.startWeek) / 52) + 1 }
    static func discount(_ f: JSONValue, _ s: GameState) -> Double {
        clamp(0.35 - yearsIn(f, s) * 0.025 - (f["q"].double - 0.5) * 0.1 + (s.economy.demand < 0.97 ? 0.08 : 0), 0.08, 0.45)
    }
    /// What a buyer would pay for your stake today on the secondary market.
    public static func secondaryPrice(_ s: GameState, fundID: Int) -> Double {
        guard let f = (s.rest["pe56"]?["mine"].array ?? []).first(where: { $0["id"].int == fundID }) else { return 0 }
        return jsRound(f["nav"].double * (1 - discount(f, s)))
    }
    public static func secondaryDiscount(_ s: GameState, fundID: Int) -> Double {
        (s.rest["pe56"]?["mine"].array ?? []).first(where: { $0["id"].int == fundID }).map { discount($0, s) } ?? 0
    }

    // MARK: Actions

    public enum CommitResult: Equatable { case ok, tooSmall, notRichEnough, gone }

    /// Commit an amount to a fund. Funds take money only from investors whose net worth is at least 1.5 times the commitment. Original: `commit`.
    @discardableResult
    public static func commit(_ s: inout GameState, offerID: String, amount: Double, data: GameData, context fc: FinanceContext) -> CommitResult {
        refresh(&s, context: fc)
        var pe = s.rest["pe56"]!
        guard let n = pe["offers"].array.firstIndex(where: { $0["id"].string == offerID }) else { return .gone }
        let o = pe["offers"].array[n]
        let amt = jsRound(amount)
        if amt < o["min"].double { return .tooSmall }
        if Valuation.netWorth(s, trades: data.catalog).total < amt * 1.5 { return .notRichEnough }
        var mine = pe["mine"].array
        mine.append(.object(["id": .number(Double(s.makeID())), "o": o["id"], "n": o["n"], "k": o["k"], "q": o["q"], "w0": .number(Double(s.week)), "com": .number(amt),
                             "called": 0, "nav": 0, "dist": 0, "paid": 0, "fee": 0, "st": "live"]))
        pe["mine"] = .array(mine)
        var offs = pe["offers"].array; offs.remove(at: n); pe["offers"] = .array(offs)
        s.rest["pe56"] = pe
        return .ok
    }

    /// Sell a stake on the secondary market. Returns the cash you get. Original: `PE56.sell`.
    @discardableResult
    public static func sellStake(_ s: inout GameState, fundID: Int) -> Double? {
        guard var pe = s.rest["pe56"], var mine = Optional(pe["mine"].array), let k = mine.firstIndex(where: { $0["id"].int == fundID && $0["st"].string == "live" }) else { return nil }
        var f = mine[k]
        let get = jsRound(f["nav"].double * (1 - discount(f, s)))
        Payments.playerReceives(&s, get, label: "Sold on the secondary market: \(f["n"].string)")
        let gain = max(0, f["dist"].double + get - f["paid"].double) - f["taxed"].double
        if gain > 0 { s.tax.gains += gain }
        f["dist"] = .number(f["dist"].double + get); f["nav"] = 0; f["st"] = "sold"
        mine[k] = f; pe["mine"] = .array(mine); s.rest["pe56"] = pe
        return get
    }

    // MARK: The week

    /// Value moves every week; every quarter: fees, capital calls, money back, and winding up after ten years. Original: 'private equity funds' step.
    public static func weekly(_ s: inout GameState, context fc: FinanceContext) {
        refresh(&s, context: fc)
        guard var pe = s.rest["pe56"], var mine = Optional(pe["mine"].array), !mine.isEmpty else { return }
        for k in mine.indices where mine[k]["st"].string == "live" {
            var f = mine[k]
            guard let st = styles[f["k"].string] else { continue }
            let yr = yearsIn(f, s)
            if f["nav"].double > 0 {
                let mu = (st.r + (f["q"].double - 0.5) * 0.12) / 52, sd = st.v / 52.0.squareRoot()
                f["nav"] = .number(max(0, f["nav"].double * (1 + mu + st.beta * ((s.rest["idxRet"]?.double ?? 0) - 0.0012) + s.random.gauss() * sd)))
            }
            if (s.week - f["w0"].int) % 13 != 12 { mine[k] = f; continue }
            let fee = jsRound(f["com"].double * (yr < 5 ? 0.02 : 0.01) / 4)
            f["fee"] = .number(f["fee"].double + fee)
            f["nav"] = .number(max(0, f["nav"].double - fee))
            if yr < 4 && f["called"].double < f["com"].double {
                let want = min(f["com"].double - f["called"].double, jsRound(f["com"].double * clamp(0.2 + s.random.gauss() * 0.08, 0.05, 0.4) / (yr < 1 ? 1 : 1.2)))
                if s.cash >= want {
                    Payments.playerPays(&s, want, label: "Capital call: \(f["n"].string)")
                    f["called"] = .number(f["called"].double + want); f["paid"] = .number(f["paid"].double + want); f["nav"] = .number(f["nav"].double + want)
                } else {
                    f["nav"] = .number(jsRound(f["nav"].double * 0.5)); f["com"] = f["called"]; f["miss"] = .number(Double(s.week))
                    s.addMessage(from: f["n"].string, title: "You missed a capital call",
                                 body: "The fund asked for \(Int(want)) and your account could not pay it. Under the fund rules you lose half your stake and will not be asked again.", tone: "bad")
                }
            }
            if yr >= 4 && f["nav"].double > 0 {
                let share = yr >= 10 ? 1 : clamp(0.05 + (yr - 4) * 0.035, 0.05, 0.3)
                var out = jsRound(f["nav"].double * share)
                let gross = f["gd"].double + out
                let due = max(0, gross - f["paid"].double * pow(1.08, yr)) * 0.2
                let carry = max(0, min(out, jsRound(due - f["carry"].double)))
                f["carry"] = .number(f["carry"].double + carry)
                f["gd"] = .number(gross)
                f["nav"] = .number(f["nav"].double - out)
                out -= carry
                f["dist"] = .number(f["dist"].double + out)
                Payments.playerReceives(&s, out, label: "Distribution: \(f["n"].string)")
                let gain = max(0, f["dist"].double - f["paid"].double) - f["taxed"].double
                if gain > 0 { s.tax.gains += gain; f["taxed"] = .number(f["taxed"].double + gain) }
            }
            if yr >= 10 {
                f["st"] = "done"; f["nav"] = 0
                let mult = f["paid"].double > 0 ? f["dist"].double / f["paid"].double : 0
                s.addMessage(from: f["n"].string, title: "The fund has closed", body: "You paid in \(Int(f["paid"].double)) and got back \(Int(f["dist"].double)) (\(String(format: "%.2f", mult))x).", tone: f["dist"].double >= f["paid"].double ? "good" : "bad")
            }
            mine[k] = f
        }
        pe["mine"] = .array(mine)
        s.rest["pe56"] = pe
    }
}
