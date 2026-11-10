import Foundation
import GameCore
import Countries

public enum Wages {
    public static func paySpread(baseMonthlyWage base: Double, country: Country) -> Double {
        let w = country.wageLevel == 0 ? 1 : country.wageLevel
        if w >= 1 { return 1 }
        let e = clamp(1 + (1 - base / 80000), 0.7, 1.6)
        return pow(w, e) / w
    }

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

public enum Payroll {
    public static func averageFactor(_ co: Company, country: Country) -> Double {
        var wages = 0.0, cost = 0.0
        for m in co.staff { wages += m.monthlyWage; cost += m.monthlyWage * country.payrollFactor(monthlyWage: m.monthlyWage) }
        if co.managerID != nil { wages += co.managerMonthlyWage; cost += co.managerMonthlyWage * country.payrollFactor(monthlyWage: co.managerMonthlyWage) }
        return wages > 0 ? cost / wages : country.payrollFactor(monthlyWage: country.medianMonthlyWage)
    }

    public static func weeklyCost(_ co: Company, country: Country, skipOffSeason: Bool = true, sickWeek: Int? = nil, capScale: Double = 1) -> Double {
        let labour = LabourRules(country: country)
        let holiday = 1 + labour.leaveWeeks / 52 * 0.3
        var cost = 0.0
        for m in co.staff where !(skipOffSeason && m.isOffSeason) {
            if sickWeek != nil && m.sickUntilWeek == sickWeek {
                let weekly = m.monthlyWage * 12 / 52
                cost += labour.employerSickPay(weeklyWage: weekly, rate: country.fx, capScale: capScale) * country.payrollFactor(monthlyWage: m.monthlyWage)
            } else {
                cost += EmployerCost.weeklyAccrual(monthlyWage: m.monthlyWage, country: country, holiday: holiday)
            }
        }
        if co.managerID != nil { cost += co.managerMonthlyWage * 12 / 52 * country.payrollFactor(monthlyWage: co.managerMonthlyWage) }
        return cost
    }
}
