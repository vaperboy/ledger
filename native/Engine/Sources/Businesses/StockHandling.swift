import Foundation
import GameCore

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
}
