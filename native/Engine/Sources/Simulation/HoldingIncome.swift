import Foundation
import GameCore
import Businesses
import Finance

/// What a holding earned, by source. A holding sells nothing and its cash earns no interest: its income is the dividends its
/// companies paid into it and the growth of the funds in its treasury.
public struct HoldingIncome: Equatable, Sendable {
    /// Dividends received from the companies it owns, within the asked weeks.
    public var dividends: Double
    /// Gain of the treasury funds at today's prices over what was paid for them (unrealised, since the funds were bought).
    public var fundGains: Double
    public var isEmpty: Bool { abs(dividends) < 0.5 && abs(fundGains) < 0.5 }
}

public extension GameEngine {
    /// The income split of a holding, or nil for a company that is not a holding.
    func holdingIncome(companyID: Int, weeks: ClosedRange<Int>? = nil) -> HoldingIncome? {
        guard let h = state.company(companyID), h.type == "hold" else { return nil }
        let paid: Double = Payments.holdingDividends(h, weeks: weeks)
        let gains: Double = HoldingModel.treasuryFunds.reduce(0) { (a: Double, sym: String) -> Double in
            a + HoldingModel.fundValue(h, state, sym) - HoldingModel.fundPosition(h, sym).cost
        }
        return HoldingIncome(dividends: paid, fundGains: gains)
    }
}
