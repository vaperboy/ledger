import Foundation
import GameCore

public enum Pricing {
    static let table: JSONValue = ContentFile.load("pricing", "prices")

    public static var goldPerNok: Int { table["goldPerNok"].int }

    public static func box(_ id: String) -> Int { table["gold"]["boxes"][id].int }

    public static func cosmetic(rarity: BoxRarity) -> Int? {
        let v: JSONValue = table["gold"]["cosmetics"][rarity.rawValue]
        return v.isNull ? nil : v.int
    }

    public static func item(_ id: String) -> Int? {
        let v: JSONValue = table["gold"]["items"][id]
        return v.isNull ? nil : v.int
    }

    public static func service(_ id: String) -> Int { table["gold"]["services"][id].int }

    public static var battlePassPremiumGold: Int { table["gold"]["battlePassPremium"].int }

    public static let goldPacks: [GoldPack] = table["realMoney"]["goldPacks"].array.map { (e: JSONValue) -> GoldPack in
        GoldPack(id: e["id"].string, name: e["name"].string, priceCents: e["usdCents"].int, gold: e["gold"].int)
    }

    public static let seasonBundle: SeasonBundle = {
        let e: JSONValue = table["realMoney"]["seasonBundle"]
        var boxes: [(kind: BoxKind, count: Int)] = []
        for b in e["boxes"].array {
            if let k = BoxKind(rawValue: b["kind"].string) { boxes.append((kind: k, count: b["count"].int)) }
        }
        return SeasonBundle(name: e["name"].string, priceCents: e["usdCents"].int, gold: e["gold"].int, boxes: boxes, includesPlus: e["includesPlus"].bool)
    }()

    public static let boxBundles: [BoxBundle] = {
        var out: [BoxBundle] = []
        for e in table["gold"]["boxBundles"].array {
            if let k = BoxKind(rawValue: e["kind"].string) { out.append(BoxBundle(kind: k, count: e["count"].int, price: e["price"].int)) }
        }
        return out
    }()

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
