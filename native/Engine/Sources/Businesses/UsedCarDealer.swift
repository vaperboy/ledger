import Foundation
import GameCore
import Countries
import Finance

extension JSONValue {
    mutating func removeKey(_ k: String) {
        guard case .object(var o) = self else { return }
        o.removeValue(forKey: k)
        self = .object(o)
    }
}

/// One car or van in a used car dealer's yard, as the player sees it. The hidden condition is not here: the mechanic finds it in the
/// first week (`inspected`), and the repair bill is added to `repairs`.
public struct UsedCarStockItem: Sendable, Identifiable, Equatable {
    public var id: Int
    public var kind: String          // always "usedcar"
    public var title: String
    public var family: String
    public var purchasePrice: Double
    public var repairs: Double
    public var askingPrice: Double
    public var weeksInStock: Int
    public var inspected: Bool
    /// "new" (just arrived, not looked at yet), "quoted" (the repair quote is in, waiting for your decision), "repair" (at the garage), "ready".
    public var status = "ready"
    /// A customer has reserved this car for when it is fixed (it is sold on finish at the reserved price).
    public var reserved = false
    public var reservedPrice = 0.0
    /// What the repair costs: the quote while waiting, the order while at the garage, zero when there is none.
    public var repairQuote = 0.0
    public var repairWeeksLeft = 0
    public var repairDueWeek = 0
    public var repairSupplierID = 0
    public var repairSupplierName = ""
    public var fairValue = 0.0
    public var holdingSoFar = 0.0
    public var weeklyHolding = 0.0
    public var stuck = false
    public var soldAsIs = false
    /// Everything this car has cost so far: price, repairs paid and the holding cost to date.
    public var costBasis: Double { purchasePrice + repairs + holdingSoFar }
}

/// The used car dealer (trade `usedcar`). Nothing arrives on its own: the player (or a manager) buys cars on the Marketplace (`Marketplace.buy`
/// puts them here), the mechanic inspects each one and repairs what is worn, and customers buy from the yard.
/// Stock sits on the balance sheet as inventory at cost (purchase price plus repairs); a sale books the price as revenue and that cost as cost
/// of sales. Weekly shoppers come from the ordinary demand model (reputation, marketing, season, rivals, economy); each looks at up to three
/// cars and buys the best value with a probability that falls as the asking price rises above the car's fair market value. The asking price
/// is the car's own price (`setUsedCarPrice`), or cost plus the dealer's markup percentage (`setUsedCarMarkup`) for a car without one.
/// See `UsedCarYard.swift` (lot spaces, repair orders, reservations, stuck cars, forced sales, buyers, price quotes).
/// The dealer's stock is `stk` on the company; the markup is `ucm` (percent). Per car (keys only when set): `ask` own price, `rq` repair quote, `job`
/// {due, sup, sn, price} repair order, `res` reserved price, `fx` repaired (or nothing to repair), `skip` sold as it is, `hold` holding cost to date.
public enum UsedCarDealer {
    public static let tradeID = "usedcar"
    public static let defaultMarkup = 12.0
    /// A car that has sat this many weeks counts as stuck: it loses value faster and sells slower.
    public static let staleAfter = 8
    /// Weekly cost of holding stock (storage, insurance, cleaning), share of its value.
    static let holding = 0.0008
    /// Weekly fall in a car's market value.
    static let depreciation = 0.003

    public static func markup(_ co: Company) -> Double { co.value("ucm").isNull ? defaultMarkup : co.value("ucm").double }

    /// The asking price of one car: its own price when the dealer set one, else cost plus the dealer's markup.
    static func ask(_ c: JSONValue, markup m: Double) -> Double { c["ask"].isNull ? (c["cost"].double + c["rep"].double) * (1 + m / 100) : c["ask"].double }

    public static func stock(_ co: Company) -> [UsedCarStockItem] { stockItems(co, week: 0) }

    public static func stockItems(_ co: Company, week: Int) -> [UsedCarStockItem] {
        let m = markup(co)
        return co.value("stk").array.map { c in
            let job = c["job"], fixed = c["fx"].bool
            let status = !job.isNull ? "repair" : !c["done"].bool ? "new" : (!fixed && c["rq"].double > 0 && !c["skip"].bool) ? "quoted" : "ready"
            let age = max(0, week - c["wk"].int)
            var it = UsedCarStockItem(id: c["id"].int, kind: "usedcar", title: c["name"].string, family: c["fam"].string, purchasePrice: c["cost"].double, repairs: c["rep"].double,
                                      askingPrice: ask(c, markup: m), weeksInStock: age, inspected: c["done"].bool)
            it.status = status
            it.reserved = !c["res"].isNull
            it.reservedPrice = c["res"].double
            it.repairQuote = !job.isNull ? job["price"].double : (fixed || c["skip"].bool ? 0 : c["rq"].double)
            it.repairDueWeek = job["due"].int
            it.repairWeeksLeft = job.isNull ? 0 : max(0, job["due"].int - week)
            it.repairSupplierID = job["sup"].int
            it.repairSupplierName = job["sn"].string
            it.fairValue = c["fair"].double
            it.holdingSoFar = c["hold"].double
            it.weeklyHolding = (c["cost"].double + c["rep"].double) * holding
            it.stuck = age >= staleAfter
            it.soldAsIs = c["skip"].bool && !fixed
            return it
        }
    }

    /// Set the markup on cost, in percent (the dealer's own price for used cars).
    public static func setMarkup(_ s: inout GameState, companyID: Int, percent: Double) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID, percent.isFinite, percent >= -50, percent <= 300 else { return false }
        s.companies[i].set("ucm", percent)
        return true
    }
}
