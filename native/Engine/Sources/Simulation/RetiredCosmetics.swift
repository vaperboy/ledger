import Foundation
import GameCore

/// Items that were sold for gold and are no longer given out (frames and profile icons). Saves that own them still load; the gold price comes back once.
public enum RetiredCosmetics {
    public struct Refund: Equatable, Sendable, Identifiable {
        public var id: String
        public var gold: Int
    }

    public static let refunds: [Refund] = ContentFile.load("cosmetics", "retired")["refunds"].array.map { (e: JSONValue) -> Refund in
        Refund(id: e["id"].string, gold: e["gold"].int)
    }

    public static func isRetired(_ id: String) -> Bool { refunds.contains { $0.id == id } }
}

extension SeasonPass {
    /// Gold owed for retired items the player owns and has not yet been paid for. `alsoOwned` is for owned ids kept outside the pass (profile icons).
    /// Each item pays once; the ids are remembered in the save.
    @discardableResult
    public mutating func refundRetired(alsoOwned: Set<String> = []) -> Int {
        var paid: Set<String> = refunded ?? []
        var gold = 0
        for r in RetiredCosmetics.refunds where !paid.contains(r.id) && (owned.contains(r.id) || alsoOwned.contains(r.id)) {
            gold += r.gold
            paid.insert(r.id)
        }
        if paid != (refunded ?? []) { refunded = paid }
        return gold
    }
}
