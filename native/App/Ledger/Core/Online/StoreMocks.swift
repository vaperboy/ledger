import Foundation
import Simulation

struct MockStoreService: StoreService {
    let vault: GoldVault

    private static let grantsGoldWithoutPayment = true
    var isVisualOnly: Bool { Self.grantsGoldWithoutPayment }

    func state() async -> StoreState { await vault.state() }

    func buyPack(_ packID: String) async throws -> StoreState {
        guard Self.grantsGoldWithoutPayment else { throw StoreError.notAvailable }
        return try await vault.buyPack(packID)
    }

    func buySeasonBundle() async throws -> StoreState {
        guard Self.grantsGoldWithoutPayment else { throw StoreError.notAvailable }
        return await vault.buySeasonBundle()
    }

    func buyBoxBundle(_ bundleID: String, paidBoxesAllowed: Bool) async throws -> StoreState { try await vault.buyBoxBundle(bundleID, paidBoxesAllowed: paidBoxesAllowed) }
    func buyCosmetic(_ id: String, owned: Set<String>) async throws -> StoreState { try await vault.buyCosmetic(id, owned: owned) }
    func buyAvatar(_ id: String, owned: Set<String>) async throws -> StoreState { try await vault.buyAvatar(id, owned: owned) }
    func openBoxes(_ kind: BoxKind, count: Int, owned: Set<String>, paidBoxesAllowed: Bool) async throws -> BoxOpening {
        try await vault.openBoxes(kind, count: count, owned: owned, paidBoxesAllowed: paidBoxesAllowed)
    }
    func grantFromSeason(boxes: Int, gold: Int) async -> StoreState { await vault.grantFromSeason(boxes: boxes, gold: gold) }
    func quickSell(itemIDs: [String], priceLevel: Double) async throws -> QuickSale { try await vault.quickSell(itemIDs, priceLevel: priceLevel) }
}
