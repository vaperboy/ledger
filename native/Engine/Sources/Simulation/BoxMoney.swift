import Foundation
import GameCore
import Countries
import Finance

/// The rare cash prize of a free box. It is paid once into the player's account through the ledger (one statement line), so the books balance;
/// each opening has an id and a second claim with the same id pays nothing. The amount is in reference-economy money and is scaled to the
/// player's currency, like every fixed price.
public enum BoxMoney {
    public static let label = "Prize from a box"
    static let rememberLimit = 200

    /// Pays `amount` (reference units) for the opening `claimID`. Returns what was paid in the player's money, or nil when it was already
    /// claimed, is not a money prize the box odds allow, or is not positive.
    @discardableResult
    public static func claim(_ s: inout GameState, amount: Int, claimID: String, currency cur: Currency) -> Double? {
        guard amount > 0, amount <= BoxOdds.moneyCap, !claimID.isEmpty else { return nil }
        var seen: [JSONValue] = (s.rest["boxm"] ?? .null).array
        if seen.contains(where: { $0.string == claimID }) { return nil }
        let cash: Double = jsRound(cur.scaledPrice(Double(amount)))
        guard cash > 0 else { return nil }
        seen.append(.string(claimID))
        if seen.count > rememberLimit { seen.removeFirst(seen.count - rememberLimit) }
        s.rest["boxm"] = .array(seen)
        Ledger.move(&s, .me, cash, why: label)
        return cash
    }
}

public extension GameEngine {
    /// Pays the cash prize of an opened box (`BoxResult.Content.money`). `claimID` is the opening's own id, so a repeat pays nothing.
    @discardableResult
    mutating func claimBoxMoney(_ amount: Int, claimID: String) -> Double? {
        var paid: Double?
        let cur: Currency = homeCurrency
        update { s, _, _ in paid = BoxMoney.claim(&s, amount: amount, claimID: claimID, currency: cur) }
        return paid
    }
}
