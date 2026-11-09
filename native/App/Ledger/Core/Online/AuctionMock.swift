import Foundation
import Simulation

/// The auction stand-in: sample players list pieces and bid over time (see `AuctionMarket` in the engine). Gold and pieces are shared with the store through the vault.
struct MockAuctionService: AuctionService {
    let vault: GoldVault

    func refresh() async -> AuctionsSnapshot { await vault.refresh() }
    func placeBid(auctionID: String, amount: Int) async throws -> AuctionsSnapshot { try await vault.placeBid(auctionID, amount: amount) }
    func list(itemID: String, startPrice: Int, reserve: Int?, duration: AuctionDuration) async throws -> AuctionsSnapshot {
        try await vault.list(itemID, startPrice: startPrice, reserve: reserve, duration: duration)
    }
    func cancel(auctionID: String) async throws -> AuctionsSnapshot { try await vault.cancel(auctionID) }
}
