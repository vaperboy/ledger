import Foundation
import GameCore
import Countries
import Finance
import Investments

public struct TradeQuote: Equatable, Sendable {
    public var amount: Double
    public var fee: Double
    public var units: Double
    public var cashChange: Double
    public var minimumPurchase: Double
    public var available: Double
    public var cashAfter: Double
    public var refusal: String?
}

public extension GameEngine {
    func buyQuote(_ kind: Brokerage.Kind, symbol: String, amount: Double) -> TradeQuote {
        let cur = homeCurrency
        let amt = amount.rounded()
        let minimum = Brokerage.minimumPurchase(cur)
        let fee = kind == .crypto ? amt * 0.004 : Brokerage.brokerFee(amt, currency: cur)
        let px = kind == .crypto ? Brokerage.price(state, kind, symbol) * 1.008 : Brokerage.price(state, kind, symbol)
        let liquid = Payments.liquid(state)
        var refusal: String?
        if amt < minimum { refusal = "The smallest order is \(cur.display(minimum))." }
        else if liquid < amt + fee { refusal = "That needs \(cur.display(amt + fee)) with the fee; your account holds \(cur.display(max(0, liquid)))." }
        else if kind == .crypto, state.rest["crypto"]?[symbol]["dead"].bool == true { refusal = "Trading in \(symbol) has stopped." }
        return TradeQuote(amount: amt, fee: fee, units: px > 0 ? amt / px : 0, cashChange: amt + fee, minimumPurchase: minimum, available: liquid,
                          cashAfter: state.cash - (amt + fee), refusal: refusal)
    }

    func sellQuote(_ kind: Brokerage.Kind, symbol: String, fraction: Double) -> TradeQuote {
        let cur = homeCurrency
        let f = min(max(fraction, 0), 1)
        let held = quotes(kind).first { $0.symbol == symbol }
        let px = kind == .crypto ? Brokerage.price(state, kind, symbol) * 0.992 : Brokerage.price(state, kind, symbol)
        let units = (held?.quantity ?? 0) * f
        let value = units * px
        let fee = kind == .crypto ? value * 0.004 : Brokerage.brokerFee(value, currency: cur)
        let refusal: String? = units <= 0 ? "There is nothing held to sell." : nil
        return TradeQuote(amount: value, fee: fee, units: units, cashChange: max(0, value - fee), minimumPurchase: 0, available: Payments.liquid(state),
                          cashAfter: state.cash + max(0, value - fee), refusal: refusal)
    }
}
