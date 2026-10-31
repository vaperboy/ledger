import Foundation
import GameCore
import Countries

/// THE employer cost of one job (owner decision, Oct 2026: paid-leave cover is part of the number shown). Hiring previews, employee profiles, Team
/// metrics, payroll accrual, forecasts and Accounting all read this one function, so what a preview shows is what payroll books.
///
/// monthly cost = gross wage + employer contributions (social + pension) + insurance (injury) + paid-leave cover (on-cost included) + benefits + other.
/// Rates come from the country's data (`Country.employerOnCost`); where the data has no separate insurance rate the line is 0.
public enum EmployerCost {
    public struct Breakdown: Equatable, Sendable {
        /// Gross pay per contracted hour (0 when the hours are not known).
        public var grossHourlyWage: Double
        /// Share of a full week, 1 = full time.
        public var workingPercentage: Double
        public var contractedHoursPerWeek: Double
        public var expectedHoursPerMonth: Double
        public var grossMonthlyWage: Double
        public var grossAnnualWage: Double
        /// Employer social contributions and pension, a month.
        public var employerTaxesAndContributions: Double
        /// Injury / accident insurance, a month (0 where the country has no separate rate).
        public var insurance: Double
        /// Cover for paid leave (the wage and its on-cost for the weeks the person is away), a month.
        public var paidLeaveCover: Double
        /// Perks, bonus plan and expense accruals that belong to the job, a month.
        public var benefits: Double
        public var otherCosts: Double
        public var totalMonthly: Double
        public var totalAnnual: Double
    }

    /// Cover for paid leave: the share of a year's wage the employer pays on top for the weeks someone is away (a working share of it).
    public static func holidayFactor(_ country: Country) -> Double { 1 + LabourRules(country: country).leaveWeeks / 52 * 0.3 }

    /// What one week of this wage costs payroll (cover for paid leave and the on-cost included): the weekly accrual of `Payroll.weeklyCost`.
    public static func weeklyAccrual(monthlyWage: Double, country: Country, holiday: Double) -> Double {
        monthlyWage * 12 / 52 * holiday * country.payrollFactor(monthlyWage: monthlyWage)
    }

    /// `monthlyWage` is the gross pay for the person's own hours (hourly staff: for their hours). `hoursPerWeek` nil = a full week.
    public static func monthly(wage: Double, country: Country, hoursPerWeek: Double? = nil, benefitsMonthly: Double = 0, otherMonthly: Double = 0) -> Breakdown {
        let full = StaffModel.fullWeekHours
        let hours = hoursPerWeek ?? full
        let share = full > 0 ? hours / full : 1
        let social = country.employerSocialRate(monthlyWage: wage)
        let contributions = wage * (social + country.employerPension)
        let insurance = wage * country.employerInjury
        let onCost = social + country.employerPension + country.employerInjury
        let cover = wage * (holidayFactor(country) - 1) * (1 + onCost)
        let total = wage + contributions + insurance + cover + benefitsMonthly + otherMonthly
        let monthHours = hours * 52 / 12
        return Breakdown(grossHourlyWage: monthHours > 0 ? wage / monthHours : 0, workingPercentage: share, contractedHoursPerWeek: hours, expectedHoursPerMonth: monthHours,
                         grossMonthlyWage: wage, grossAnnualWage: wage * 12, employerTaxesAndContributions: contributions, insurance: insurance, paidLeaveCover: cover,
                         benefits: benefitsMonthly, otherCosts: otherMonthly, totalMonthly: total, totalAnnual: total * 12)
    }

    /// The monthly cost of a staff member's standing pay (wage, on-cost, leave cover), with benefits added by the caller.
    public static func monthly(_ m: StaffMember, country: Country, benefitsMonthly: Double = 0) -> Breakdown {
        monthly(wage: m.monthlyWage, country: country, hoursPerWeek: m.weeklyHours ?? (m.partTimeShare * StaffModel.fullWeekHours), benefitsMonthly: benefitsMonthly)
    }
}
