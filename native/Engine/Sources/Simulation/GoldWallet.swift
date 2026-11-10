import Foundation

public struct GoldWallet: Codable, Equatable, Sendable {
    public private(set) var balance: Int

    public init(balance: Int = 0) { self.balance = max(0, balance) }

    public var available: Int { balance }

    public mutating func credit(_ amount: Int) { balance += max(0, amount) }

    @discardableResult
    public mutating func spend(_ amount: Int) -> Bool {
        guard amount >= 0, amount <= available else { return false }
        balance -= amount
        return true
    }

    public func shortfall(for price: Int, purpose: GoldShortfall.Purpose) -> GoldShortfall? {
        guard price > available else { return nil }
        return GoldShortfall(purpose: purpose, price: price, available: available)
    }
}

public struct GoldShortfall: Equatable, Sendable {
    public enum Purpose: String, Sendable { case box, bundle, cosmetic }
    public var purpose: Purpose
    public var price: Int
    public var available: Int

    public var missing: Int { max(0, price - available) }

    public func suggestedPack(firstPurchase: Bool) -> GoldPack? {
        GoldStore.packs.filter { GoldStore.totalGold($0, firstPurchase: firstPurchase) >= missing }.min { $0.priceCents < $1.priceCents }
    }

    public var text: String {
        let what: String
        switch purpose {
        case .box: what = "this box"
        case .bundle: what = "this bundle"
        case .cosmetic: what = "this item"
        }
        return "You are \(missing) gold short for \(what)."
    }
}
