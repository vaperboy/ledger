import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {

    func managerMayHire(companyID: Int, role: String, target: Int) -> ManagerHiring.Verdict {
        ManagerHiring.verdict(state, companyID: companyID, role: role, target: target, data: data)
    }

    func premisesPlan(companyID: Int) -> PremisesProposals.Plan? { PremisesProposals.plan(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func acceptPremisesMove(companyID: Int) -> Bool {
        var ok = false
        update { s, data, _ in ok = PremisesProposals.accept(&s, companyID: companyID, data: data) }
        return ok
    }

    mutating func declinePremisesMove(companyID: Int) { update { s, _, _ in PremisesProposals.decline(&s, companyID: companyID) } }

    func growthPath(companyID: Int, employeeID: Int) -> GrowthPath? { GrowthPaths.growthPath(state, companyID: companyID, employeeID: employeeID, data: data) }

    @discardableResult
    mutating func promote(companyID: Int, employeeID: Int) -> PromoteResult {
        var r = PromoteResult.blocked("")
        update { s, data, _ in r = GrowthPaths.promote(&s, companyID: companyID, employeeID: employeeID, data: data) }
        return r
    }

    @discardableResult
    mutating func setSuccessor(companyID: Int, employeeID: Int, successorID: Int?) -> Bool {
        var ok = false
        update { s, _, _ in ok = GrowthPaths.setSuccessor(&s, companyID: companyID, employeeID: employeeID, successorID: successorID) }
        return ok
    }

    func successor(companyID: Int) -> Int? { GrowthPaths.successor(state, companyID: companyID) }
}
