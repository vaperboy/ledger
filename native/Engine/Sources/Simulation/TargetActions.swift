import Foundation
import GameCore
import Finance
import Businesses

public extension GameEngine {
    @discardableResult
    mutating func approveBudget(companyID: Int) -> Bool {
        var r = false; update { s, _, _ in r = ManagerTargets.approveBudget(&s, companyID: companyID) }; return r
    }
    func targetStatus(companyID: Int) -> ManagerTargets.Status? { ManagerTargets.status(state, companyID: companyID, data: data) }
}
