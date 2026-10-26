import Foundation
import GameCore

/// Taxes that depend only on a country's rules. Money is in accounting units, per year unless stated.
public enum Taxes {
    public enum IncomeKind { case selfEmployed, wage }

    /// Tax in income brackets. Original: `bracketTax`.
    public static func bracketTax(_ income: Double, brackets: [(from: Double, rate: Double)]) -> Double {
        var t = 0.0
        for i in brackets.indices {
            let lo = brackets[i].from
            let hi = i + 1 < brackets.count ? brackets[i + 1].from : Double.infinity
            if income > lo { t += (min(income, hi) - lo) * brackets[i].rate }
        }
        return t
    }

    /// Annual personal income tax including social contributions. Original: `personalTax(inc, kind)`.
    public static func personalIncomeTax(_ income: Double, kind: IncomeKind, in c: Country) -> Double {
        let I = c.income
        let inc = max(0, income)
        let rate = kind == .wage ? c.employeeSocial : c.selfEmployedSocial
        let deduction: Double
        if kind == .wage, let wd = I.wageDeduction { deduction = min(wd.maximum, inc * wd.share) } else { deduction = 0 }
        let flat = I.flat != 0 ? max(0, inc - deduction - I.allowance) * I.flat : 0
        let social: Double
        if I.socialCapShare != 0 {
            social = inc > I.socialFloor ? min(inc * rate, (inc - I.socialFloor) * I.socialCapShare) : 0
        } else {
            social = inc * rate
        }
        return flat + bracketTax(inc, brackets: I.brackets) + social
    }

    /// Original: `wealthTax`.
    public static func wealthTax(netWorth: Double, in c: Country) -> Double {
        max(0, netWorth - c.wealthThreshold) * c.wealthRate
    }

    /// Tax on dividends after the tax-free shield. Original: `dividendTax`.
    public static func dividendTax(_ dividends: Double, shield: Double, in c: Country) -> Double {
        max(0, dividends - max(0, shield)) * c.dividendTax
    }

    /// Tax on realised capital gains of a private investor (`tax.capitalGains`).
    public static func capitalGainsTax(_ gains: Double, in c: Country) -> Double { max(0, gains) * c.capitalGainsTax }

    /// Tax on savings and deposit interest (`tax.savingsInterest`).
    public static func savingsInterestTax(_ interest: Double, in c: Country) -> Double { max(0, interest) * c.savingsInterestTax }

    /// The most of a year's profit that carried-forward losses may offset: `free` plus `share` of the profit above it
    /// (Germany 1M + 60%, France 1M + 50%, the US 80%); the whole profit where the country has no cap.
    public static func lossOffsetLimit(profit: Double, in c: Country) -> Double {
        let p = max(0, profit)
        return min(p, c.lossFree) + c.lossShare * max(0, p - c.lossFree)
    }

    /// Special industry rates (oil, salmon, hydro) fall back to the given default. Original: `specialTax`.
    public static func specialRate(_ kind: String, in c: Country, fallback: Double) -> Double {
        c.specialTax[kind] ?? fallback
    }
}
