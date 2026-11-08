import Foundation
import GameCore
import Businesses

/// Progressive unlocks (see Businesses/Unlocks.swift).
public extension GameEngine {
    /// Every registry item for one company: unlocked or not, with the reason text.
    func unlockState(companyID: Int) -> [UnlockItem] { Unlocks.state(state, companyID: companyID, context: context) }
    /// Newly opened unlocks the player has not been told about yet (announced once per unlock by the weekly sweep, whichever company earned it).
    func pendingUnlocks() -> [UnlockItem] { Unlocks.pending(state, context: context) }
    /// The player has seen the announcement.
    mutating func markUnlockShown(id: String, companyID: Int) { update { s, _, _ in Unlocks.markShown(&s, id: id, companyID: companyID) } }
    /// Ids of every feature the player has unlocked; they are open for every company.
    func unlockedFeatures() -> [String] { Unlocks.unlockedFeatures(state) }
    /// One item of one company.
    func unlockItem(_ id: String, companyID: Int) -> UnlockItem? { unlockState(companyID: companyID).first { (u: UnlockItem) -> Bool in u.id == id } }
    /// Everything still locked with the condition in plain words and the progress, closest first: one list for a "what unlocks next" screen.
    func unlockRoadmap() -> [UnlockRoadmapItem] { Gates.roadmap(state, data: data, context: context) }
}
