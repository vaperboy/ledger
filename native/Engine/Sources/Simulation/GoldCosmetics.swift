import Foundation
import GameCore

public struct GoldCosmetic: Equatable, Sendable, Identifiable {
    public enum Source: String, Sendable { case box, store, collection }
    public var item: SeasonReward
    public var rarity: BoxRarity
    public var source: Source
    public var price: Int?
    public var id: String { item.id }
}

public enum GoldCosmetics {
    public static func storePrice(_ rarity: BoxRarity) -> Int? {
        switch rarity {
        case .common: return 60
        case .rare: return 150
        case .epic: return 400
        case .legendary: return nil
        }
    }

    public static let all: [GoldCosmetic] = ContentFile.load("cosmetics", "gold_cosmetics")["cosmetics"].array.map { (e: JSONValue) -> GoldCosmetic in
        let rarity: BoxRarity = ContentFile.rarity(e["rarity"].string)
        let source: GoldCosmetic.Source = GoldCosmetic.Source(rawValue: e["source"].string) ?? .store
        let price: Int? = e["price"].isNull ? (source == .store ? GoldCosmetics.storePrice(rarity) : nil) : e["price"].int
        let item: SeasonReward = SeasonReward(id: e["id"].string, tier: 0, premium: false, kind: SeasonReward.Kind(rawValue: e["kind"].string) ?? .badge,
                                              title: e["title"].string, detail: e["detail"].string, colors: ContentFile.colors(e["colors"]),
                                              season: 0, theme: ItemThemes.id(e), founderEdition: e["founderEdition"].bool, accountBound: e["bound"].bool)
        return GoldCosmetic(item: item, rarity: rarity, source: source, price: price)
    }

    public static func cosmetic(_ id: String) -> GoldCosmetic? { all.first { $0.id == id } }

    public static func boxPool(_ rarity: BoxRarity, owned: Set<String>) -> [GoldCosmetic] {
        all.filter { $0.rarity == rarity && $0.item.kind != .saveSlot && $0.source != .collection && !owned.contains($0.id) }
    }

    public static var storeItems: [GoldCosmetic] { all.filter { $0.price != nil } }
}

extension SeasonRewards {
    public static func item(_ id: String) -> SeasonReward? {
        all.first { $0.id == id } ?? GoldCosmetics.cosmetic(id)?.item
    }
}
