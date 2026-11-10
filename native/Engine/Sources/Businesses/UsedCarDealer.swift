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

public struct UsedCarStockItem: Sendable, Identifiable, Equatable {
    public var id: Int
    public var kind: String
    public var title: String
    public var family: String
    public var purchasePrice: Double
    public var repairs: Double
    public var askingPrice: Double
    public var weeksInStock: Int
    public var inspected: Bool
    public var status = "ready"
    public var reserved = false
    public var reservedPrice = 0.0
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
    public var costBasis: Double { purchasePrice + repairs + holdingSoFar }
}

public enum UsedCarDealer {
    public static let tradeID = "usedcar"
    public static let defaultMarkup = 12.0
    public static let staleAfter = 8
    static let holding = 0.0008
    static let depreciation = 0.003

    public static func markup(_ co: Company) -> Double { co.value("ucm").isNull ? defaultMarkup : co.value("ucm").double }

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

    public static func setMarkup(_ s: inout GameState, companyID: Int, percent: Double) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID, percent.isFinite, percent >= -50, percent <= 300 else { return false }
        s.companies[i].set("ucm", percent)
        return true
    }
}
