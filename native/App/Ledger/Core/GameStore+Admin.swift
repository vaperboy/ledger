import Foundation
import GameCore
import Businesses
import Simulation

// An administrator account plays with every level gate open; the flag lives on the open save.
extension GameStore {
    /// Matches the open save to the account: opens every level gate for an administrator, closes them again otherwise.
    func applyAdminLevels(_ admin: Bool) {
        guard let e = engine, FeatureUnlocks.allOpen(e.state) != admin else { return }
        _ = act { (x: inout GameEngine) -> Void in x.update { s, _, _ in FeatureUnlocks.setAllOpen(&s, admin) } }
    }

    /// The same, from the last server answer; nothing changes before the server has answered once.
    func syncAdminLevels() {
        guard StoreSession.shared.server != nil else { return }
        applyAdminLevels(StoreSession.shared.isAdmin)
    }
}
