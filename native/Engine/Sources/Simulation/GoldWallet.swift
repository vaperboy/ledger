import Foundation

/// The player's gold. Gold is premium currency: it is only ever spent (or held while a bid leads), never converted to in-game money,
/// and it never leaves a wallet except through a purchase, a sale fee or a won auction.
public struct GoldWallet: Codable, Equatable, Sendable {
    /// Everything owned, including what is held for a leading bid.
    public private(set) var balance: Int
    /// Part of `balance` reserved for bids that currently lead.
    public private(set) var held: Int

    public init(balance: Int = 0) { self.balance = max(0, balance); held = 0 }

    /// What can be spent or bid right now.
    public var available: Int { balance - held }

    public mutating func credit(_ amount: Int) { balance += max(0, amount) }

    /// Spends gold that is not held; false (and no change) when there is not enough.
    @discardableResult
    public mutating func spend(_ amount: Int) -> Bool {
        guard amount >= 0, amount <= available else { return false }
        balance -= amount
        return true
    }

    @discardableResult
    public mutating func hold(_ amount: Int) -> Bool {
        guard amount > 0, amount <= available else { return false }
        held += amount
        return true
    }

    /// Gives a hold back (the bid was beaten or the auction failed).
    public mutating func release(_ amount: Int) { held = max(0, held - max(0, amount)) }

    /// Turns a hold into a payment (the auction was won).
    public mutating func spendHeld(_ amount: Int) {
        let n: Int = min(max(0, amount), held)
        held -= n
        balance -= n
    }
}
