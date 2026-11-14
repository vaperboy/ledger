import Foundation
import GameCore

/// The prices (and event rotation) the server sent last, by group: boxes, bundles, rarity, items, services, events. They win over the
/// content table, so the app always shows what the server charges, including prices an administrator changed.
public final class ServerPriceBook: @unchecked Sendable {
    public static let shared = ServerPriceBook()
    private let lock = NSLock()
    private var groups: [String: [String: Int]] = [:]

    public func replace(_ new: [String: [String: Int]]) {
        lock.lock(); defer { lock.unlock() }
        groups = new
    }

    public func value(_ group: String, _ id: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return groups[group]?[id]
    }
}

public enum GoldPrices {
    static let table: JSONValue = ContentFile.load("pricing", "prices")

    public static var goldPerNok: Int { table["goldPerNok"].int }

    /// Game money (reference NOK) that one gold is worth inside the game.
    public static var gameNokPerGold: Double { table["gameNokPerGold"].double }

    public static func artifactValue(_ rarity: BoxRarity) -> Double { table["gold"]["artifactValue"][rarity.rawValue].double }

    public static func box(_ id: String) -> Int { ServerPriceBook.shared.value("boxes", id) ?? table["gold"]["boxes"][id].int }

    /// The price of a guaranteed item of a rarity (shelf and store).
    public static func cosmetic(rarity: BoxRarity) -> Int? {
        if let p = ServerPriceBook.shared.value("rarity", rarity.rawValue) { return p }
        let v: JSONValue = table["gold"]["cosmetics"][rarity.rawValue]
        return v.isNull ? nil : v.int
    }

    /// A single item's own price (save slots, or an administrator's price for one item).
    public static func item(_ id: String) -> Int? {
        if let p = ServerPriceBook.shared.value("items", id) { return p }
        let v: JSONValue = table["gold"]["items"][id]
        return v.isNull ? nil : v.int
    }

    public static func service(_ id: String) -> Int { ServerPriceBook.shared.value("services", id) ?? table["gold"]["services"][id].int }

    public static var battlePassPremiumGold: Int { table["gold"]["battlePassPremium"].int }

    public static let goldPacks: [GoldPack] = table["realMoney"]["goldPacks"].array.map { (e: JSONValue) -> GoldPack in
        GoldPack(id: e["id"].string, name: e["name"].string, priceCents: e["usdCents"].int, gold: e["gold"].int)
    }

    private static func bundle(_ key: String) -> SeasonBundle {
        let e: JSONValue = table["realMoney"][key]
        var boxes: [(kind: BoxKind, count: Int)] = []
        for b in e["boxes"].array {
            if let k = BoxKind(rawValue: b["kind"].string) { boxes.append((kind: k, count: b["count"].int)) }
        }
        return SeasonBundle(name: e["name"].string, priceCents: e["usdCents"].int, gold: e["gold"].int, boxes: boxes, includesPlus: e["includesPlus"].bool, tiers: e["tiers"].int)
    }

    public static let seasonBundle: SeasonBundle = bundle("seasonBundle")

    public static let seasonLevels: SeasonBundle = bundle("seasonLevels")

    public static var proBundleGold: Int { table["realMoney"]["bundles"]["pro"]["gold"].int }

    public static var founderBundleGold: Int { table["realMoney"]["bundles"]["founder"]["gold"].int }

    public static var founderPassTiers: Int { table["realMoney"]["bundles"]["founder"]["passTiers"].int }

    public static var founderLastSeason: Int { table["realMoney"]["bundles"]["founder"]["lastSeason"].int }

    public static var boxBundles: [BoxBundle] {
        var out: [BoxBundle] = []
        for e in table["gold"]["boxBundles"].array {
            guard let k = BoxKind(rawValue: e["kind"].string) else { continue }
            let id: String = k.rawValue + "x" + String(e["count"].int)
            out.append(BoxBundle(kind: k, count: e["count"].int, price: ServerPriceBook.shared.value("bundles", id) ?? e["price"].int))
        }
        return out
    }

    public static func planCents(_ productID: String) -> Int? {
        let v: JSONValue = table["realMoney"]["plans"][productID]
        return v.isNull ? nil : v.int
    }

    public static var planProductIDs: [String] { Array(table["realMoney"]["plans"].object.keys) }

    public struct Local: Equatable, Sendable {
        public var box: Double
        public var battlePass: Double
        public var oneTime: Double
    }

    public static var localCurrencies: [String] { table["localMoney"].object.keys.sorted() }

    public static func local(_ currency: String) -> Local? {
        let e: JSONValue = table["localMoney"][currency]
        guard !e.isNull else { return nil }
        return Local(box: e["box"].double, battlePass: e["battlePass"].double, oneTime: e["oneTime"].double)
    }
}
