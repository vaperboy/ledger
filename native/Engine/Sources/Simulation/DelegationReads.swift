import Foundation
import GameCore
import Countries
import Businesses

public extension GameEngine {
    /// What the player's managers may spend without asking, in the home currency, and that currency's rate (0 limit: nobody to delegate to).
    func delegatedSpendLimit() -> (limit: Double, rate: Double) {
        let limit = Delegation.spendLimit(state, data: data)
        guard limit > 0 else { return (0, 0) }
        return (limit, ManagerModel.playerCurrency(state, data).rate)
    }
}
