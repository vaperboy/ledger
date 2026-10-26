import Foundation
import GameCore

/// Accounting figures of a company, computed from its saved state. Originals in engine/money/money.js.
///
/// Definitions (so the numbers never contradict each other):
///  - assets    = cash + customers' unpaid invoices + VAT refund due + stock + lease deposit + equipment & vehicles
///                at book value + owned premises + owned property + financial-company assets
///  - debts     = loans of the company + unpaid wages, bills, supplier invoices, rent, tax + VAT owed + financial-company liabilities
///  - equity    = assets - debts
public enum CompanyFigures {
    /// Equipment and vehicles at book value. Original: `eqBook`.
    public static func equipmentBookValue(_ co: Company) -> Double {
        var t = 0.0
        for (_, e) in co.value("eq").object.sorted(by: { $0.key < $1.key }) { t += e["bv"].double }
        for v in co.value("veh").array { t += v["bv"].double }
        return t
    }

    static func propertyValue(_ co: Company) -> Double {
        co.value("props").array.reduce(0) { $0 + $1["val"].double }
    }

    /// Everything the company owns. Original: `companyAssets`.
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

    /// Fixed assets that are not cash: used for lending limits. Original: `coAssets`.
    public static func fixedAssets(_ co: Company) -> Double {
        let prem = co.value("prem")
        return equipmentBookValue(co) + (prem["owned"].bool ? prem["val"].double : 0) + propertyValue(co) + co.inventory + co.num("luxBV")
    }

    /// Everything the company owes. Original: `companyDebts`.
    public static func debts(_ co: Company, loans: [Loan]) -> Double {
        let p = co.payables
        let loanSum = loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
        let fm = co.value("fm")
        return loanSum + (p["wages"] ?? 0) + (p["other"] ?? 0) + (p["inv"] ?? 0) + (p["rent"] ?? 0) + max(0, co.vatBalance) + (p["tax"] ?? 0)
            + (fm["liab"].isNull ? 0 : fm["liab"].double)
    }

    /// Profit over the last twelve months, scaled to a year. Original: `coEbit12`.
    public static func yearlyProfitEstimate(_ co: Company, currentWeek: Int) -> Double {
        let h = Array(co.monthlyHistory.suffix(12))
        if h.count < 3 {
            let y = co.books.year
            guard let rev = y["rev"], rev != 0 else { return 0 }
            return (rev - Books.expenses(y)) * (52 / max(4, Double(currentWeek - co.foundedWeek + 1)))
        }
        return h.reduce(0) { $0 + $1.profit } * (12 / Double(h.count))
    }

    /// What the company spends in a typical week; sets its overdraft room. Original: `coWeekCost`.
    public static func weeklyCostEstimate(_ co: Company, fixedCost: Double, employerFactor: Double) -> Double {
        let staffPay = co.staff.reduce(0) { $0 + $1.monthlyWage } * 12 / 52 * employerFactor
        let mgr = co.managerMonthlyWage * 12 / 52 * employerFactor
        let prem = co.value("prem")
        let rent = (!prem.isNull && !prem["owned"].bool && prem["m2"].double > 0) ? prem["rent"].double * prem["m2"].double / 52 : 0
        let marketing = co.value("mkt").object.sorted(by: { $0.key < $1.key }).reduce(0) { $0 + $1.value["b"].double }
        return staffPay + mgr + rent + fixedCost * pow(co.size, 0.6) + marketing + co.value("lastW")["cogs"].double * 0.5
    }

    /// How far below zero a company's account may go. Original: `coOverdraft`.
    public static func overdraftRoom(weeklyCost: Double) -> Double { max(0, weeklyCost * 3) }
}
