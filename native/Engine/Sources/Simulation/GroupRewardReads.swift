import Foundation
import GameCore
import Countries
import Employees
import Businesses

// What a reward to a group employee (executive, head-office member, the analyst) would do, before the owner confirms it. The actions themselves are the
// `group*` ones in EmploymentReads.swift (`GroupPeople`); this read only prices them, with the same rounding and the same employer-cost rule.

public struct GroupRewardPreview: Equatable, Sendable {
    public var title: String
    /// Their monthly pay before and after (equal when the reward does not change it).
    public var wageBefore: Double
    public var wageAfter: Double
    /// What the group pays more a month with the employer's charges (pay and any weekly reimbursement), and what it pays once (a course).
    public var employerCostPerMonth: Double
    public var oneOffCost: Double
    /// What changes, in words.
    public var lines: [String]
}

public extension GameEngine {
    /// `percent` is the pay review (0.05 = 5 percent), `expense` a `StaffExpenses` item id, `workingPercent` the new working percentage.
    func groupRewardPreview(personID: Int, kind: StaffPromises.Kind, percent: Double = 0.05, expense: String = "", workingPercent: Double = 100) -> GroupRewardPreview {
        let wage: Double = GroupPeople.wage(state, personID: personID) ?? 0
        let cur: Currency = ManagerModel.playerCurrency(state, data)
        let level: Int = GroupPeople.level(state, personID: personID)
        var after: Double = wage
        var oneOff: Double = 0
        var extraMonthly: Double = 0
        var lines: [String] = []
        switch kind {
        case .salaryReview:
            after = cur.roundedStep(wage * (1 + percent), about: 100)
            lines.append("Their pay rises from the next payroll.")
        case .promotion:
            after = cur.roundedStep(wage * 1.05, about: 100)
            lines.append(level >= 2 ? "They already have full control, so only the pay rises." : "They get one more level of authority and a raise.")
        case .responsibility:
            lines.append(level >= 2 ? "They already have full control: nothing changes." : "They get one more level of authority. It costs nothing.")
        case .training:
            oneOff = cur.scaledPrice(6000)
            lines.append("A course, paid by you now.")
        case .betterConditions, .futureBenefits:
            if let item = StaffExpenses.item(expense) ?? StaffExpenses.all.first {
                extraMonthly = cur.scaledPrice(item.monthlyCost)
                lines.append(item.name + " is reimbursed every week while it is on.")
            }
        case .percentageChange:
            let old: Double = max(1, GroupPeople.percent(state, personID: personID))
            after = wage * workingPercent / old
            lines.append("Pay follows the working percentage.")
        }
        let country: Country = homeCountry
        let before: Double = EmployerCost.monthly(wage: wage, country: country).totalMonthly
        let now: Double = EmployerCost.monthly(wage: after, country: country).totalMonthly
        return GroupRewardPreview(title: kind.title, wageBefore: wage, wageAfter: after, employerCostPerMonth: now - before + extraMonthly, oneOffCost: oneOff, lines: lines)
    }
}
