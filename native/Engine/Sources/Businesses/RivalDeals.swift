import Foundation
import GameCore
import Countries
import Finance

/// Buying a rival: the owner's reply to an offer, then the purchase itself. The rival becomes a company of yours (a limited company in the
/// same city, set up with the standard choices) with the customers' goodwill; the group behind it, if any, gets the money, and a rival that
/// was in trouble can hide bills. Original: `proposeBuy`, `acquireRival` (engine/world/rivals.js) and the group steps in rival_groups.js
/// ('proposeBuy.terms', 'acquireRival.before', 'acquireRival.after'). Not ported: buying a rival abroad, branches and franchise units.
extension Rivals {
    public enum AcquireResult: Equatable { case ok(companyID: Int), notEnoughCash, failed(String) }

    /// What buying costs besides the price: the new company's own start-up money. Original: `setupEstimate(...).total * 1.15`.
    public static func startupMoney(_ s: GameState, _ co: Company, rival r: Rival, data: GameData) -> Double {
        guard let bd = data.catalog[co.type] else { return 0 }
        let size = clamp(r.size * 0.8, bd.minSize, bd.maxSize)
        return jsRound((CompanySetup.estimate(tradeID: co.type, cityID: co.cityID, form: .limited, size: size, countryCode: co.countryCode, state: s, data: data)?.total ?? 0) * 1.15)
    }

    public static func acquire(_ s: inout GameState, companyID: Int, rivalID: Int, price: Double, data: GameData, context: FinanceContext) -> AcquireResult {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], let r = rivals(s, for: co).first(where: { $0.id == rivalID }) else { return .failed("That rival is gone.") }
        let k = key(co)
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let size = clamp(r.size * 0.8, bd.minSize, bd.maxSize)
        let startup = startupMoney(s, co, rival: r, data: data)
        if Payments.liquid(s) < price + startup + cur.scaledPrice(200000) { return .notEnoughCash }
        let group = RivalGroups.group(s, id: r.groupID)
        let troubled = r.groupID != nil ? (group?.inTrouble ?? false) : (s.rest["mk"]?[k]["riv"].array.first { $0["id"].int == rivalID }?["dist27"].double ?? 0) != 0
        guard case .success(let id) = CompanySetup.create(&s, tradeID: co.type, cityID: co.cityID, form: .limited, size: size, name: r.name, countryCode: co.countryCode, data: data, context: context) else {
            return .failed("The new company could not be set up.")
        }
        Payments.playerPays(&s, price, label: "Acquisition of \(r.name)", companyID: id)
        _ = Payments.injectCash(&s, companyID: id, amount: startup)
        _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        if let i = s.companyIndex(id) {
            s.companies[i].reputation = max(s.companies[i].reputation, 50 + r.size * 6)
            s.companies[i].awareness = max(s.companies[i].awareness, 36 + r.size * 22)
            s.companies[i].set("wom", s.companies[i].num("wom") + 10)
            var f = s.companies[i].value("flags"); f["acq"] = .number(Double(s.week)); s.companies[i].set("flags", f)
            _ = OpeningChecklist.open(&s, companyIndex: i, data: data)
        }
        removeRival(&s, key: k, id: rivalID)
        if let gid = r.groupID, s.rest["g27"]?["g"][gid] != nil {
            var g = s.rest["g27"]!["g"][gid]
            g["cash"] = .number(g["cash"].double + price)
            g["br"] = .number(Double(max(1, g["br"].int - 1)))
            if g["dist"].double != 0 { g["debt"] = .number(max(0, g["debt"].double - price * 0.8)) }
            RivalGroups.logMove(&g, week: s.week, "Sold \(r.name) to you")
            s.rest["g27"]!["g"][gid] = g
        }
        var h = HashedRandom("\(s.seed):hidden:\(s.week):\(rivalID)")
        if troubled, h.next() < 0.35, let i = s.companyIndex(id) {
            let bill = jsRound(price * (0.08 + 0.17 * h.next()))
            s.companies[i].addPayable("other", bill)
            s.addMessage(from: s.companies[i].name, title: "Surprise in the books of \(s.companies[i].name)",
                         body: "Unpaid supplier bills and a tax claim from before you bought it: \(cur.display(bill)). It is yours to pay now.", companyID: id, tone: "bad")
        }
        s.note("You bought \(r.name). Its customers now belong to you.", tone: "good", companyID: id)
        return .ok(companyID: id)
    }
}
