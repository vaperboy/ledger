import Foundation
import GameCore
import Finance

/// Stock for shops and producers: when demand jumps above what the shelves hold, sales are lost until the next
/// delivery. Original: `stockUnits`, `stockHandle` (engine/company/family_basic.js).
public enum StockHandling {
    /// Units that can really be sold given stock policy and cover. Original: `stockUnits`.
    public static func unitsAvailable(_ co: Company, _ bd: Trade, demand D: Double, capacity cap: Double, units u0: Double, w: World) -> Double {
        guard let stockWeeks = bd.trait("stock"), stockWeeks != 0 else { return u0 }
        let pol = co.int("stockPol", 1)
        let hi = D > cap * 0.9 ? 1.0 : 0.4
        let q = ManagerModel.quality(co, bd, people: w.state.people)
        let so = [0.05, 0.012, 0.002][min(2, max(0, pol))] * hi * (co.managerID != nil ? 1.2 - q * 0.8 : 1)
        var u = u0 * (1 - so * 0.5)
        let lw = co.value("lastW")
        if lw["cogs"].double > 0 && lw["units"].double > 0 {
            let needNow = lw["cogs"].double * (stockWeeks / 7) * 0.5 * (u / lw["units"].double)
            if needNow > 0 && co.inventory < needNow {
                let f = clamp(co.inventory / needNow, 0.25, 1)
                u *= f
            }
        }
        return u
    }

    /// Weeks-of-cover multiplier per stock policy: lean, normal, generous (the policy the owner or chain sets as `stockPol`).
    static let policyCover: [Double] = [0.75, 1, 1.4]

    /// The stock the company's policy wants on the shelves: a week's cost of sales for the trade's cover days, scaled by the policy. Nil for a trade that holds no stock.
    public static func policyTarget(_ co: Company, _ bd: Trade) -> Double? {
        guard let stockWeeks = bd.trait("stock"), stockWeeks != 0 else { return nil }
        let cogs = co.value("lastW")["cogs"].double
        guard cogs > 0 else { return nil }
        return cogs * stockWeeks / 7 * policyCover[min(2, max(0, co.int("stockPol", 1)))]
    }

    /// A manager tops up shelves that have fallen well below the policy, in an order no bigger than their budget (a cautious one uses less of it) and
    /// never so large that the next weeks' bills are at risk. Returns what was ordered, nil when nothing was.
    static func managerOrder(_ s: inout GameState, _ ci: Int, _ bd: Trade, manager n: Person, data: GameData) -> Double? {
        let co = s.companies[ci]
        guard co.status == .open, co.int("supCut") == 0, ManagerModel.budget(of: co).actsAlone, let target = policyTarget(co, bd), co.inventory < target * 0.6 else { return nil }
        let limit = ManagerModel.spendLimit(of: co, s, data: data) * ManagerVoice.budgetUse(n)
        let room = co.cash - ManagerModel.weekCost(s, co, data: data) * 3
        let amount = jsRound(min(target * 0.9 - co.inventory, limit, room))
        guard amount > 0 else { return nil }
        s.companies[ci].inventory += amount
        AccountingLedger.note(category: "cogs", label: "Stock and supplier purchases", ref: Suppliers.goodsVendor(s, company: co, data: data).map { "supplier:\($0.id)" } ?? "")
        Ledger.moveRaw(&s, .company(co.id), -amount)
        return amount
    }
}
