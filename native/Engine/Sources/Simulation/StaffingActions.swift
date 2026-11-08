import Foundation
import GameCore
import Businesses

// The staffing plan for the screens: the headcount per role, who is in, what is open and for how long, and the owner's (or head office's) targets.
// Rules: Businesses/StaffingPlan.swift.

public extension GameEngine {
    /// One row per role of the company's plan (target, filled, vacancies, weeks open), then the seasonal crew and the store manager's post.
    func staffingPlan(companyID: Int) -> [StaffingPlan.Row] { StaffingPlan.plan(state, companyID: companyID, data: data) }

    /// Set how many people of a role the company should have (or, with `seasonal`, the size of the seasonal crew). The manager or boss fills it.
    @discardableResult
    mutating func setHeadcountTarget(companyID: Int, role: String, target: Int, seasonal: Bool = false) -> Bool {
        var ok = false
        update { s, data, _ in ok = StaffingPlan.setTarget(&s, companyID: companyID, role: role, target: target, seasonal: seasonal, data: data) }
        return ok
    }

    /// Go back to the target the company derives from its trade and its work.
    @discardableResult
    mutating func resetHeadcountTarget(companyID: Int, role: String, seasonal: Bool = false) -> Bool {
        var ok = false
        update { s, _, _ in ok = StaffingPlan.resetTarget(&s, companyID: companyID, role: role, seasonal: seasonal) }
        return ok
    }

    /// Head office sets a role's target for every open store of a chain. Returns how many stores took it.
    @discardableResult
    mutating func setChainHeadcountTarget(chainID: Int, role: String, target: Int) -> Int {
        var n = 0
        update { s, data, _ in n = StaffingPlan.setChainTarget(&s, chainID: chainID, role: role, target: target, data: data) }
        return n
    }
}
