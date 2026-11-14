import Foundation
import GameCore

public struct GoldCosmetic: Equatable, Sendable, Identifiable {
    /// box and store drop from boxes (store ones are also sold for gold); collection, plan, level, rank and goal are earned; free is owned from the start;
    /// mission drops now and then with a mission reward; event comes only from its event box.
    public enum Source: String, Sendable { case box, store, collection, plan, free, level, rank, goal, mission, event }
    public var item: SeasonReward
    public var rarity: BoxRarity
    public var source: Source
    /// The catalogue price; nil when the item is not sold for gold.
    public var listPrice: Int?
    /// The level, rank number or goal id that unlocks it, for level, rank and goal items.
    public var value: String = ""
    public var id: String { item.id }
    public var art: String { item.art }

    /// The gold price now: an item's own price, else the store price of its rarity for store items (both follow the server). Nil when not sold.
    public var price: Int? {
        guard let p = listPrice else { return nil }
        if let own = GoldPrices.item(id) { return own }
        return source == .store ? (GoldCosmetics.storePrice(rarity) ?? p) : p
    }
}

public enum GoldCosmetics {
    public static func storePrice(_ rarity: BoxRarity) -> Int? {
        GoldPrices.cosmetic(rarity: rarity)
    }

    private static let file: JSONValue = ContentFile.load("cosmetics", "gold_cosmetics")

    static func parse(_ e: JSONValue, source forced: GoldCosmetic.Source? = nil) -> GoldCosmetic {
        let rarity: BoxRarity = ContentFile.rarity(e["rarity"].string)
        let source: GoldCosmetic.Source = forced ?? GoldCosmetic.Source(rawValue: e["source"].string) ?? .store
        let price: Int? = GoldPrices.item(e["id"].string) ?? (source == .store ? GoldCosmetics.storePrice(rarity) : nil)
        let earned: Bool = source != .box && source != .collection && source != .free && source != .event
        var item: SeasonReward = SeasonReward(id: e["id"].string, tier: 0, premium: false, kind: SeasonReward.Kind(rawValue: e["kind"].string) ?? .badge,
                                              title: e["title"].string, detail: e["detail"].string, colors: ContentFile.colors(e["colors"]),
                                              season: 0, theme: ItemThemes.id(e), founderEdition: e["founderEdition"].bool, accountBound: e["bound"].bool || earned)
        item.art = e["art"].string
        item.style = e["style"].string
        item.animated = e["animated"].bool
        item.animStyle = e["animStyle"].string
        item.anim = e["anim"].string
        item.rarity = rarity
        return GoldCosmetic(item: item, rarity: rarity, source: source, listPrice: price, value: e["value"].string)
    }

    /// Every current cosmetic, including those of seasons that have not started. For lookups of ids only.
    public static let everything: [GoldCosmetic] = GoldCosmetics.file["cosmetics"].array.map { (e: JSONValue) -> GoldCosmetic in parse(e) } + EventBoxes.cosmetics

    /// Items that are no longer given out (frames). They stay known so saves that own them still load and can be refunded.
    public static let retired: [GoldCosmetic] = GoldCosmetics.file["retired"].array.map { (e: JSONValue) -> GoldCosmetic in parse(e) }

    /// What a player can see today: nothing of a season that has not started.
    public static var all: [GoldCosmetic] { visible() }

    public static func visible(today: Int = SeasonCatalog.today()) -> [GoldCosmetic] {
        let hidden: Set<String> = SeasonCatalog.hiddenThemes(today: today)
        return everything.filter { !hidden.contains($0.item.theme) }
    }

    public static func cosmetic(_ id: String) -> GoldCosmetic? { everything.first { $0.id == id } ?? retired.first { $0.id == id } }

    public static func boxPool(_ rarity: BoxRarity, owned: Set<String>, today: Int = SeasonCatalog.today()) -> [GoldCosmetic] {
        visible(today: today).filter { (c: GoldCosmetic) -> Bool in
            c.rarity == rarity && c.item.kind != .saveSlot && (c.source == .box || c.source == .store) && !owned.contains(c.id)
        }
    }

    public static var storeItems: [GoldCosmetic] { visible().filter { $0.price != nil } }
}

extension SeasonRewards {
    public static func item(_ id: String) -> SeasonReward? {
        everything.first { $0.id == id } ?? GoldCosmetics.cosmetic(id)?.item
    }
}
