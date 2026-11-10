import Foundation
import Simulation

struct LocalStoreService: StoreService {
    let vault: GoldVault

    func state() async -> StoreState { await vault.state() }

    func deliver(_ item: PurchaseItem, transactionID: String) async throws -> PurchaseDeliveryResult { try await vault.deliver(item, transactionID: transactionID) }
    func revoke(transactionID: String) async -> StoreState { await vault.revoke(transactionID: transactionID) }

    func buyBoxBundle(_ bundleID: String, paidBoxesAllowed: Bool) async throws -> StoreState { try await vault.buyBoxBundle(bundleID, paidBoxesAllowed: paidBoxesAllowed) }
    func buyCosmetic(_ id: String, owned: Set<String>) async throws -> StoreState { try await vault.buyCosmetic(id, owned: owned) }
    func buyAvatar(_ id: String, owned: Set<String>) async throws -> StoreState { try await vault.buyAvatar(id, owned: owned) }
    func openBoxes(_ kind: BoxKind, count: Int, owned: Set<String>, paidBoxesAllowed: Bool) async throws -> BoxOpening {
        try await vault.openBoxes(kind, count: count, owned: owned, paidBoxesAllowed: paidBoxesAllowed)
    }
    func grantFromSeason(boxes: Int, gold: Int) async -> StoreState { await vault.grantFromSeason(boxes: boxes, gold: gold) }
    func grantCard(defID: String, roll: Double) async -> StoreState { await vault.grantCard(defID, roll: roll) }
    func quickSell(itemIDs: [String], priceLevel: Double) async throws -> QuickSale { try await vault.quickSell(itemIDs, priceLevel: priceLevel) }
    func giveAway(itemID: String) async throws -> StoreState { try await vault.giveAway(itemID) }
    func receiveGift(_ item: ArtifactItem) async -> (state: StoreState, completed: [ArtifactCollection]) { await vault.receiveGift(item) }
}
