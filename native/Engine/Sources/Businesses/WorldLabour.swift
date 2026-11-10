import Foundation
import GameCore
import Countries
import Employees

extension World {
    public func labour(_ co: Company) -> LabourRules { LabourRules(country: country(co)) }

    public func minimumWage(_ co: Company, hours: Double = StaffModel.fullWeekHours) -> Double {
        labour(co).minimumMonthly(hours: hours, rate: currency(co).rate, inflationIndex: economy.inflationIndex)
    }

    public func terminationPayments(_ co: Company, monthlyWage: Double, tenureWeeks: Double, withCause: Bool = false, onNotice: Bool = false,
                                    reason: LabourRules.TerminationReason? = nil, massLayoff: Bool = false) -> (notice: Double, severance: Double, fine: Double) {
        let c = country(co)
        return labour(co).termination(tenureWeeks: tenureWeeks, withCause: withCause, onNotice: onNotice, reason: reason, massLayoff: massLayoff)
            .payments(monthlyWage: monthlyWage, employerSocial: c.employerOnCost(monthlyWage: monthlyWage))
    }

    public func terminationCost(_ co: Company, monthlyWage: Double, tenureWeeks: Double, withCause: Bool = false, onNotice: Bool = false,
                                reason: LabourRules.TerminationReason? = nil) -> Double {
        let p = terminationPayments(co, monthlyWage: monthlyWage, tenureWeeks: tenureWeeks, withCause: withCause, onNotice: onNotice, reason: reason)
        return p.notice + p.severance + p.fine
    }
}
