import Foundation
import GameCore
import Businesses

public extension GameEngine {
    /// Staff headcount (or a manager) from which the contract extras (perks, promises, expenses, bonus plans) show in hiring and contracts.
    static let staffTermsMinimumStaff = 5

    /// Perks, promises, expenses and the other contract extras are offered once the company has five staff or a manager; before that a hire is
    /// the going rate with an above or below market choice. A missing company never unlocks them.
    func staffTermsUnlocked(companyID: Int) -> Bool {
        guard let co = state.company(companyID) else { return false }
        return co.managerID != nil || co.staff.count >= Self.staffTermsMinimumStaff
    }
}
