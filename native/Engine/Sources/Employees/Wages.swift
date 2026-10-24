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
    public static func market(baseMonthlyWage base: Double, country: Country, city: Country.City, economy: Economy, week: Int, rates: ExchangeRates) -> Double {
        let currency = Currency(country: country, rates: rates)
        let raw = roundTo(base * city.wage * pow(1 + economy.inflation, Double(week) / 52) * (1 + 0.03 * max(0, economy.demand - 1) * 4), step: 100)
        var v = Currency.nicePrice(raw / currency.rate) * currency.rate
        let f = paySpread(baseMonthlyWage: base, country: country)
        if f != 1 {
            let r2 = roundTo(v * f, step: 100)
            v = Currency.nicePrice(r2 / currency.rate) * currency.rate
        }
        return v
    }
}
