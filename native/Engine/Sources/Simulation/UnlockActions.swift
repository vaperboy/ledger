import Foundation
import GameCore
import Businesses

public extension GameEngine {
    func unlockState(companyID: Int) -> [UnlockItem] { Unlocks.state(state, companyID: companyID, context: context) }
    func pendingUnlocks() -> [UnlockItem] { Unlocks.pending(state, context: context) }
    mutating func markUnlockShown(id: String, companyID: Int) { update { s, _, _ in Unlocks.markShown(&s, id: id, companyID: companyID) } }
    func unlockedFeatures() -> [String] { Unlocks.unlockedFeatures(state) }
    func unlockItem(_ id: String, companyID: Int) -> UnlockItem? { unlockState(companyID: companyID).first { (u: UnlockItem) -> Bool in u.id == id } }
    func unlockRoadmap() -> [UnlockRoadmapItem] { Gates.roadmap(state, data: data, context: context) }
}
