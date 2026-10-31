import Foundation
import GameCore
import Countries
import Employees
import Businesses

/// Company > Team compact metrics (spec 3H): workers, average hourly rate, total hours, total payroll cost. All from the one employer-cost rule.
public struct TeamMetrics: Equatable, Sendable {
    public var workers: Int
    /// Average gross hourly pay across contracted hours.
    public var averageHourlyRate: Double
    public var totalHoursPerWeek: Double
    public var totalHoursPerMonth: Double
    /// Total monthly employer cost of the people (EmployerCost, leave cover included).
    public var totalMonthlyCost: Double
    public var totalAnnualCost: Double
    public var grossMonthlyWages: Double
}

public extension GameEngine {
    func teamMetrics(companyID: Int) -> TeamMetrics? {
        guard let co = state.company(companyID) else { return nil }
        let c = EmployerCosts.company(co, state: state, data: data)
        var all = Array(c.people.values)
        if let m = c.manager { all.append(m) }
        let hours = all.reduce(0) { $0 + $1.contractedHoursPerWeek }
        let monthHours = all.reduce(0) { $0 + $1.expectedHoursPerMonth }
        let gross = all.reduce(0) { $0 + $1.grossMonthlyWage }
        return TeamMetrics(workers: all.count, averageHourlyRate: monthHours > 0 ? gross / monthHours : 0, totalHoursPerWeek: hours, totalHoursPerMonth: monthHours,
                           totalMonthlyCost: c.totalMonthly, totalAnnualCost: c.totalAnnual, grossMonthlyWages: gross)
    }
}
