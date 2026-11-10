import Foundation
import GameCore
import Businesses

public extension GameEngine {
    func managerOrders(companyID: Int) -> [ManagerModel.Order] { ManagerModel.orders(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func setDirection(companyID: Int, direction: ManagerModel.Direction?) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            ManagerModel.setDirection(&s, companyID: companyID, direction: direction)
        }
    }
}
