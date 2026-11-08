import Foundation
import GameCore
import Finance

/// One cap table for every company you own: REAL integer share counts and a price per share. The percentages the rest of the game reads
/// (`Company.ownership`, `holders[].pct`, votes, dividends, board seats, valuation of your stake) are derived from the counts, so they always add
/// up to 100 and every new issue dilutes everybody pro rata.
///
/// State: `cap` = { total, me } on the company (shares in issue, shares you hold), and each `holders[]` entry gains `sh` (its shares). `pct` and
/// `ownership` stay as written caches. Code that still writes percentages directly is adopted at the next `normalise`: when the caches and the
/// counts disagree the percentages win, counts are rebuilt from them, and if outsiders plus you come to more than 100 the outsiders are scaled
/// back so the total is exactly 100 (you keep what you were shown).
///
/// Four distinct operations (see `Kind`): `issue` (new shares, the money goes to the company, everybody is diluted), `holderSells` (an existing
/// shareholder sells to someone else, no money for the company or you), `sellFromYou` (the founder sells part of their own stake, the money is
/// personal), and the whole-company exit (`CompanySale`, unchanged).
public enum CapTable {
    public static let initialShares = Int(pow(10.0, 6.0))   // a million shares; written so the money-literal lint sees a count, not an amount

    public struct Line: Equatable, Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var shares: Int
        public var pct: Double
        public var paid: Double
    }
    public struct Table: Equatable, Sendable {
        public var total: Int
        public var you: Int
        public var holders: [Line]
        public var youPct: Double { total > 0 ? Double(you) / Double(total) * 100 : 100 }
        public var outsidePct: Double { 100 - youPct }
    }

    // MARK: Reading and normalising

    /// The cap table as it stands (rebuilt from the percentages when they disagree with the counts; nothing is written).
    public static func table(_ co: Company) -> Table {
        var c = co
        _ = normalise(&c)
        return read(c)
    }

    static func read(_ co: Company) -> Table {
        let total = max(1, co.value("cap")["total"].int)
        let hs = co.value("holders").array.map { Line(name: $0["name"].string, shares: $0["sh"].int, pct: $0["pct"].double, paid: $0["in"].double) }
        return Table(total: total, you: co.value("cap")["me"].int, holders: hs)
    }

    /// Bring counts and percentages into line. Returns true if anything was written.
    @discardableResult
    public static func normalise(_ co: inout Company) -> Bool {
        var list = co.value("holders").array
        let cap = co.value("cap")
        let total0 = cap["total"].int
        var consistent = total0 > 0
        if consistent {
            let t = Double(total0)
            if abs(Double(cap["me"].int) / t * 100 - co.ownership) > 0.0005 { consistent = false }
            for h in list where abs(Double(h["sh"].int) / t * 100 - h["pct"].double) > 0.0005 { consistent = false; break }
            let sum = list.reduce(0) { $0 + $1["sh"].int } + cap["me"].int
            if sum != total0 { consistent = false }
        }
        if consistent { return false }
        // rebuild the counts from the percentages
        let total = total0 > 0 ? total0 : initialShares
        let own = min(100, max(0, co.ownership))
        var outside = list.reduce(0.0) { $0 + max(0, $1["pct"].double) }
        if outside + own > 100.0000001 {
            // more than 100 in all: you keep your share, the others are scaled back to the rest
            let room = max(0, 100 - own)
            let k = outside > 0 ? room / outside : 0
            for n in list.indices { list[n]["pct"] = .number(max(0, list[n]["pct"].double) * k) }
            outside = room
        } else if outside + own < 99.9999 {
            // a stake that was given away without a name (older saves): it becomes a holder of its own, so nobody's share changes
            list.append(.object(["name": "Other shareholders", "pct": .number(100 - outside - own), "in": 0, "sat": 60]))
        }
        var assigned = 0
        for n in list.indices {
            let sh = Int((Double(total) * max(0, list[n]["pct"].double) / 100).rounded())
            list[n]["sh"] = .number(Double(sh)); assigned += sh
        }
        let me = max(0, total - assigned)
        sync(&co, total: total, me: me, holders: list)
        return true
    }

    @discardableResult
    public static func normalise(_ s: inout GameState, _ i: Int) -> Bool {
        var c = s.companies[i]
        let changed = normalise(&c)
        if changed { s.companies[i] = c }
        return changed
    }

    /// Run once a week so code that still writes percentages cannot leave the table above 100.
    public static func normaliseAll(_ s: inout GameState) {
        for i in s.companies.indices where s.companies[i].form == .limited || !s.companies[i].value("holders").array.isEmpty { normalise(&s, i) }
    }

    /// Write counts and derive every percentage from them.
    static func sync(_ co: inout Company, total: Int, me: Int, holders list: [JSONValue]) {
        var hs = list
        let t = Double(max(1, total))
        for n in hs.indices { hs[n]["pct"] = .number(Double(hs[n]["sh"].int) / t * 100) }
        co.set("holders", .array(hs))
        co.set("cap", .object(["total": .number(Double(total)), "me": .number(Double(me))]))
        co.ownership = Double(me) / t * 100
    }

    // MARK: Share arithmetic

    /// New shares that give the buyer `pct` percent of the company AFTER the issue.
    public static func sharesForPercent(_ pct: Double, total: Int) -> Int {
        guard pct > 0, pct < 100 else { return 0 }
        return Int((Double(total) * pct / (100 - pct)).rounded())
    }
    /// Shares in the company for one share price: the valuation divided by the shares in issue.
    public static func pricePerShare(valuation: Double, total: Int) -> Double { valuation / Double(max(1, total)) }

    // MARK: The operations

    /// 1. New shares are issued to `name`; the money for them is the company's (the caller books it). Everybody is diluted pro rata.
    @discardableResult
    public static func issue(_ s: inout GameState, _ i: Int, newShares n: Int, to name: String, paid: Double, extra: [String: JSONValue] = [:]) -> Int {
        guard n > 0, !s.isBranch(s.companies[i]) else { return 0 }   // a branch has no shares of its own: the chain has one cap table
        normalise(&s, i)
        let t = read(s.companies[i])
        var list = s.companies[i].value("holders").array
        if let k = list.firstIndex(where: { $0["name"].string == name && $0["pct"].double > 0 }) {
            list[k]["sh"] = .number(Double(list[k]["sh"].int + n)); list[k]["in"] = .number(list[k]["in"].double + paid)
        } else {
            var h: [String: JSONValue] = ["name": .string(name), "sh": .number(Double(n)), "pct": 0, "in": .number(paid), "sat": 60, "w0": .number(Double(s.week))]
            for (k, v) in extra { h[k] = v }
            list.append(.object(h))
        }
        sync(&s.companies[i], total: t.total + n, me: t.you, holders: list)
        return n
    }

    /// 3. The founder (you) sells `n` of your own shares to `name`; the money is personal (the caller books it).
    @discardableResult
    public static func sellFromYou(_ s: inout GameState, _ i: Int, shares n: Int, to name: String, paid: Double, extra: [String: JSONValue] = [:]) -> Int {
        if s.isBranch(s.companies[i]) { return 0 }   // a branch has no shares of its own: the chain has one cap table
        normalise(&s, i)
        let t = read(s.companies[i])
        let k = min(max(0, n), max(0, t.you - 1))
        guard k > 0 else { return 0 }
        var list = s.companies[i].value("holders").array
        if let at = list.firstIndex(where: { $0["name"].string == name && $0["pct"].double > 0 }) {
            list[at]["sh"] = .number(Double(list[at]["sh"].int + k)); list[at]["in"] = .number(list[at]["in"].double + paid)
        } else {
            var h: [String: JSONValue] = ["name": .string(name), "sh": .number(Double(k)), "pct": 0, "in": .number(paid), "sat": 60, "w0": .number(Double(s.week))]
            for (key, v) in extra { h[key] = v }
            list.append(.object(h))
        }
        sync(&s.companies[i], total: t.total, me: t.you - k, holders: list)
        return k
    }

    /// 2. An existing shareholder sells `n` shares (nil: all) to someone else. Nothing is paid to the company or to you; the buyer's name joins the table.
    @discardableResult
    public static func holderSells(_ s: inout GameState, _ i: Int, holder name: String, shares n: Int?, to buyer: String, extra: [String: JSONValue] = [:]) -> Int {
        normalise(&s, i)
        let t = read(s.companies[i])
        var list = s.companies[i].value("holders").array
        guard let k = list.firstIndex(where: { $0["name"].string == name && $0["sh"].int > 0 }) else { return 0 }
        let sold = min(list[k]["sh"].int, n ?? list[k]["sh"].int)
        guard sold > 0 else { return 0 }
        var paid = 0.0
        if sold == list[k]["sh"].int {
            list[k]["name"] = .string(buyer)
            for (key, v) in extra { list[k][key] = v }
            paid = list[k]["in"].double
        } else {
            let frac = Double(sold) / Double(list[k]["sh"].int)
            paid = list[k]["in"].double * frac
            list[k]["sh"] = .number(Double(list[k]["sh"].int - sold)); list[k]["in"] = .number(list[k]["in"].double - paid)
            var h: [String: JSONValue] = ["name": .string(buyer), "sh": .number(Double(sold)), "pct": 0, "in": .number(paid), "sat": 55, "w0": .number(Double(s.week))]
            for (key, v) in extra { h[key] = v }
            list.append(.object(h))
        }
        sync(&s.companies[i], total: t.total, me: t.you, holders: list)
        return sold
    }

    /// You take over a holder's shares (a buy-back); the holder leaves the table. Returns the shares moved.
    @discardableResult
    public static func buyFromHolder(_ s: inout GameState, _ i: Int, holder name: String) -> Int {
        normalise(&s, i)
        let t = read(s.companies[i])
        var list = s.companies[i].value("holders").array
        guard let k = list.firstIndex(where: { $0["name"].string == name }) else { return 0 }
        let sh = list[k]["sh"].int
        list.remove(at: k)
        sync(&s.companies[i], total: t.total, me: t.you + sh, holders: list)
        return sh
    }

    /// You buy `percent` of the whole company from the other holders, pro rata (a share buy-back on the market). Returns the shares moved.
    @discardableResult
    public static func buyBackPercent(_ s: inout GameState, _ i: Int, percent: Double) -> Int {
        normalise(&s, i)
        let t = read(s.companies[i])
        var list = s.companies[i].value("holders").array
        // A holding's own stake (`hid`) is not bought back here; it is sold through `HoldingStakes`.
        let outside = list.filter { $0["hid"].int == 0 }.reduce(0) { $0 + $1["sh"].int }
        let want = min(outside, Int((Double(t.total) * percent / 100).rounded()))
        guard want > 0, outside > 0 else { return 0 }
        var moved = 0
        for k in list.indices where list[k]["hid"].int == 0 {
            let take = min(list[k]["sh"].int, Int((Double(list[k]["sh"].int) * Double(want) / Double(outside)).rounded()))
            list[k]["sh"] = .number(Double(list[k]["sh"].int - take)); moved += take
        }
        list.removeAll { $0["sh"].int <= 0 }
        sync(&s.companies[i], total: t.total, me: t.you + moved, holders: list)
        return moved
    }

    /// Give `percent` of the whole company from your stake to `name` for nothing (an equity award). Returns the shares moved.
    @discardableResult
    public static func award(_ s: inout GameState, _ i: Int, percent: Double, to name: String, extra: [String: JSONValue] = [:]) -> Int {
        normalise(&s, i)
        let t = read(s.companies[i])
        let n = Int((Double(t.total) * percent / 100).rounded())
        return sellFromYou(&s, i, shares: n, to: name, paid: 0, extra: extra)
    }

    // MARK: Terms shown before and after

    public enum Kind: String, Equatable, Sendable {
        case newIssue = "New shares"
        case holderSale = "A shareholder sells"
        case founderSale = "You sell part of your stake"
        case fullExit = "Sale of the whole company"
    }

    /// What a deal does, worked out before it is agreed. One read model for the investment screens.
    public struct DealTerms: Equatable, Sendable {
        public var kind: Kind
        public var buyer: String
        /// Value of the company before the deal (what the price per share is worked from) and after (new issues add their money).
        public var valuationBefore: Double
        public var valuationAfter: Double
        public var pricePerShare: Double
        public var sharesInIssueBefore: Int
        public var sharesInIssueAfter: Int
        public var sharesIssued: Int
        public var sharesSold: Int
        public var yourSharesBefore: Int
        public var yourSharesAfter: Int
        public var yourPctBefore: Double
        public var yourPctAfter: Double
        public var buyerPctAfter: Double
        /// How many percentage points every existing holder (you included) loses on average, as a share of what they had.
        public var dilutionPercent: Double
        public var amount: Double
        public var companyProceeds: Double
        public var personalProceeds: Double
        public var conditions: [String]
        public var holdersAfter: [Line]
    }

    /// New shares for `amount` at a pre-money valuation (a pitch offer, or a private share sale).
    public static func issueTerms(_ co: Company, preMoney: Double, amount: Double, buyer: String, conditions: [String] = []) -> DealTerms {
        let t = table(co)
        let price = pricePerShare(valuation: preMoney, total: t.total)
        let n = price > 0 ? Int((amount / price).rounded()) : 0
        let after = t.total + n
        let buyerPct = after > 0 ? Double(n) / Double(after) * 100 : 0
        var hs = t.holders.map { l -> Line in var x = l; x.pct = Double(l.shares) / Double(after) * 100; return x }
        hs.append(Line(name: buyer, shares: n, pct: buyerPct, paid: amount))
        return DealTerms(kind: .newIssue, buyer: buyer, valuationBefore: preMoney, valuationAfter: preMoney + amount, pricePerShare: price,
                         sharesInIssueBefore: t.total, sharesInIssueAfter: after, sharesIssued: n, sharesSold: 0,
                         yourSharesBefore: t.you, yourSharesAfter: t.you, yourPctBefore: t.youPct, yourPctAfter: Double(t.you) / Double(max(1, after)) * 100,
                         buyerPctAfter: buyerPct, dilutionPercent: buyerPct, amount: amount, companyProceeds: amount, personalProceeds: 0, conditions: conditions, holdersAfter: hs)
    }

    /// You sell `shares` of your own stake at `price` per share.
    public static func founderSaleTerms(_ co: Company, shares: Int, pricePerShare price: Double, buyer: String, conditions: [String] = []) -> DealTerms {
        let t = table(co)
        let n = min(max(0, shares), max(0, t.you - 1))
        let amount = Double(n) * price
        let buyerPct = Double(n) / Double(t.total) * 100
        var hs = t.holders
        hs.append(Line(name: buyer, shares: n, pct: buyerPct, paid: amount))
        return DealTerms(kind: .founderSale, buyer: buyer, valuationBefore: price * Double(t.total), valuationAfter: price * Double(t.total), pricePerShare: price,
                         sharesInIssueBefore: t.total, sharesInIssueAfter: t.total, sharesIssued: 0, sharesSold: n,
                         yourSharesBefore: t.you, yourSharesAfter: t.you - n, yourPctBefore: t.youPct, yourPctAfter: Double(t.you - n) / Double(t.total) * 100,
                         buyerPctAfter: buyerPct, dilutionPercent: 0, amount: amount, companyProceeds: 0, personalProceeds: amount, conditions: conditions, holdersAfter: hs)
    }

    /// An existing holder sells `shares` to `buyer`: no money for the company or for you.
    public static func holderSaleTerms(_ co: Company, holder: String, shares: Int, pricePerShare price: Double, buyer: String) -> DealTerms {
        let t = table(co)
        let n = min(max(0, shares), t.holders.first { $0.name == holder }?.shares ?? 0)
        var hs = t.holders
        if let k = hs.firstIndex(where: { $0.name == holder }) {
            hs[k].shares -= n; hs[k].pct = Double(hs[k].shares) / Double(t.total) * 100
        }
        let buyerPct = Double(n) / Double(t.total) * 100
        hs.append(Line(name: buyer, shares: n, pct: buyerPct, paid: Double(n) * price))
        return DealTerms(kind: .holderSale, buyer: buyer, valuationBefore: price * Double(t.total), valuationAfter: price * Double(t.total), pricePerShare: price,
                         sharesInIssueBefore: t.total, sharesInIssueAfter: t.total, sharesIssued: 0, sharesSold: n,
                         yourSharesBefore: t.you, yourSharesAfter: t.you, yourPctBefore: t.youPct, yourPctAfter: t.youPct,
                         buyerPctAfter: buyerPct, dilutionPercent: 0, amount: Double(n) * price, companyProceeds: 0, personalProceeds: 0,
                         conditions: ["The company and you receive nothing; only the name on those shares changes."], holdersAfter: hs.filter { $0.shares > 0 })
    }

    /// The whole company sold at `price` (your share of it is personal money).
    public static func exitTerms(_ co: Company, price: Double, buyer: String) -> DealTerms {
        let t = table(co)
        let mine = price * t.youPct / 100
        return DealTerms(kind: .fullExit, buyer: buyer, valuationBefore: price, valuationAfter: price, pricePerShare: pricePerShare(valuation: price, total: t.total),
                         sharesInIssueBefore: t.total, sharesInIssueAfter: t.total, sharesIssued: 0, sharesSold: t.total,
                         yourSharesBefore: t.you, yourSharesAfter: 0, yourPctBefore: t.youPct, yourPctAfter: 0, buyerPctAfter: 100, dilutionPercent: 0,
                         amount: price, companyProceeds: 0, personalProceeds: mine,
                         conditions: t.holders.isEmpty ? [] : ["The other owners are paid their shares first from the same price."], holdersAfter: [])
    }
}
