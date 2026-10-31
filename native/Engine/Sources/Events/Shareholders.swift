import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Owners who have a say. Outside investors (those who bought shares in a company of yours) have a profile (want dividends, want growth, want a
/// sale, or stay quiet) and a mood that moves with results. Unhappy owners make demands. What happens when you say no depends on how many shares
/// they hold: over half and they outvote you; over a third and they block big moves; less and they may sell their stake, sometimes to a rival
/// group. Each limited company has a dividend policy paid every quarter. Original: features/company/owner_investors.js (round 27d).
///
/// State on the company: `holders` = [{ name, pct, in, k27 (profile), sat (mood), w0, g27? }], `dp27` (dividend policy: none, low, mid, high), `block27`
/// (week until which the other owners block big moves), `dm27` (next demand not before), `dq27` = { w, paid, pr } (the last quarter).
/// The inbox action of a demand is "own27" (data: { co, kind, amt, hn }).
///
/// Not ported: the yearly review of the manager, and the "replace the manager" demand (it needs the manager hiring of the original's `replaceMgr`).
public enum Shareholders {
    public static let action = "own27"
    public static let policies = ["none", "low", "mid", "high"]
    public static let payout: [String: Double] = ["none": 0, "low": 0.25, "mid": 0.5, "high": 0.8]
    public static let policyNames: [String: String] = ["none": "Reinvest everything", "low": "25% of profit", "mid": "50% of profit", "high": "80% of profit"]
    public static let profileNames: [String: String] = ["div": "Wants dividends", "growth": "Wants growth", "exit": "Wants a sale", "quiet": "Quiet"]

    public struct Holder: Identifiable, Equatable {
        public var id: String { name }
        public var name: String
        public var pct: Double
        public var profile: String
        public var mood: Double
        public var boardSeat: Bool { pct >= 20 }
        public var moodWord: String { mood >= 70 ? "Happy" : mood >= 50 ? "Content" : mood >= 35 ? "Uneasy" : "Angry" }
    }
    public enum Power: String { case control, block, voice, none }

    // MARK: Reading

    public static func outside(_ co: Company) -> Double { max(0, 100 - co.ownership) }
    /// What the other owners can do, by their share. Original: `power`.
    public static func power(_ co: Company) -> (kind: Power, text: String) {
        let o = outside(co)
        if o > 50 { return (.control, "They can outvote you: dividends, the manager, accepting a takeover bid.") }
        if o >= 33.4 { return (.block, "They can block big changes: selling the company, new shares, mergers.") }
        if o > 0 { return (.voice, "They have a voice and board seats, but you decide.") }
        return (.none, "You own it all.")
    }
    static func profile(_ h: inout JSONValue, seed: Int, week: Int) -> String {
        if h["k27"].isNull {
            let x = HashedRandom.first("\(seed):ip:\(h["name"].string)")
            let n = h["name"].string.lowercased()
            let fundish = ["fund", "capital", "partners", "invest", "group", "equity"].contains { n.contains($0) }
            h["k27"] = .string(!h["g27"].isNull ? "exit" : fundish ? (x < 0.5 ? "exit" : "growth") : x < 0.38 ? "div" : x < 0.66 ? "growth" : x < 0.78 ? "exit" : "quiet")
            if h["sat"].isNull { h["sat"] = 60 }
            if h["w0"].isNull { h["w0"] = .number(Double(week)) }
        }
        return h["k27"].string
    }
    public static func holders(_ s: GameState, companyID: Int) -> [Holder] {
        guard let co = s.company(companyID) else { return [] }
        return co.value("holders").array.filter { $0["pct"].double > 0 }.map { var h = $0; let p = profile(&h, seed: s.seed, week: s.week); return Holder(name: h["name"].string, pct: h["pct"].double, profile: p, mood: h["sat"].double) }
    }
    /// The average mood of the other owners, weighted by their share. Original: `holderSat`.
    public static func averageMood(_ s: GameState, companyID: Int) -> Double {
        let hs = holders(s, companyID: companyID)
        if hs.isEmpty { return 60 }
        return hs.reduce(0) { $0 + $1.mood * $1.pct } / max(0.01, hs.reduce(0) { $0 + $1.pct })
    }
    public static func policy(_ co: Company) -> String { co.str("dp27", "none") }
    public static func blockedUntil(_ co: Company) -> Int? { co.value("block27").isNull ? nil : co.int("block27") }
    /// True while the other owners block share sales and the sale of the company.
    public static func isBlocked(_ s: GameState, companyID: Int) -> Bool { (s.company(companyID).flatMap { blockedUntil($0) } ?? 0) > s.week }
    /// What a buy-back of one holder's stake would cost: at value from an unhappy owner, 12% more otherwise.
    public static func buyBackPrice(_ s: GameState, companyID: Int, holder name: String, data: GameData) -> Double? {
        guard let co = s.company(companyID), let h = holders(s, companyID: companyID).first(where: { $0.name == name }) else { return nil }
        let v0 = max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
        return (v0 * h.pct / 100 * (h.mood < 40 ? 1.0 : 1.12) / 1000).rounded() * 1000
    }

    // MARK: Actions

    public static func setPolicy(_ s: inout GameState, companyID: Int, policy p: String) {
        guard let i = s.companyIndex(companyID), policies.contains(p) else { return }
        s.companies[i].set("dp27", p)
    }

    /// Buy one owner's stake back from your own account. Original: `ACT.own27buy`.
    @discardableResult
    public static func buyBack(_ s: inout GameState, companyID: Int, holder name: String, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), let price = buyBackPrice(s, companyID: companyID, holder: name, data: data), Payments.liquid(s) >= price else { return false }
        var list = s.companies[i].value("holders").array
        guard let k = list.firstIndex(where: { $0["name"].string == name }) else { return false }
        let h = list[k]
        Payments.transferFromSavings(&s, need: price)
        Payments.playerPays(&s, price, label: "Bought \(name)'s stake in \(s.companies[i].name)", companyID: companyID)
        s.companies[i].ownership = min(100, s.companies[i].ownership + h["pct"].double)
        list.remove(at: k)
        s.companies[i].set("holders", .array(list))
        if h["pct"].double >= 20 {
            var f = s.companies[i].value("flags"); f["boardSeat"] = .number(max(0, (f["boardSeat"].isNull ? 1 : f["boardSeat"].double) - 1)); s.companies[i].set("flags", f)
        }
        s.note("You now own \(Int(s.companies[i].ownership.rounded()))% of \(s.companies[i].name).", tone: "good", companyID: companyID)
        return true
    }

    // MARK: The quarter

    static func quarterProfit(_ co: Company) -> Double { co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit } }
    static func yearOnYear(_ co: Company) -> Double? {
        let h = co.monthlyHistory
        if h.count < 15 { return nil }
        let a = h.suffix(3).reduce(0) { $0 + $1.revenue }, b = h[(h.count - 15)..<(h.count - 12)].reduce(0) { $0 + $1.revenue }
        return b > 0 ? a / b - 1 : nil
    }
    static func bump(_ s: inout GameState, _ i: Int, _ v: Double) {
        var list = s.companies[i].value("holders").array
        for k in list.indices { _ = profile(&list[k], seed: s.seed, week: s.week); list[k]["sat"] = .number(clamp(list[k]["sat"].double + v, 0, 100)) }
        s.companies[i].set("holders", .array(list))
    }

    /// Dividend by policy, then the owners' mood. Original: `quarter`.
    static func quarter(_ s: inout GameState, _ i: Int, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        guard co.status == .open, co.form == .limited, co.type != "hold" else { return }
        let pol = policy(co), pr = quarterProfit(co)
        var paid = 0.0
        if (payout[pol] ?? 0) > 0 && pr > 0 {
            let amt = (pr * payout[pol]! / 1000).rounded() * 1000
            let r = amt > 0 ? Payments.payDividend(&s, companyID: co.id, amount: amt, context: fc) : .noRetainedProfit
            if r == .ok { paid = amt; s.note("\(co.name) paid a dividend of \(fc.currency(co.countryCode, s).display(amt)) (\((policyNames[pol] ?? "").lowercased())).", tone: "good", companyID: co.id) }
            else if r == .notEnoughCash { s.note("\(co.name) skipped its dividend: not enough cash after costs.", tone: "n", companyID: co.id) }
        }
        s.companies[i].set("dq27", .object(["w": .number(Double(s.week)), "paid": .number(paid), "pr": .number(pr)]))
        var list = s.companies[i].value("holders").array
        let idx = list.indices.filter { list[$0]["pct"].double > 0 }
        if idx.isEmpty { return }
        let g = yearOnYear(s.companies[i])
        let below = 0   // owners also mind your own supply companies selling below cost; not ported
        for k in idx {
            let kind = profile(&list[k], seed: s.seed, week: s.week)
            var d = (60 - list[k]["sat"].double) * 0.05
            if pr < 0 { d -= 4 }
            if kind == "div" { d += paid > 0 && paid >= pr * 0.35 ? 6 : pr > 0 ? -6 : -2 }
            if kind == "growth" {
                d += g == nil ? 0 : g! > 0.1 ? 7 : g! > 0.02 ? 2 : g! < 0 ? -6 : -1
                if paid > pr * 0.6 && pr > 0 { d -= 2 }
            }
            if kind == "exit" { let yrs = Double(s.week - list[k]["w0"].int) / 52; d += yrs > 3 ? -5 : (g ?? 0) > 0.08 ? 3 : 0 }
            if kind == "quiet" { d *= 0.5 }
            if below > 0 { d -= 6 * Double(below) }
            if s.companies[i].managerID != nil, s.companies[i].value("mood").double < 35, !s.companies[i].value("mood").isNull { d -= 2 }
            list[k]["sat"] = .number(clamp(jsRound(list[k]["sat"].double + d), 0, 100))
        }
        s.companies[i].set("holders", .array(list))
        maybeDemand(&s, i, data: data, context: fc)
    }

    static func maybeDemand(_ s: inout GameState, _ i: Int, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        if s.week < co.int("dm27") { return }
        var list = co.value("holders").array.filter { $0["pct"].double > 0 }
        guard let ix = list.indices.filter({ list[$0]["sat"].double < 38 }).max(by: { list[$0]["pct"].double < list[$1]["pct"].double }) else { return }
        var unhappy = list[ix]
        s.companies[i].set("dm27", s.week + 26)
        let k = profile(&unhappy, seed: s.seed, week: s.week)
        let cur = fc.currency(co.countryCode, s)
        let pr = max(0, co.monthlyHistory.suffix(12).reduce(0) { $0 + $1.profit }), v0 = max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
        let pw = power(co), o = outside(co)
        let tail = pw.kind == .control ? " Outside owners hold \(Int(o.rounded()))%, so they can push this through without you."
            : pw.kind == .block ? " They hold \(Int(o.rounded()))% between them and can block your big moves if you refuse."
            : " They hold \(Int(o.rounded()))%. If you refuse, they may sell their stake to someone else."
        let name = unhappy["name"].string
        var title = "", body = "", opts: [String] = [], kind = "", amt = 0.0
        if k == "div" {
            amt = (pr * 0.5 / 1000).rounded() * 1000
            title = "\(name) wants a dividend from \(co.name)"; body = "They want \(cur.display(amt)) paid out (half of last year's profit) and a policy of regular dividends."
            opts = ["Pay it, and set 50% as policy", "Pay half now", "Refuse: the money stays in the company"]; kind = "div"
        } else if k == "growth" {
            amt = (max(cur.scaledPrice(50000), co.lastWeekRevenue * 6) / 1000).rounded() * 1000
            title = "\(name) wants \(co.name) to grow faster"; body = "They want \(cur.display(amt)) spent on marketing over the next three months, or a second site."
            opts = ["Agree to the marketing push", "Show them your own plan", "Refuse"]; kind = "growth"
        } else if k == "exit" {
            amt = (v0 * unhappy["pct"].double / 100 * 1.1 / 1000).rounded() * 1000
            title = "\(name) wants out of \(co.name)"
            body = "They have held their \(String(format: "%.1f", unhappy["pct"].double))% for \(Int((Double(s.week - unhappy["w0"].int) / 52).rounded())) years and want their money back: sell the company, or buy their stake for about \(cur.display(amt))."
            opts = ["Buy their stake", "Sell the whole company", "Refuse"]; kind = "exit"
        } else { return }
        s.addMessage(kind: "ask", from: "\(name), shareholder", title: title, body: body + tail, companyID: co.id, tone: "bad", status: "open",
                     options: opts.map { .option($0) }, action: action, data: .object(["co": .number(Double(co.id)), "kind": .string(kind), "amt": .number(amt), "hn": .string(name)]), expiresWeek: s.week + 3)
    }

    // MARK: Answers

    /// The player's answer to an owners' demand. Original: `ACTS.own27`, `resolveDemand`.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context fc: FinanceContext) {
        let d = m.value("data")
        guard let i = s.companyIndex(d["co"].int), s.companies[i].status == .open else { return }
        resolve(&s, i, d, idx, data: data, context: fc)
    }
    /// Nobody answered in time: you refused. Original: the 'auto' loop in the weekly step.
    public static func expired(_ s: inout GameState, message m: Message, data: GameData, context fc: FinanceContext) {
        let d = m.value("data")
        guard let i = s.companyIndex(d["co"].int), s.companies[i].status == .open else { return }
        refused(&s, i, d, data: data, context: fc)
    }

    static func resolve(_ s: inout GameState, _ i: Int, _ d: JSONValue, _ idx: Int, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i], id = co.id
        switch d["kind"].string {
        case "div":
            if idx == 0 || idx == 1 {
                let amt = idx == 0 ? d["amt"].double : (d["amt"].double / 2000).rounded() * 1000
                let r = Payments.payDividend(&s, companyID: id, amount: amt, context: fc)
                if r == .ok { if idx == 0 { s.companies[i].set("dp27", "mid") }; bump(&s, i, idx == 0 ? 18 : 8) }
                else { s.note("\(co.name) could not pay: \(r == .notEnoughCash ? "not enough cash." : "not enough equity.")", tone: "bad", companyID: id); bump(&s, i, -4) }
                return
            }
            refused(&s, i, d, data: data, context: fc)
        case "growth":
            if idx == 0 {
                let a = d["amt"].double
                if Payments.companyPays(&s, companyID: id, amount: a, category: "mkt", label: "Marketing push agreed with the owners") || s.companies[i].cash > -fc.overdraftRoom(s.companies[i], s) {
                    s.companies[i].awareness = min(100, s.companies[i].awareness + 8)
                    EventEngine.addModifier(&s, i, key: "dem", multiplier: 1.06, weeks: 13)
                    bump(&s, i, 15)
                }
                return
            }
            if idx == 1 { bump(&s, i, s.random.chance(0.6) ? 8 : -2); s.companies[i].set("dm27", s.week + 26); return }
            refused(&s, i, d, data: data, context: fc)
        case "exit":
            let hn = d["hn"].string
            var list = co.value("holders").array
            if idx == 0, let k = list.firstIndex(where: { $0["name"].string == hn }) {
                let h = list[k], amt = d["amt"].double
                if Payments.liquid(s) < amt { s.note("You do not have \(fc.currency(co.countryCode, s).display(amt)) to buy the stake.", tone: "bad", companyID: id); refused(&s, i, d, data: data, context: fc); return }
                Payments.transferFromSavings(&s, need: amt)
                Payments.playerPays(&s, amt, label: "Bought \(hn)'s stake in \(co.name)", companyID: id)
                s.companies[i].ownership = min(100, co.ownership + h["pct"].double)
                list.remove(at: k); s.companies[i].set("holders", .array(list))
                s.note("You bought back \(String(format: "%.1f", h["pct"].double))% of \(co.name). You now own \(Int(s.companies[i].ownership.rounded()))%.", tone: "good", companyID: id)
                return
            }
            if idx == 1 { sellOut(&s, i, why: "The owners agreed to sell", data: data, context: fc); return }
            refused(&s, i, d, data: data, context: fc)
        default: break
        }
    }

    static func refused(_ s: inout GameState, _ i: Int, _ d: JSONValue, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i], pw = power(co)
        bump(&s, i, -10)
        if pw.kind == .control {
            s.note("The other owners of \(co.name) outvoted you.", tone: "bad", companyID: co.id)
            switch d["kind"].string {
            case "div": _ = Payments.payDividend(&s, companyID: co.id, amount: d["amt"].double, context: fc); s.companies[i].set("dp27", "mid")
            case "growth":
                _ = Payments.companyPays(&s, companyID: co.id, amount: d["amt"].double, category: "mkt", label: "Marketing push forced by the owners")
                s.companies[i].awareness = min(100, s.companies[i].awareness + 8)
            case "exit": sellOut(&s, i, why: "The majority owners voted to sell", data: data, context: fc)
            default: break
            }
            return
        }
        if pw.kind == .block {
            s.companies[i].set("block27", s.week + 26)
            s.note("The other owners of \(co.name) will block share sales, a sale of the company and mergers for half a year.", tone: "bad", companyID: co.id)
            return
        }
        // a small, unhappy owner sells: sometimes to a rival group
        var list = s.companies[i].value("holders").array
        guard let k = list.indices.filter({ list[$0]["sat"].double < 40 }).max(by: { list[$0]["pct"].double < list[$1]["pct"].double }), s.random.chance(0.5) else { return }
        let old = list[k]["name"].string
        let gs = GroupStakes.groups(s, country: co.countryCode).filter { $0["dist"].int == 0 && (($0["types"].array.contains { $0.string == co.type }) || $0["strat"].string == "acq") }
        if !gs.isEmpty, s.random.chance(0.5) {
            let g = gs[s.random.int(0, gs.count - 1)]
            list[k]["name"] = g["name"]; list[k]["g27"] = g["id"]; list[k]["k27"] = "exit"; list[k]["sat"] = 45; list[k]["w0"] = .number(Double(s.week))
            s.companies[i].set("holders", .array(list))
            s.addMessage(from: "Shareholders of \(co.name)", title: "\(g["name"].string) now owns \(String(format: "%.1f", list[k]["pct"].double))% of \(co.name)",
                         body: "\(old) sold its stake to \(g["name"].string), a competitor. They will want a say, and may try to buy the rest.", companyID: co.id, tone: "bad")
        } else {
            let nm = Funding.personName(&s, countryCode: co.countryCode, data: data) + ", investor"
            list[k]["name"] = .string(nm); list[k]["k27"] = .null; list[k]["sat"] = 55; list[k]["w0"] = .number(Double(s.week))
            _ = profile(&list[k], seed: s.seed, week: s.week)
            s.companies[i].set("holders", .array(list))
            s.note("\(old) sold its stake in \(co.name) to \(nm).", tone: "n", companyID: co.id)
        }
    }

    /// The whole company is sold to the best buyer who pays now. Original: `sellOut`.
    static func sellOut(_ s: inout GameState, _ i: Int, why: String, data: GameData, context fc: FinanceContext) {
        guard s.companies[i].status == .open else { return }
        let co = s.companies[i], v = max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
        let price = jsRound(v * 0.98)
        let mine = price * co.ownership / 100
        if CompanySale.complete(&s, companyIndex: i, buyer: "A competitor", price: price, data: data, context: fc) != nil {
            s.addMessage(from: "Shareholders of \(co.name)", title: "\(co.name) is sold", body: "\(why). A competitor paid \(fc.currency(co.countryCode, s).display(price)); your \(Int(co.ownership.rounded()))% came to \(fc.currency(co.countryCode, s).display(mine)).", companyID: co.id)
        }
    }

    // MARK: The week

    /// Every third month, each limited company runs its quarter.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        let mi = GameCalendar.monthIndex(week: s.week)
        let last = s.rest["m27d"]?.int ?? mi
        if s.rest["m27d"] == nil { s.rest["m27d"] = .number(Double(mi)) }
        guard last != mi else { return }
        s.rest["m27d"] = .number(Double(mi))
        if mi % 3 == 0 { for i in s.companies.indices { quarter(&s, i, data: data, context: fc) } }
    }
}
