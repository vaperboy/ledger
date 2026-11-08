import Foundation
import GameCore
import Businesses

/// The owner's orders to a manager (see `ManagerModel.Order`).
public extension GameEngine {
    /// Direction, Budget, Headcount, Pay and bonus, Replace, with what is set now; empty when the company has no manager.
    func managerOrders(companyID: Int) -> [ManagerModel.Order] { ManagerModel.orders(state, companyID: companyID, data: data) }

    /// Where the owner wants the business to go (nil clears it); the manager prices and markets accordingly.
    @discardableResult
    mutating func setDirection(companyID: Int, direction: ManagerModel.Direction?) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            ManagerModel.setDirection(&s, companyID: companyID, direction: direction)
        }
    }
}
