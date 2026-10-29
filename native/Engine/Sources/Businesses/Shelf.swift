import Foundation
import GameCore

/// Shelf stock with deliveries. Goods businesses sell from a shelf that is refilled on delivery days; when the shelf
/// is empty, sales are lost. Original: features/company/shelf_stock_chains_boards.js (`R12DELIV`).
public enum Shelf {
    /// Days between deliveries: perishables and fast sellers daily, others twice a week or weekly.
    static func deliveryEvery(_ bd: Trade) -> Double {
        let st = bd.trait("stock") ?? 0
        return (st == 0 || st <= 2 || bd.hasTrait("perish")) ? 1 : st <= 14 ? 3.5 : 7
    }
    static func isDeliveryDay(_ bd: Trade, weekday wd: Int) -> Bool {
        let e = deliveryEvery(bd)
        return e == 1 || (e == 3.5 ? (wd == 0 || wd == 3) : wd == 0)
    }
    static func daysUntilNextDelivery(_ bd: Trade, weekday wd: Int) -> Int {
        let e = deliveryEvery(bd)
        if e == 1 { return 1 }
        if e == 3.5 { return wd < 3 ? 3 - wd : 7 - wd }
        let g = 7 - wd
        return g == 0 ? 7 : g
    }

    /// Order the shelf for the days until the next delivery. Returns the value of spoiled stock to write off.
    @discardableResult
    static func deliver(_ co: inout Company, _ bd: Trade, weekday wd: Int, demand D: Double, ticket: Double, mgrQuality: Double,
                        random r: inout DeterministicRandom) -> Double {
        guard DailyTrade.kind(bd) == .goods else { return 0 }
        if !co.value("shelf").isNull && !isDeliveryDay(bd, weekday: wd) { return 0 }
        let gap = daysUntilNextDelivery(bd, weekday: wd)
        let sh = DailyTrade.shape(bd)
        var share = 0.0
        for i in 0..<gap { share += sh[(wd + i) % 7] }
        let byManager = co.managerID != nil
        let weekly: Double
        if !byManager {
            // You order from last week: what sold, plus some of what you could not sell.
            let last = co.value("dlast")
            weekly = (!last.isNull && last["u"].double != 0) ? last["u"].double + 0.6 * last["lost"].double : D
        } else {
            weekly = D * max(0.5, 1 + r.gauss() * (1 - mgrQuality) * 0.25)
        }
        let expect = weekly * share
        let pol = co.value("stockPol").isNull ? 1 : co.int("stockPol")
        let cover = [1.0, 1.2, 1.5].indices.contains(pol) ? [1.0, 1.2, 1.5][pol] : 1.2
        let target = (expect * cover + (byManager ? max(0, expect).squareRoot() * 0.6 * mgrQuality : 0)).rounded(.up)
        var writeOff = 0.0
        if bd.hasTrait("perish") && !co.value("shelf").isNull {
            let spare = max(0, co.num("shelf") - 0.35 * co.num("lastExp"))
            let unitCost = ticket * (bd.costOfSales == 0 ? 0.3 : bd.costOfSales)
            if spare > 0 && unitCost > 0 { writeOff = spare * unitCost * 0.25 }
            co.set("shelf", 0)
        }
        co.set("shelf", max(co.num("shelf"), target))
        co.set("lastExp", expect)
        return writeOff
    }
}
