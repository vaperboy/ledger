import Foundation
import GameCore
import Businesses

/// Progressive unlocks (see Businesses/Unlocks.swift).
public extension GameEngine {
    /// Every registry item for one company: unlocked or not, with the reason text.
    func unlockState(companyID: Int) -> [UnlockItem] { Unlocks.state(state, companyID: companyID, context: context) }
    /// Newly opened unlocks the player has not been told about yet (announced once per company by the weekly sweep).
    func pendingUnlocks() -> [UnlockItem] { Unlocks.pending(state, context: context) }
    /// The player has seen the announcement.
    mutating func markUnlockShown(id: String, companyID: Int) { update { s, _, _ in Unlocks.markShown(&s, id: id, companyID: companyID) } }
    /// One item of one company.
    func unlockItem(_ id: String, companyID: Int) -> UnlockItem? { unlockState(companyID: companyID).first { (u: UnlockItem) -> Bool in u.id == id } }
}
