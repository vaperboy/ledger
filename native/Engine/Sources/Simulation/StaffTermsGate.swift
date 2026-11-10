import Foundation
import GameCore
import Businesses

public extension GameEngine {
    static let staffTermsMinimumStaff = 5

    func staffTermsUnlocked(companyID: Int) -> Bool {
        guard let co = state.company(companyID) else { return false }
        return co.managerID != nil || co.staff.count >= Self.staffTermsMinimumStaff
    }
}
