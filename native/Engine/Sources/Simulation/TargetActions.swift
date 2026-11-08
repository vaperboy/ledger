import Foundation
import GameCore
import Finance
import Businesses

/// The yearly budget and the targets card as player actions. Model: `ManagerTargets`. Targets follow the direction set in the quarterly review.
public extension GameEngine {
    /// Approve the budget a manager drafted for the coming year.
    @discardableResult
    mutating func approveBudget(companyID: Int) -> Bool {
        var r = false; update { s, _, _ in r = ManagerTargets.approveBudget(&s, companyID: companyID) }; return r
    }
    /// The targets card: this month's standing, the year's budget, the last months.
    func targetStatus(companyID: Int) -> ManagerTargets.Status? { ManagerTargets.status(state, companyID: companyID, data: data) }
}
