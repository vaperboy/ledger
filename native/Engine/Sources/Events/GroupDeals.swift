import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Deals between you and the rival groups of the world: a group bids for one of your companies (accept, ask for more, refuse; when outside owners
/// hold more than half they can accept without you), a group buys what you sell it, and you buy a stake in a group. Originals: `R27.bidFor`,
/// `sellToGroup`, `ACTS.g27bid`, `outsideVote` (features/world/rival_groups.js) and `buyStake` (features/world/business_events.js).
///
/// The groups themselves (`rest["g27"]`) are the Competition port's; this file only reads and pays them, so with no groups in the game no
/// bid arrives. The answer to a bid is the inbox action "g27bid", with the same data as the original ({ co, g, price, V0, round, fin }).
public enum GroupDeals {
    public static let bidAction = "g27bid"

    static func writeGroup(_ s: inout GameState, _ id: String, _ g: JSONValue) {
        guard s.rest["g27"] != nil else { return }
        s.rest["g27"]!["g"][id] = g
    }
    static func logMove(_ g: inout JSONValue, week: Int, _ text: String, country: String) {
        var mv = g["mv"].array
        mv.insert(.object(["w": .number(Double(week)), "t": .string(text), "cc": .string(country)]), at: 0)
        if mv.count > 10 { mv.removeLast(mv.count - 10) }
        g["mv"] = .array(mv)
    }
    static func pay(_ g: inout JSONValue, _ amount: Double) {
        g["cash"] = .number(g["cash"].double - jsRound(amount))
        if g["cash"].double < 0 { g["debt"] = .number(g["debt"].double - g["cash"].double); g["cash"] = 0 }
    }

    /// The group buys the company; you get your share of the price. The company becomes one of the group's local rivals. Original: `sellToGroup`.
    @discardableResult
    public static func sellToGroup(_ s: inout GameState, companyIndex i: Int, groupID: String, price: Double, data: GameData, context fc: FinanceContext) -> Bool {
        guard var g = GroupStakes.group(s, id: groupID), s.companies[i].status.isLive else { return false }
        let co = s.companies[i]
        guard CompanySale.complete(&s, companyIndex: i, buyer: g["name"].string, price: price, data: data, context: fc) != nil else { return false }
        let key = co.type + "|" + co.cityID
        if let bd = data.catalog[co.type], ["svc", "venue", "retail", "project", "prod", "logi"].contains(bd.family), var mk = s.rest["mk"], !mk[key].isNull {
            var riv = mk[key]["riv"].array
            riv.append(.object(["id": .number(Double(s.makeID())), "name": .string(co.name), "owner": g["owner"], "size": .number(jsRound(clamp(co.size, 0.5, 2) * 100) / 100),
                                "rel": 50, "listed": false, "ign": 0, "lock": 0, "meet": -99, "g27": .string(groupID)]))
            mk[key]["riv"] = .array(riv)
            mk[key]["n"] = .number(mk[key]["n"].double + 1)
            s.rest["mk"] = mk
        }
        pay(&g, price)
        g["br"] = .number(g["br"].double + 1)
        logMove(&g, week: s.week, "Bought \(co.name) from you", country: co.countryCode)
        writeGroup(&s, groupID, g)
        s.news("\(g["name"].string) buys \(co.name).", tone: "n")
        return true
    }

    /// A group offers to buy one of your companies. Original: `R27.bidFor`.
    public static func bidFor(_ s: inout GameState, companyIndex i: Int, groupID: String, price: Double, value v0: Double, context fc: FinanceContext) {
        guard let g = GroupStakes.group(s, id: groupID) else { return }
        let co = s.companies[i], cur = fc.currency(co.countryCode, s)
        let out = 100 - co.ownership
        var body = "\(g["name"].string) offers \(cur.display(price)) for all of \(co.name) (about \(Int(((price / max(1, v0) - 1) * 100).rounded()).magnitude)% \(price >= v0 ? "above" : "below") what it is worth today). "
        if co.ownership < 100 { body += "You own \(Int(co.ownership.rounded()))%, so you would get \(cur.display(price * co.ownership / 100)). " }
        body += out > 50 ? "Outside owners hold \(Int(out.rounded()))%. If the price is good they can accept without you." : out >= 33.4 ? "Outside owners hold \(Int(out.rounded()))% and will want a say." : ""
        s.addMessage(kind: "ask", from: "\(g["owner"].string), \(g["name"].string)", title: "\(g["name"].string) wants to buy \(co.name)", body: body, companyID: co.id, tone: "n", status: "open",
                     options: [.option("Accept", "Sell now for \(cur.display(price * co.ownership / 100)) to you."), .option("Ask for more", "They may raise their offer, or walk away."), .option("Refuse", "Keep it. They may come back, or compete harder.")],
                     action: bidAction, data: .object(["co": .number(Double(co.id)), "g": .string(groupID), "price": .number(price), "V0": .number(v0), "round": 0]), expiresWeek: s.week + 3)
    }

    /// The other owners decide when they hold more than half. Original: `outsideVote`.
    static func outsideVote(_ s: inout GameState, companyID: Int, groupID: String, price: Double, v0: Double, data: GameData, context fc: FinanceContext) {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open, let g = GroupStakes.group(s, id: groupID) else { return }
        let co = s.companies[i], out = 100 - co.ownership
        if out <= 50 { return }
        let need = 1.12
        guard price >= v0 * need else { return }
        let mine = price * co.ownership / 100
        if sellToGroup(&s, companyIndex: i, groupID: groupID, price: price, data: data, context: fc) {
            s.addMessage(from: "Shareholders of \(co.name)", title: "Outvoted: \(co.name) is sold to \(g["name"].string)",
                         body: "The other owners hold \(Int(out.rounded()))% and accepted \(fc.currency(co.countryCode, s).display(price)). Your \(Int(co.ownership.rounded()))% was paid out: \(fc.currency(co.countryCode, s).display(mine)).", companyID: co.id, tone: "bad")
        }
    }

    /// Your answer to a group's bid. Original: `ACTS.g27bid`.
    public static func answerBid(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context fc: FinanceContext) {
        let d = m.value("data")
        guard let i = s.companyIndex(d["co"].int), s.companies[i].status == .open, let g = GroupStakes.group(s, id: d["g"].string) else { return }
        let id = d["g"].string, price = d["price"].double, v0 = d["V0"].double, cid = d["co"].int
        if idx == 0 { sellToGroup(&s, companyIndex: i, groupID: id, price: price, data: data, context: fc); return }
        if d["fin"].bool { outsideVote(&s, companyID: cid, groupID: id, price: price, v0: v0, data: data, context: fc); return }
        if idx == 1 {
            let p2 = (price * 1.15 / 1000).rounded() * 1000
            let yes = d["round"].int < 1 && s.random.chance(g["strat"].string == "acq" ? 0.6 : g["cash"].double > p2 ? 0.45 : 0.25)
            if yes {
                let co = s.companies[i], cur = fc.currency(co.countryCode, s)
                s.addMessage(kind: "ask", from: "\(g["owner"].string), \(g["name"].string)", title: "Final offer for \(co.name)", body: "\(g["name"].string) raises its bid to \(cur.display(p2)). \"This is as far as we go.\"",
                             companyID: co.id, tone: "n", status: "open",
                             options: [.option("Accept", "\(cur.display(p2 * co.ownership / 100)) to you."), .option("Refuse", "They walk away.")], action: bidAction,
                             data: .object(["co": .number(Double(cid)), "g": .string(id), "price": .number(p2), "V0": .number(v0), "round": 1, "fin": 1]), expiresWeek: s.week + 2)
            } else {
                s.note("\(g["name"].string) would not pay more for \(s.companies[i].name) and walked away.", tone: "n", companyID: cid)
                outsideVote(&s, companyID: cid, groupID: id, price: price, v0: v0, data: data, context: fc)
            }
            return
        }
        outsideVote(&s, companyID: cid, groupID: id, price: price, v0: v0, data: data, context: fc)
    }

    // MARK: Stakes in other groups

    public struct Stake: Identifiable, Equatable {
        public var id: Int
        public var groupID: String, name: String
        public var ownership: Double, cost: Double, value: Double
        public var sinceWeek: Int
    }
    public static func stakes(_ s: GameState) -> [Stake] {
        (s.rest["st27"]?.array ?? []).enumerated().map { n, st in
            let g = GroupStakes.group(s, id: st["g"].string)
            return Stake(id: n, groupID: st["g"].string, name: g?["name"].string ?? "A group", ownership: st["pct"].double, cost: st["cost"].double,
                         value: g.map { GroupStakes.value(of: $0, s) * st["pct"].double } ?? 0, sinceWeek: st["w"].int)
        }
    }

    public enum BuyStakeResult: Equatable { case bought(Double), outbid, couldNotPay(Double), noGroup }

    /// Buy part of a group in an auction. `fraction` of the group's value at `multiplier` times fair value; you win with probability `chance`. Original: `buyStake`.
    @discardableResult
    public static func buyStake(_ s: inout GameState, groupID: String, fraction: Double, multiplier: Double, chance: Double, context fc: FinanceContext) -> BuyStakeResult {
        guard let g = GroupStakes.group(s, id: groupID) else { return .noGroup }
        let price = (GroupStakes.value(of: g, s) * fraction * multiplier / 1000).rounded() * 1000
        if !s.random.chance(chance) { s.note("Another bidder won the stake in \(g["name"].string).", tone: "n"); return .outbid }
        if Payments.liquid(s) < price { s.note("You could not raise \(Int(price)) in time.", tone: "bad"); return .couldNotPay(price) }
        Payments.transferFromSavings(&s, need: price)
        Payments.playerPays(&s, price, label: "Stake in \(g["name"].string)")
        s.rest["st27"] = .array((s.rest["st27"]?.array ?? []) + [.object(["g": .string(groupID), "pct": .number(fraction), "cost": .number(price), "w": .number(Double(s.week))])])
        s.note("You now own \(Int((fraction * 100).rounded()))% of \(g["name"].string).", tone: "good")
        return .bought(price)
    }
}
