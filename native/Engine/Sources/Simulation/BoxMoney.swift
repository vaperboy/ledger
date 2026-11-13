import Foundation
import GameCore
import Countries
import Finance

public enum BoxMoney {
    public static let label = "Prize from a box"
    static let rememberLimit = 200

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
    @discardableResult
    mutating func claimBoxMoney(_ amount: Int, claimID: String) -> Double? {
        var paid: Double?
        let cur: Currency = homeCurrency
        update { s, _, _ in paid = BoxMoney.claim(&s, amount: amount, claimID: claimID, currency: cur) }
        return paid
    }
}

public enum AuctionCash {
    static let rememberLimit = 200

    /// The most one sale can pay: the asking cap on a legendary piece, in local money.
    public static func maxProceeds(currency cur: Currency) -> Int {
        AuctionRules.maxAsk(value: AuctionMarket.suggestedStart(.legendary, priceLevel: 1 / max(cur.rate, 0.000_001)))
    }

    @discardableResult
    public static func settle(_ s: inout GameState, local: Int, claimID: String, label: String, currency cur: Currency) -> Double? {
        guard local != 0, !claimID.isEmpty else { return nil }
        guard local <= maxProceeds(currency: cur) else { return nil }
        var seen: [JSONValue] = (s.rest["aucm"] ?? .null).array
        if seen.contains(where: { $0.string == claimID }) { return nil }
        let cash: Double = jsRound(Double(local) * cur.rate)
        guard cash != 0 else { return nil }
        seen.append(.string(claimID))
        if seen.count > rememberLimit { seen.removeFirst(seen.count - rememberLimit) }
        s.rest["aucm"] = .array(seen)
        Ledger.move(&s, .me, cash, why: label)
        return cash
    }
}

public extension GameEngine {
    var auctionCash: Int { max(0, Int((state.cash / homeCurrency.rate).rounded(.down))) }

    /// Local money per unit of game money, so gold-based values follow the game's exchange rate only.
    var auctionPriceLevel: Double { 1 / homeCurrency.rate }

    @discardableResult
    mutating func settleAuctionCash(_ local: Int, claimID: String, label: String) -> Double? {
        var paid: Double?
        let cur: Currency = homeCurrency
        update { s, _, _ in paid = AuctionCash.settle(&s, local: local, claimID: claimID, label: label, currency: cur) }
        return paid
    }
}
