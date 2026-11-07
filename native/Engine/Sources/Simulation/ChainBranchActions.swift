import Foundation
import GameCore
import Finance
import Businesses

/// A branch of a chain leaves it by being closed (wound down) or sold as a going concern; it never fails or is sold as shares on its own.
/// The model is `ChainBranches`.
public extension GameEngine {
    func isBranch(companyID: Int) -> Bool { state.company(companyID).map { state.isBranch($0) } ?? false }
    func branchClosurePlan(storeID: Int) -> ChainBranches.ClosurePlan? { ChainBranches.closurePlan(state, storeID: storeID, data: data) }
    func branchSaleQuote(storeID: Int) -> ChainBranches.SaleQuote? { ChainBranches.saleQuote(state, storeID: storeID, data: data) }
    /// The chain's combined cash and how many weeks in a row it has been below zero.
    func chainCash(chainID: Int) -> (cash: Double, weeksOverdrawn: Int) {
        (ChainBranches.combinedCash(state, chainID: chainID), ChainBranches.weeksOverdrawn(state, chainID: chainID))
    }

    @discardableResult
    mutating func closeBranch(storeID: Int) -> Result<ChainBranches.ClosurePlan, ChainBranches.Refusal> {
        var r: Result<ChainBranches.ClosurePlan, ChainBranches.Refusal> = .failure(.notABranch)
        update { s, d, _ in r = ChainBranches.close(&s, storeID: storeID, data: d) }
        return r
    }

    @discardableResult
    mutating func sellBranch(storeID: Int) -> Result<ChainBranches.SaleQuote, ChainBranches.Refusal> {
        var r: Result<ChainBranches.SaleQuote, ChainBranches.Refusal> = .failure(.notABranch)
        update { s, d, _ in r = ChainBranches.sell(&s, storeID: storeID, data: d) }
        return r
    }
}
