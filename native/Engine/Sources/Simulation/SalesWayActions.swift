import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Ways to sell (platform, memberships, on-call service, add-ons) as the "Ways to sell" card of the original shows them.
public extension GameEngine {
    func waysToSell(companyID: Int) -> [SalesWays.Row] {
        SalesWays.rows(state, companyID: companyID, data: data)
    }
    /// Start or stop a way to sell.
    @discardableResult
    mutating func setWayToSell(companyID: Int, kind: String, on: Bool) -> SalesWays.Switch {
        var r = SalesWays.Switch.noCompany
        update { s, d, _ in r = SalesWays.setOn(&s, companyID: companyID, kind: kind, on: on, data: d) }
        return r
    }
}
