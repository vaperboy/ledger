import Foundation
import GameCore
import Countries
import Finance
import Businesses

// Manager hiring, premises proposals and staff growth paths: the public reads and actions for the screens (no screen yet; the owner decides about screens later).
// Rules: Businesses/ManagerHiring.swift, PremisesProposals.swift, GrowthPaths.swift.

public extension GameEngine {
    // MARK: Who hires

    /// May the company's manager hire one more person in this role now (`target` = how many the team calls for)? Without a manager the answer is always no.
    func managerMayHire(companyID: Int, role: String, target: Int) -> ManagerHiring.Verdict {
        ManagerHiring.verdict(state, companyID: companyID, role: role, target: target, data: data)
    }

    // MARK: Bigger premises

    /// The move to bigger premises a demand-limited company would make (the numbers behind the manager's proposal), nil when it is not premises-limited.
    func premisesPlan(companyID: Int) -> PremisesProposals.Plan? { PremisesProposals.plan(state, companyID: companyID, data: data) }

    /// Move now to the best bigger premises without waiting for the proposal. False if there is no plan or it cannot be paid.
    @discardableResult
    mutating func acceptPremisesMove(companyID: Int) -> Bool {
        var ok = false
        update { s, data, _ in ok = PremisesProposals.accept(&s, companyID: companyID, data: data) }
        return ok
    }

    /// Say no to a move (the manager does not ask again for a year).
    mutating func declinePremisesMove(companyID: Int) { update { s, _, _ in PremisesProposals.decline(&s, companyID: companyID) } }

    // MARK: Growth

    /// Where this employee can go next and how ready they are.
    func growthPath(companyID: Int, employeeID: Int) -> GrowthPath? { GrowthPaths.growthPath(state, companyID: companyID, employeeID: employeeID, data: data) }

    /// Promote a ready employee one rung (better role, assistant manager, manager).
    @discardableResult
    mutating func promote(companyID: Int, employeeID: Int) -> PromoteResult {
        var r = PromoteResult.blocked("")
        update { s, data, _ in r = GrowthPaths.promote(&s, companyID: companyID, employeeID: employeeID, data: data) }
        return r
    }

    /// Name the person who takes over when the manager leaves (`successorID` nil clears it).
    @discardableResult
    mutating func setSuccessor(companyID: Int, employeeID: Int, successorID: Int?) -> Bool {
        var ok = false
        update { s, _, _ in ok = GrowthPaths.setSuccessor(&s, companyID: companyID, employeeID: employeeID, successorID: successorID) }
        return ok
    }

    /// The person named to take over from the company's manager.
    func successor(companyID: Int) -> Int? { GrowthPaths.successor(state, companyID: companyID) }
}
