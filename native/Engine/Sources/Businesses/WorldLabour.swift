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

    /// Notice and severance for letting someone go, with the employer's social charge: the one helper for staff, layoffs and managers.
    public func terminationCost(_ co: Company, monthlyWage: Double, tenureWeeks: Double, withCause: Bool = false, onNotice: Bool = false) -> Double {
        labour(co).termination(tenureWeeks: tenureWeeks, withCause: withCause, onNotice: onNotice)
            .cost(monthlyWage: monthlyWage, employerSocial: country(co).employerSocial)
    }
}
