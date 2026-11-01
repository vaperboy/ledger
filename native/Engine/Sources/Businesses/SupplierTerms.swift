import Foundation
import GameCore

/// Read-only view of how a relationship with a supplier turns into a discount, for the Suppliers section: the next level and what it is worth.
/// Uses the same tables as `Suppliers.relationshipDiscount`; it adds no rule.
public extension Suppliers {
    struct NextTier: Equatable, Sendable {
        public var word: String
        /// The relationship score at which the level starts.
        public var from: Double
        public var discount: Double
    }

    /// The next relationship level above `r` that brings a better discount (nil when there is none).
    static func nextDiscountTier(_ r: Double) -> NextTier? {
        let now = discounts[index(r)]
        var i = index(r) + 1
        while i < words.count {
            if discounts[i] > now { return NextTier(word: words[i].word, from: words[i - 1].below, discount: discounts[i]) }
            i += 1
        }
        return nil
    }
}
