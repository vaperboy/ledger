import Foundation
import GameCore

/// One row of the cosmetics catalogue: what it is, how rare, and where a player gets it.
public struct CatalogEntry: Equatable, Sendable, Identifiable {
    public var kind: SeasonReward.Kind
    public var id: String
    public var title: String
    public var rarity: BoxRarity
    public var art: String
    public var detail: String
    public var drop: String
}

public enum CosmeticCatalog {
    public static let avatarKinds: [SeasonReward.Kind] = [.outfit, .face, .hair, .skin]

    static func drop(_ c: GoldCosmetic) -> String {
        switch c.source {
        case .store: return "Store (\(c.price ?? 0) gold) and boxes"
        case .box: return "Boxes only"
        case .collection: return "Collection reward"
        case .plan: return "Ledger plan"
        case .free: return "Free"
        case .level: return "Level \(c.value)"
        case .rank: return "Rank \(c.value): " + (Int(c.value).flatMap { (n: Int) -> String? in n < Career.ranks.count ? Career.ranks[n].title : nil } ?? "")
        case .goal: return "Goal " + c.value + ": " + (Career.defs.first { $0.id == c.value }?.title ?? "")
        case .mission: return "Sometimes found with a mission reward"
        case .event: return "Event box only: " + (EventBoxes.home(of: c.id).map { (b: EventBox) -> String in b.title + " (" + b.setTitle + ")" } ?? "event")
        }
    }

    static func drop(_ r: SeasonReward) -> String {
        "Season \(r.season) pass, tier \(r.tier), " + (r.premium ? "premium" : "free")
    }

    /// Every cosmetic a player can see today: the gold catalogue plus the cosmetic rewards of live seasons.
    public static func entries(today: Int = SeasonCatalog.today()) -> [CatalogEntry] {
        var out: [CatalogEntry] = GoldCosmetics.visible(today: today).map { (c: GoldCosmetic) -> CatalogEntry in
            CatalogEntry(kind: c.item.kind, id: c.id, title: c.item.title, rarity: c.rarity, art: c.art, detail: c.item.detail, drop: drop(c))
        }
        for r in SeasonRewards.visible(today: today) where ![.box, .gold, .xp, .profileCard, .companyCard, .artifact].contains(r.kind) {
            out.append(CatalogEntry(kind: r.kind, id: r.id, title: r.title, rarity: r.rarity ?? .common, art: r.art, detail: r.detail, drop: drop(r)))
        }
        return out
    }

    /// Cosmetic ids the player owns without having bought or won them: free items, level and rank outfits and finished career goals.
    public static func earned(level: Int, bestRank: Int, goalRewards: [String]) -> Set<String> {
        var out: Set<String> = []
        for c in GoldCosmetics.everything {
            switch c.source {
            case .free: out.insert(c.id)
            case .level: if level >= (Int(c.value) ?? Int.max) { out.insert(c.id) }
            case .rank: if bestRank >= (Int(c.value) ?? Int.max) { out.insert(c.id) }
            case .goal: if goalRewards.contains(c.id) { out.insert(c.id) }
            default: break
            }
        }
        return out
    }
}
