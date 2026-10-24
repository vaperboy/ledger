import Foundation
import GameCore
import Countries
import Employees

// Labour law of the company's own country (data: `LabourRules`, `labour` in country_traits.json).
extension World {
    public func labour(_ co: Company) -> LabourRules { LabourRules(country: country(co)) }

    /// The statutory (or agreed) minimum monthly pay, in accounting units, for someone contracted `hours` a week at this company.
    public func minimumWage(_ co: Company, hours: Double = StaffModel.fullWeekHours) -> Double {
        labour(co).minimumMonthly(hours: hours, rate: currency(co).rate, inflation: economy.inflation, week: week)
    }

    /// The one-off payments for letting someone go, kept apart: notice (or pay in lieu, with the employer charge at this wage), severance, and any
    /// termination fund fine. Routine payroll is not part of this. The one helper for staff, layoffs and managers.
    public func terminationPayments(_ co: Company, monthlyWage: Double, tenureWeeks: Double, withCause: Bool = false, onNotice: Bool = false,
                                    reason: LabourRules.TerminationReason? = nil, age: Double? = nil, massLayoff: Bool = false) -> (notice: Double, severance: Double, fine: Double) {
        let c = country(co)
        return labour(co).termination(tenureWeeks: tenureWeeks, withCause: withCause, onNotice: onNotice, reason: reason, age: age, massLayoff: massLayoff)
            .payments(monthlyWage: monthlyWage, employerSocial: c.employerSocialRate(monthlyWage: monthlyWage))
    }

    public func terminationCost(_ co: Company, monthlyWage: Double, tenureWeeks: Double, withCause: Bool = false, onNotice: Bool = false,
                                reason: LabourRules.TerminationReason? = nil, age: Double? = nil) -> Double {
        let p = terminationPayments(co, monthlyWage: monthlyWage, tenureWeeks: tenureWeeks, withCause: withCause, onNotice: onNotice, reason: reason, age: age)
        return p.notice + p.severance + p.fine
    }
}
