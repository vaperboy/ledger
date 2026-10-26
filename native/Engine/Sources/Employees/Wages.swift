import Foundation
import GameCore
import Countries

/// What a job pays on the labour market. Original: `wageFor` (engine/people/people.js) and the pay-spread step.
public enum Wages {
    /// In lower-wage countries low-paid jobs follow the wage index more steeply than skilled jobs. Original: `R24.paySpread`.
    public static func paySpread(baseMonthlyWage base: Double, country: Country) -> Double {
        let w = country.wageLevel == 0 ? 1 : country.wageLevel
        if w >= 1 { return 1 }
        let e = clamp(1 + (1 - base / 80000), 0.7, 1.6)
        return pow(w, e) / w
    }

    /// Monthly market wage for a role at full time, in accounting units.
    public static func market(baseMonthlyWage base: Double, country: Country, city: Country.City, economy: Economy, rates: ExchangeRates) -> Double {
        let currency = Currency(country: country, rates: rates)
        let raw = roundTo(base * city.wage * economy.inflationIndex * (1 + 0.03 * max(0, economy.demand - 1) * 4), step: 100)
        var v = Currency.nicePrice(raw / currency.rate) * currency.rate
        let f = paySpread(baseMonthlyWage: base, country: country)
        if f != 1 {
            let r2 = roundTo(v * f, step: 100)
            v = Currency.nicePrice(r2 / currency.rate) * currency.rate
        }
        return v
    }
}

/// What the payroll costs. The one place that adds up a company's pay for a week: the weekly accrual (`CompanyCosts.wages`), the estimates of
/// the cash due, the weekly cost behind runway and overdraft room, the event formulas and the team screens all read it, so they cannot drift apart.
public enum Payroll {
    /// Gross pay of one week before commission and bonuses: the staff on the payroll (not those laid off for the season) with cover for paid
    /// leave and sick days added, and the manager.
    public static func weeklyGross(_ co: Company, country: Country) -> Double {
        let cover = 1 + LabourRules(country: country).leaveWeeks / 52 * 0.3
        var gross = co.staff.reduce(0) { $0 + ($1.isOffSeason ? 0 : $1.monthlyWage * 12 / 52 * cover) }
        if co.managerID != nil { gross += co.managerMonthlyWage * 12 / 52 }
        return gross
    }

    /// The same for a month.
    public static func monthlyGross(_ co: Company, country: Country) -> Double { weeklyGross(co, country: country) * 52 / 12 }

    /// A week of payroll with the employer's charges.
    public static func weeklyCost(_ co: Company, country: Country) -> Double { weeklyGross(co, country: country) * country.employerCostFactor }
}
