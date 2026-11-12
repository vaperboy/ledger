import Foundation
import GameCore

public enum Taxes {
    public static func bracketTax(_ income: Double, brackets: [(from: Double, rate: Double)]) -> Double {
        var t = 0.0
        for i in brackets.indices {
            let lo = brackets[i].from
            let hi = i + 1 < brackets.count ? brackets[i + 1].from : Double.infinity
            if income > lo { t += (min(income, hi) - lo) * brackets[i].rate }
        }
        return t
    }

    public static func personalIncomeTax(_ income: Double, in c: Country) -> Double {
        let I = c.income
        let inc = max(0, income)
        let rate = c.employeeSocial
        let deduction: Double
        if let wd = I.wageDeduction { deduction = min(wd.maximum, inc * wd.share) } else { deduction = 0 }
        let flat = I.flat != 0 ? max(0, inc - deduction - I.allowance) * I.flat : 0
        let social: Double
        if I.socialCapShare != 0 {
            social = inc > I.socialFloor ? min(inc * rate, (inc - I.socialFloor) * I.socialCapShare) : 0
        } else {
            social = inc * rate
        }
        return flat + bracketTax(inc, brackets: I.brackets) + social
    }

    public static func wealthTax(netWorth: Double, in c: Country) -> Double {
        max(0, netWorth - c.wealthThreshold) * c.wealthRate
    }

    public static func dividendTax(_ dividends: Double, shield: Double, in c: Country) -> Double {
        max(0, dividends - max(0, shield)) * c.dividendTax
    }

    public static func capitalGainsTax(_ gains: Double, in c: Country) -> Double { max(0, gains) * c.capitalGainsTax }

    public static func savingsInterestTax(_ interest: Double, in c: Country) -> Double { max(0, interest) * c.savingsInterestTax }

    public static func lossOffsetLimit(profit: Double, in c: Country) -> Double {
        let p = max(0, profit)
        return min(p, c.lossFree) + c.lossShare * max(0, p - c.lossFree)
    }

    public static func specialRate(_ kind: String, in c: Country, fallback: Double) -> Double {
        c.specialTax[kind] ?? fallback
    }
}
