import Foundation
import GameCore

/// The Store's cosmetics shelf of the day: a fixed-size pick of box and store items, the same for everyone on a day.
/// Battle Pass items are never on it; the pass is the only way to get them. The server makes the real pick; this one
/// is used without the server (previews, tests).
public enum StoreRotation {
    public static let size: Int = 6

    /// The gold price on the shelf: the item's own price, else the store price of its rarity (a guaranteed item always costs clearly
    /// more than a box that may drop it). Legendary items stay box-only.
    public static func price(_ c: GoldCosmetic) -> Int? { c.price ?? GoldPrices.item(c.id) ?? GoldCosmetics.storePrice(c.rarity) }

    /// Every item that may come up on the shelf.
    public static func eligible(today: Int = SeasonCatalog.today()) -> [GoldCosmetic] {
        let pass: Set<String> = Set(SeasonRewards.everything.map { (r: SeasonReward) -> String in r.id })
        return GoldCosmetics.visible(today: today).filter { (c: GoldCosmetic) -> Bool in
            (c.source == .box || c.source == .store) && c.item.kind != .saveSlot && c.item.kind != .tradePlate && c.rarity != .legendary
                && !pass.contains(c.id) && (price(c) ?? 0) > 0
        }
    }

    /// The shelf of one day, in shelf order.
    public static func pick(day: Int, today: Int = SeasonCatalog.today()) -> [GoldCosmetic] {
        let ranked: [(c: GoldCosmetic, k: UInt64)] = eligible(today: today).map { (c: GoldCosmetic) -> (c: GoldCosmetic, k: UInt64) in (c, key(c.id, day)) }
        let sorted: [(c: GoldCosmetic, k: UInt64)] = ranked.sorted { (a: (c: GoldCosmetic, k: UInt64), b: (c: GoldCosmetic, k: UInt64)) -> Bool in
            a.k == b.k ? a.c.id < b.c.id : a.k < b.k
        }
        return sorted.prefix(size).map { (x: (c: GoldCosmetic, k: UInt64)) -> GoldCosmetic in x.c }
    }

    /// FNV-1a of "id:day", stable across runs and platforms.
    static func key(_ id: String, _ day: Int) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in (id + ":" + String(day)).utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }
}
