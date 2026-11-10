import Foundation
import GameCore
import Businesses

public extension GameEngine {
    func staffingPlan(companyID: Int) -> [StaffingPlan.Row] { StaffingPlan.plan(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func setHeadcountTarget(companyID: Int, role: String, target: Int, seasonal: Bool = false) -> Bool {
        var ok = false
        update { s, data, _ in ok = StaffingPlan.setTarget(&s, companyID: companyID, role: role, target: target, seasonal: seasonal, data: data) }
        return ok
    }

    @discardableResult
    mutating func resetHeadcountTarget(companyID: Int, role: String, seasonal: Bool = false) -> Bool {
        var ok = false
        update { s, _, _ in ok = StaffingPlan.resetTarget(&s, companyID: companyID, role: role, seasonal: seasonal) }
        return ok
    }

    @discardableResult
    mutating func setChainHeadcountTarget(chainID: Int, role: String, target: Int) -> Int {
        var n = 0
        update { s, data, _ in n = StaffingPlan.setChainTarget(&s, chainID: chainID, role: role, target: target, data: data) }
        return n
    }
}
