import Foundation
import GameCore

public extension Suppliers {
    struct NextTier: Equatable, Sendable {
        public var word: String
        public var from: Double
        public var discount: Double
    }

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
