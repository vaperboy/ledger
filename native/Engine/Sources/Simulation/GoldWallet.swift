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

    /// The trigger for the "gold runs short" popup: what a purchase or bid of `price` is short of, or nil when the wallet can pay it.
    /// A bid that replaces the player's own leading bid passes `ownLead` (that hold is given back when the new bid is placed).
    public func shortfall(for price: Int, purpose: GoldShortfall.Purpose, ownLead: Int = 0) -> GoldShortfall? {
        let spendable: Int = available + max(0, ownLead)
        guard price > spendable else { return nil }
        return GoldShortfall(purpose: purpose, price: price, available: spendable, held: held)
    }
}

/// How short the wallet is, and the smallest pack that closes the gap. Pure data: the popup that shows it (and the store that sells the pack) are screens.
public struct GoldShortfall: Equatable, Sendable {
    public enum Purpose: String, Sendable { case box, bundle, cosmetic, bid }
    public var purpose: Purpose
    public var price: Int
    /// What could be spent when the check was made.
    public var available: Int
    /// Gold held for leading bids (not spendable).
    public var held: Int

    public var missing: Int { max(0, price - available) }
    /// True when the missing gold is exactly what a leading bid ties up: losing or withdrawing that bid would be enough.
    public var coveredByHeld: Bool { held >= missing }

    /// The smallest pack that covers `missing`, counting the one-time bonus when this would be the first pack bought; nil when no pack is big enough.
    public func suggestedPack(firstPurchase: Bool) -> GoldPack? {
        GoldStore.packs.filter { GoldStore.totalGold($0, firstPurchase: firstPurchase) >= missing }.min { $0.priceCents < $1.priceCents }
    }

    /// The shortage in plain words.
    public var text: String {
        let what: String
        switch purpose {
        case .box: what = "this box"
        case .bundle: what = "this bundle"
        case .cosmetic: what = "this item"
        case .bid: what = "this bid"
        }
        let base: String = "You are \(missing) gold short for \(what)."
        return coveredByHeld && held > 0 ? base + " \(held) gold is held for bids you lead; it comes back when you are outbid." : base
    }
}
