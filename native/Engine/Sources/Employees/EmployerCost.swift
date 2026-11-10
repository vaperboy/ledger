import Foundation
import GameCore
import Countries

public enum EmployerCost {
    public struct Breakdown: Equatable, Sendable {
        public var grossHourlyWage: Double
        public var workingPercentage: Double
        public var contractedHoursPerWeek: Double
        public var expectedHoursPerMonth: Double
        public var grossMonthlyWage: Double
        public var grossAnnualWage: Double
        public var employerTaxesAndContributions: Double
        public var insurance: Double
        public var paidLeaveCover: Double
        public var benefits: Double
        public var otherCosts: Double
        public var totalMonthly: Double
        public var totalAnnual: Double
    }

    public static func holidayFactor(_ country: Country) -> Double { 1 + LabourRules(country: country).leaveWeeks / 52 * 0.3 }

    public static func weeklyAccrual(monthlyWage: Double, country: Country, holiday: Double) -> Double {
        monthlyWage * 12 / 52 * holiday * country.payrollFactor(monthlyWage: monthlyWage)
    }

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

    public struct Deductions: Equatable, Sendable {
        public var incomeTax: Double
        public var employeeSocial: Double
        public var net: Double
        public var total: Double { incomeTax + employeeSocial }
    }

    public static func deductions(wage: Double, country: Country) -> Deductions {
        let tax = wage > 0 ? Taxes.personalIncomeTax(wage * 12, kind: .wage, in: country) / 12 : 0
        let social = wage * country.employeeSocial
        return Deductions(incomeTax: tax, employeeSocial: social, net: max(0, wage - tax - social))
    }

    public static func monthly(_ m: StaffMember, country: Country, benefitsMonthly: Double = 0) -> Breakdown {
        monthly(wage: m.monthlyWage, country: country, hoursPerWeek: m.weeklyHours ?? (m.partTimeShare * StaffModel.fullWeekHours), benefitsMonthly: benefitsMonthly)
    }
}
