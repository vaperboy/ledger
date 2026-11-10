import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum RivalBids {
    public static let action = "g27bid"

    @discardableResult
    static func sell(_ s: inout GameState, companyID: Int, groupID: String, price: Double, data: GameData, context fc: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return false }
        let co = s.companies[i]
        let gname = s.rest["g27"]?["g"][groupID]["name"].string ?? "A rival group"
        guard CompanySale.complete(&s, companyIndex: i, buyer: gname, price: price, data: data, context: fc) != nil else { return false }
        CompanySale.withdraw(&s, companyID: companyID)
        RivalGroups.completeSale(&s, groupID: groupID, company: co, price: price, data: data)
        return true
    }

    static func outsideVote(_ s: inout GameState, companyID: Int, groupID: String, price: Double, value v0: Double, data: GameData, context fc: FinanceContext) {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open else { return }
        let co = s.companies[i]
        let out = 100 - co.ownership
        guard out > 50 else { return }
        let need = 1.12
        guard price >= v0 * need else { return }
        let cur = fc.homeCurrency(s)
        if sell(&s, companyID: companyID, groupID: groupID, price: price, data: data, context: fc) {
            s.addMessage(from: "Shareholders of \(co.name)", title: "Outvoted: \(co.name) is sold to \(s.rest["g27"]?["g"][groupID]["name"].string ?? "a group")",
                         body: "The other owners hold \(Int(saturating: jsRound(out)))% and accepted \(cur.display(price)). Your \(Int(saturating: jsRound(co.ownership)))% was paid out: \(cur.display(price * co.ownership / 100)).",
                         companyID: co.id, tone: "bad")
        }
    }

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context fc: FinanceContext) {
        let d = m.value("data")
        let cid = d["co"].int, gid = d["g"].string
        guard let i = s.companyIndex(cid), s.companies[i].status == .open, let g = s.rest["g27"]?["g"][gid], !g.isNull else { return }
        let co = s.companies[i]
        let price = d["price"].double, v0 = d["V0"].double
        if idx == 0 { sell(&s, companyID: cid, groupID: gid, price: price, data: data, context: fc); return }
        if d["fin"].bool { outsideVote(&s, companyID: cid, groupID: gid, price: price, value: v0, data: data, context: fc); return }
        if idx == 1 {
            let p2 = ((price * 1.15) / 1000).rounded() * 1000
            let yes = d["round"].int < 1 && s.random.chance(g["strat"].string == "acq" ? 0.6 : g["cash"].double > p2 ? 0.45 : 0.25)
            if yes {
                let cur = World(state: s, data: data).currency(co)
                var nd = d; nd["price"] = .number(p2); nd["round"] = 1; nd["fin"] = true
                s.addMessage(kind: "ask", from: "\(g["owner"].string), \(g["name"].string)", title: "Final offer for \(co.name)",
                             body: "\(g["name"].string) raises its bid to \(cur.display(p2)). \"This is as far as we go.\"", companyID: co.id, tone: "n", status: "open",
                             options: [.option("Accept", "\(cur.display(p2 * co.ownership / 100)) to you."), .option("Refuse", "They walk away.")],
                             action: action, data: nd, expiresWeek: s.week + 2)
            } else {
                s.note("\(g["name"].string) would not pay more for \(co.name) and walked away.", tone: "n", companyID: co.id)
                outsideVote(&s, companyID: cid, groupID: gid, price: price, value: v0, data: data, context: fc)
            }
            return
        }
        outsideVote(&s, companyID: cid, groupID: gid, price: price, value: v0, data: data, context: fc)
    }

    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for k in s.inbox.indices {
            let m = s.inbox[k]
            guard m.int("auto") != 0, !m.flag("done27") else { continue }
            if m.actionID == "g27poach" {
                s.inbox[k].set("done27", true)
                let d = m.value("data")
                if let ci = s.companyIndex(d["co"].int), s.companies[ci].managerID == d["n"].int { RivalGroups.poachGo(&s, ci, groupID: d["g"].string) }
            } else if m.actionID == action {
                s.inbox[k].set("done27", true)
                let d = m.value("data")
                outsideVote(&s, companyID: d["co"].int, groupID: d["g"].string, price: d["price"].double, value: d["V0"].double, data: data, context: fc)
            }
        }
    }
}
