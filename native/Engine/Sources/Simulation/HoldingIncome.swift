import Foundation
import GameCore
import Businesses
import Finance

public struct HoldingIncome: Equatable, Sendable {
    public var dividends: Double
    public var fundGains: Double
    public var isEmpty: Bool { abs(dividends) < 0.5 && abs(fundGains) < 0.5 }
}

public extension GameEngine {
    func holdingIncome(companyID: Int, weeks: ClosedRange<Int>? = nil) -> HoldingIncome? {
        guard let h = state.company(companyID), h.type == "hold" else { return nil }
        let paid: Double = Payments.holdingDividends(h, weeks: weeks)
        let gains: Double = HoldingModel.treasuryFunds.reduce(0) { (a: Double, sym: String) -> Double in
            a + HoldingModel.fundValue(h, state, sym) - HoldingModel.fundPosition(h, sym).cost
        }
        return HoldingIncome(dividends: paid, fundGains: gains)
    }
}
