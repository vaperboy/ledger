import Foundation

/// Cosmetics and comfort that gold buys or that boxes and collections hand out. They reuse `SeasonReward` so the same wardrobe
/// (owned set, equip) serves the Season Pass and the store. Nothing here touches money or the simulation.
public struct GoldCosmetic: Equatable, Sendable, Identifiable {
    public enum Source: String, Sendable { case box, store, collection }
    public var item: SeasonReward
    public var rarity: BoxRarity
    /// `store`: sold for gold and also found in boxes. `box`: prizes only. `collection`: given for a finished collection.
    public var source: Source
    /// Gold price in the store; nil when it cannot be bought.
    public var price: Int?
    public var id: String { item.id }
}

public enum GoldCosmetics {
    private static func c(_ id: String, _ kind: SeasonReward.Kind, _ title: String, _ detail: String, _ colors: [UInt32], _ rarity: BoxRarity,
                          _ source: GoldCosmetic.Source = .store, price: Int? = nil) -> GoldCosmetic {
        let p: Int? = price ?? (source == .store ? storePrice(rarity) : nil)
        return GoldCosmetic(item: SeasonReward(id: id, tier: 0, premium: false, kind: kind, title: title, detail: detail, colors: colors), rarity: rarity, source: source, price: p)
    }

    /// Store price by rarity for items the store sells (legendary items are box and collection prizes only).
    public static func storePrice(_ rarity: BoxRarity) -> Int? {
        switch rarity {
        case .common: return 60
        case .rare: return 150
        case .epic: return 400
        case .legendary: return nil
        }
    }

    public static let all: [GoldCosmetic] = [
        c("gold.plate.pewter", .namePlate, "Pewter plate", "A quiet grey name plate.", [0xA9ADB5, 0x2C2E33], .common),
        c("gold.backdrop.fog", .backdrop, "Fog backdrop", "A soft grey backdrop.", [0x39414A, 0x262B31], .common),
        c("gold.trade.pewter", .tradePlate, "Pewter trade plate", "A grey plate for your trade names.", [0xA9ADB5, 0x2C2E33], .common),
        c("gold.theme.sage", .theme, "Sage theme", "A sage tint on the usual palette.", [0x9DB59A, 0x232B22], .common),
        c("gold.theme.amber", .theme, "Amber theme", "A warm amber tint.", [0xE0A458, 0x33261A], .rare),
        c("gold.plate.copper", .namePlate, "Copper plate", "A name plate in worn copper.", [0xC27C5A, 0x33241C], .rare),
        c("gold.backdrop.plum", .backdrop, "Plum backdrop", "A deep plum backdrop.", [0x4A2F44, 0x2C1C29], .rare),
        c("gold.flair.laurel", .richListFlair, "Rich-list laurel", "A laurel beside your name on the rich list.", [0xA8B88A], .rare),
        c("gold.theme.indigo", .theme, "Indigo theme", "A deep indigo tint.", [0x8C94E0, 0x1E2140], .epic),
        c("gold.plate.onyx", .namePlate, "Onyx plate", "A polished black name plate.", [0xD6D6D8, 0x111113], .epic),
        c("gold.backdrop.aurora", .backdrop, "Aurora backdrop", "Green into violet, very quiet.", [0x2E5A52, 0x3A2E5A], .epic),
        c("gold.trade.rose", .tradePlate, "Rose trade plate", "A rose gold plate for trade names.", [0xE3B7A8, 0x4A3028], .epic),
        c("gold.plate.leaf", .namePlate, "Gold leaf plate", "A name plate in hammered gold leaf.", [0xF0CF73, 0x6B4E12], .legendary, .box),
        c("gold.theme.crimson", .theme, "Crimson theme", "A deep crimson tint.", [0xE0707A, 0x3A1519], .legendary, .box),
        c("gold.flair.sun", .richListFlair, "Rich-list sun", "A gold sun beside your name on the rich list.", [0xF5D56B, 0x8A5A10], .legendary, .box),
        c("gold.coll.counting", .namePlate, "Counting House plate", "Reward for completing the Counting House collection.", [0xE0BC5E, 0x3A3022], .epic, .collection),
        c("gold.coll.harbour", .backdrop, "Harbour Lights backdrop", "Reward for completing the Harbour Trade collection.", [0x2C5A66, 0x1A3238], .epic, .collection),
        c("gold.coll.market", .tradePlate, "Market Square trade plate", "Reward for completing the Market Square collection.", [0xD99AA6, 0x3A2227], .epic, .collection),
        c("gold.coll.archive", .richListFlair, "Archive seal", "Reward for completing the Town Archive collection.", [0xE4DFD3, 0x4A4842], .epic, .collection),
        // Extra save slots: comfort, bought in order.
        c("gold.slot.1", .saveSlot, "Extra save slot", "Room for one more saved game.", [], .common, .store, price: 400),
        c("gold.slot.2", .saveSlot, "Second extra save slot", "Room for one more saved game.", [], .common, .store, price: 600),
        c("gold.slot.3", .saveSlot, "Third extra save slot", "Room for one more saved game.", [], .common, .store, price: 900)
    ]

    public static func cosmetic(_ id: String) -> GoldCosmetic? { all.first { $0.id == id } }

    /// Prizes a box can hold at a rarity, minus what the player already owns.
    public static func boxPool(_ rarity: BoxRarity, owned: Set<String>) -> [GoldCosmetic] {
        all.filter { $0.rarity == rarity && $0.item.kind != .saveSlot && $0.source != .collection && !owned.contains($0.id) }
    }

    /// What the store sells for gold, in a fixed order.
    public static var storeItems: [GoldCosmetic] { all.filter { $0.price != nil } }
}

extension SeasonRewards {
    /// Any season reward or gold cosmetic by id (the wardrobe reads both).
    public static func item(_ id: String) -> SeasonReward? {
        all.first { $0.id == id } ?? GoldCosmetics.cosmetic(id)?.item
    }
}
