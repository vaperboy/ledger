import Foundation
import Simulation

extension GameStore {
    /// Pays a money pack into the personal account through the ledger. Returns the game money paid, or nil when nothing was paid.
    func claimMoneyPack(_ packID: String, claimID: String) -> Double? {
        guard let paid = act({ $0.claimMoneyPack(packID, claimID: claimID) }) ?? nil, paid > 0 else { return nil }
        if let cur = engine?.homeCurrency { tell("Money added", "+" + cur.display(paid) + " is in your personal account.", tone: "good") }
        return paid
    }
}
