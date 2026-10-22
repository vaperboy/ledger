import Foundation
import GameCore
import Finance
import Businesses

/// Manager targets and the yearly budget as player actions. Model: `ManagerTargets` (original: features/people/targets_and_budgets.js).
public extension GameEngine {
    /// `tg58set` / `tg58f`: the targets as they would be at this strictness (0 easy, 1 realistic, 2 stretch). Nothing is saved.
    func targetPreview(companyID: Int, mode: Int) -> ManagerTargets.Preview? { ManagerTargets.preview(state, companyID: companyID, mode: mode, data: data) }
    /// `tg58go`: set this month's targets and the manager's bonus level (0 none, 1 standard, 2 high); also approves the year's budget.
    @discardableResult
    mutating func setTargets(companyID: Int, mode: Int, bonus: Int) -> Bool {
        var r = false; update { s, d, _ in r = ManagerTargets.apply(&s, companyID: companyID, mode: mode, bonus: bonus, data: d) }; return r
    }
    /// Approve the budget a manager drafted for the coming year.
    @discardableResult
    mutating func approveBudget(companyID: Int) -> Bool {
        var r = false; update { s, _, _ in r = ManagerTargets.approveBudget(&s, companyID: companyID) }; return r
    }
    /// The targets card: this month's standing, the year's budget, the last months.
    func targetStatus(companyID: Int) -> ManagerTargets.Status? { ManagerTargets.status(state, companyID: companyID, data: data) }
}
