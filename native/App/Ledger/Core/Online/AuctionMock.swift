import Foundation
import Simulation

struct MockAuctionService: AuctionService {
    let vault: GoldVault

    func refresh(cash: Int, priceLevel: Double) async -> AuctionsSnapshot { await vault.refresh(cash: cash, priceLevel: priceLevel) }
    func placeBid(auctionID: String, amount: Int, cash: Int) async throws -> AuctionsSnapshot { try await vault.placeBid(auctionID, amount: amount, cash: cash) }
    func buyNow(auctionID: String, cash: Int) async throws -> AuctionsSnapshot { try await vault.buyNow(auctionID, cash: cash) }
    func list(itemID: String, startPrice: Int, reserve: Int?, buyNow: Int?, duration: AuctionDuration) async throws -> AuctionsSnapshot {
        try await vault.list(itemID, startPrice: startPrice, reserve: reserve, buyNow: buyNow, duration: duration)
    }
    func cancel(auctionID: String) async throws -> AuctionsSnapshot { try await vault.cancel(auctionID) }
}
