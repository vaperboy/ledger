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

/// What the payroll costs. The one place that adds up a company's standing pay for a week: the weekly accrual (`CompanyCosts.wages`), the estimates
/// of the cash due, the weekly cost behind runway and overdraft room and the event formulas all read it, so they cannot drift apart.
public enum Payroll {
    /// One week of standing payroll with the employer's on-cost: staff pay with cover for paid leave and sick days (those laid off for the season
    /// left out unless asked), plus the manager. Each wage carries its own on-cost rate (`Country.payrollFactor`), which matters where
    /// contributions are capped. Commission and bonuses are not included.
    /// With `sickWeek` (the accrual), someone who fell sick last week costs what the country's sick-pay law makes the employer pay
    /// (`LabourRules.employerSickPay`) instead of the full wage; estimates leave it out. `capScale` carries the price drift of a flat statutory rate.
    public static func weeklyCost(_ co: Company, country: Country, skipOffSeason: Bool = true, sickWeek: Int? = nil, capScale: Double = 1) -> Double {
        let labour = LabourRules(country: country)
        let holiday = 1 + labour.leaveWeeks / 52 * 0.3   // cover for paid leave (sick pay is by law, below)
        var cost = 0.0
        for m in co.staff where !(skipOffSeason && m.isOffSeason) {
            let weekly = m.monthlyWage * 12 / 52
            let pay = (sickWeek != nil && m.sickUntilWeek == sickWeek)
                ? labour.employerSickPay(weeklyWage: weekly, rate: country.fx, capScale: capScale) : weekly * holiday
            cost += pay * country.payrollFactor(monthlyWage: m.monthlyWage)
        }
        if co.managerID != nil { cost += co.managerMonthlyWage * 12 / 52 * country.payrollFactor(monthlyWage: co.managerMonthlyWage) }
        return cost
    }
}
