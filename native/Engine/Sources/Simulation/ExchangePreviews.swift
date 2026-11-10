import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

public struct ExchangeOrderPreview: Equatable, Sendable {
    public var instrument: String
    public var side: ExchangeSide
    public var shares: Int
    public var limit: Double
    public var amount: Double
    public var fee: Double
    public var cashNow: Double
    public var cashAfterBuy: Double?
    public var bandLow: Double?, bandHigh: Double?
    public var refusal: OrderRefusal?
    public var allowed: Bool { refusal == nil }
    public var lines: [String]
}

public extension GameEngine {
    func previewOrder(instrument: String, side: ExchangeSide, shares: Int, limit: Double) -> ExchangeOrderPreview {
        var trial: GameEngine = self
        let cur: Currency = homeCurrency
        let px: Double = ExchangeRules.round4(limit)
        let amount: Double = Double(max(0, shares)) * max(0, px)
        let fee: Double = amount > 0 ? ExchangeRules.fee(amount, currency: cur) : 0
        let result: OrderResult = trial.placeExchangeOrder(instrument: instrument, side: side, shares: shares, limit: limit)
        var refusal: OrderRefusal?
        if case .refused(let r) = result { refusal = r }
        let row: ExchangeRow? = exchangeMarket.first { $0.id == instrument }
        let cash: Double = Payments.liquid(state)
        var lines: [String] = []
        if let why = refusal {
            lines.append(why.words)
        } else {
            let verb: String = side == .buy ? "buy" : "sell"
            lines.append("An order to \(verb) \(shares) at \(cur.display(px)) or better waits until the day's closing auction.")
            lines.append(side == .buy ? "At most \(cur.display(amount + fee)) leaves your cash, fee included, and only if it fills in full."
                                      : "If it fills you receive up to \(cur.display(amount - fee)) after the fee.")
            lines.append("If the price at the close is worse than your limit, nothing happens and you pay nothing. You can cancel until then.")
        }
        return ExchangeOrderPreview(instrument: instrument, side: side, shares: shares, limit: px, amount: amount, fee: fee, cashNow: cash,
                                    cashAfterBuy: side == .buy ? cash - amount - fee : nil, bandLow: row?.low, bandHigh: row?.high, refusal: refusal, lines: lines)
    }
}
