import Foundation
import GameCore
import Countries
import Finance
import Investments

/// What a purchase or a sale would do, read from the same rules `Brokerage.buy` and `Brokerage.sell` apply (fee, smallest order, the price
/// the crypto trade really gets, savings topping up the current account). Nothing here changes the game.
public struct TradeQuote: Equatable, Sendable {
    public var amount: Double
    public var fee: Double
    /// Buying: units received at the price the trade really gets. Selling: units sold.
    public var units: Double
    /// Selling: what reaches the account after the fee. Buying: what leaves it (amount plus fee).
    public var cashChange: Double
    public var minimumPurchase: Double
    /// Buying: current account plus savings, what the broker can draw on.
    public var available: Double
    public var cashAfter: Double
    /// Why it would not go through, in words (nil when it would).
    public var refusal: String?
}

public extension GameEngine {
    /// Buying `amount` of a name.
    func buyQuote(_ kind: Brokerage.Kind, symbol: String, amount: Double) -> TradeQuote {
        let cur = homeCurrency
        let amt = amount.rounded()
        let minimum = Brokerage.minimumPurchase(cur)
        let fee = kind == .crypto ? amt * 0.004 : Brokerage.brokerFee(amt, currency: cur)
        let px = kind == .crypto ? Brokerage.price(state, kind, symbol) * 1.008 : Brokerage.price(state, kind, symbol)
        let liquid = Payments.liquid(state)
        var refusal: String?
        if amt < minimum { refusal = "The smallest order is \(cur.display(minimum))." }
        else if liquid < amt + fee { refusal = "That needs \(cur.display(amt + fee)) with the fee; the current account and savings hold \(cur.display(max(0, liquid)))." }
        else if kind == .crypto, state.rest["crypto"]?[symbol]["dead"].bool == true { refusal = "Trading in \(symbol) has stopped." }
        return TradeQuote(amount: amt, fee: fee, units: px > 0 ? amt / px : 0, cashChange: amt + fee, minimumPurchase: minimum, available: liquid,
                          cashAfter: state.cash + state.savings - (amt + fee), refusal: refusal)
    }

    /// Selling `fraction` (0...1) of what is held.
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
                          cashAfter: state.cash + state.savings + max(0, value - fee), refusal: refusal)
    }
}
