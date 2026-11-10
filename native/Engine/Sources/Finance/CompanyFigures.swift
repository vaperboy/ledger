import Foundation
import GameCore
import Countries
import Employees

public enum CompanyFigures {
    public static func equipmentBookValue(_ co: Company) -> Double {
        var t = 0.0
        for (_, e) in co.value("eq").object.sorted(by: { $0.key < $1.key }) { t += e["bv"].double }
        for v in co.value("veh").array { t += v["bv"].double }
        return t
    }

    static func propertyValue(_ co: Company) -> Double {
        co.value("props").array.reduce(0) { $0 + $1["val"].double }
    }

    public static func assets(_ co: Company) -> Double {
        let prem = co.value("prem")
        let owned = prem["owned"].bool ? prem["val"].double : 0
        let fm = co.value("fm")
        return co.cash
            + co.receivables.reduce(0) { $0 + $1.amount }
            + max(0, -co.vatBalance)
            + co.inventory
            + prem["dep"].double
            + equipmentBookValue(co)
            + owned
            + propertyValue(co)
            + co.num("luxBV")
            + (fm["assets"].isNull ? 0 : fm["assets"].double)
    }

    public static func fixedAssets(_ co: Company) -> Double {
        let prem = co.value("prem")
        return equipmentBookValue(co) + (prem["owned"].bool ? prem["val"].double : 0) + propertyValue(co) + co.inventory + co.num("luxBV")
    }

    public static func debts(_ co: Company, loans: [Loan]) -> Double {
        let loanSum = loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
        return loanSum + billsOwed(co)
    }

    public static func billsOwed(_ co: Company) -> Double {
        let p = co.payables
        let fm = co.value("fm")
        var total: Double = p["wages"] ?? 0
        total += p["other"] ?? 0
        total += p["inv"] ?? 0
        total += p["rent"] ?? 0
        total += max(0, co.vatBalance)
        total += p["tax"] ?? 0
        total += p["legal"] ?? 0
        total += p["warr"] ?? 0
        if !fm["liab"].isNull { total += fm["liab"].double }
        return total
    }

    public static func yearlyProfitEstimate(_ co: Company, currentWeek: Int) -> Double {
        let h = Array(co.monthlyHistory.suffix(12))
        if h.count < 3 {
            let y = co.books.year
            guard let rev = y["rev"], rev != 0 else { return 0 }
            return (rev - Books.expenses(y)) * (52 / max(4, Double(currentWeek - co.foundedWeek + 1)))
        }
        return h.reduce(0) { $0 + $1.profit } * (12 / Double(h.count))
    }

    public static func weeklyCostEstimate(_ co: Company, fixedCost: Double, country: Country) -> Double {
        let payroll = Payroll.weeklyCost(co, country: country)
        let prem = co.value("prem")
        let rent = (!prem.isNull && !prem["owned"].bool && prem["m2"].double > 0) ? prem["rent"].double * prem["m2"].double / 52 : 0
        let marketing = co.value("mkt").object.sorted(by: { $0.key < $1.key }).reduce(0) { $0 + $1.value["b"].double }
        return payroll + rent + fixedCost * pow(co.size, 0.6) + marketing + co.value("lastW")["cogs"].double * 0.5
    }

    public static func weeksOfCash(cash: Double, weeklyCost: Double) -> Double { weeklyCost > 0 ? max(0, cash) / weeklyCost : 0 }
    public static func runwayWeeks(cash: Double, weeklyLoss: Double) -> Double? { weeklyLoss > 0 ? max(0, cash) / weeklyLoss : nil }

    public static func overdraftRoom(weeklyCost: Double) -> Double { max(0, weeklyCost * 3) }
}
