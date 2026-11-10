import Foundation

public struct GoldPack: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var priceCents: Int
    public var gold: Int
}

public struct BoxBundle: Equatable, Sendable, Identifiable {
    public var kind: BoxKind
    public var count: Int
    public var price: Int
    public var id: String { "\(kind.rawValue)x\(count)" }
    public var singlesPrice: Int { kind.price * count }
    public var savingPercent: Int { singlesPrice == 0 ? 0 : Int((Double(singlesPrice - price) / Double(singlesPrice) * 100).rounded()) }
}

public struct SeasonBundle: Equatable, Sendable {
    public var name: String
    public var priceCents: Int
    public var gold: Int
    public var boxes: [(kind: BoxKind, count: Int)]
    public var includesPlus: Bool

    public static func == (a: SeasonBundle, b: SeasonBundle) -> Bool {
        a.name == b.name && a.priceCents == b.priceCents && a.gold == b.gold && a.includesPlus == b.includesPlus
            && a.boxes.map { "\($0.kind)\($0.count)" } == b.boxes.map { "\($0.kind)\($0.count)" }
    }
}

public enum GoldStore {
    public static let packs: [GoldPack] = [
        GoldPack(id: "gold.pouch", name: "Pouch", priceCents: 199, gold: 200),
        GoldPack(id: "gold.purse", name: "Purse", priceCents: 499, gold: 550),
        GoldPack(id: "gold.chest", name: "Chest", priceCents: 999, gold: 1_200),
        GoldPack(id: "gold.vault", name: "Vault", priceCents: 1_999, gold: 2_600),
        GoldPack(id: "gold.hoard", name: "Hoard", priceCents: 4_999, gold: 7_000)
    ]

    public static let seasonBundle = SeasonBundle(name: "Season bundle", priceCents: 1_499, gold: 1_000, boxes: [(.cabinet, 3)], includesPlus: true)

    public static let boxBundles: [BoxBundle] = [
        BoxBundle(kind: .cabinet, count: 5, price: 540),
        BoxBundle(kind: .cabinet, count: 10, price: 1_000),
        BoxBundle(kind: .grand, count: 3, price: 1_080)
    ]

    public static func firstPurchaseBonus(_ pack: GoldPack) -> Int { pack.gold / 2 }

    public static func totalGold(_ pack: GoldPack, firstPurchase: Bool) -> Int { pack.gold + (firstPurchase ? firstPurchaseBonus(pack) : 0) }

    public static func goldPerUnit(_ pack: GoldPack) -> Double { Double(pack.gold) / (Double(pack.priceCents) / 100) }

    public static func extraPercent(_ pack: GoldPack) -> Int {
        guard let base = packs.first else { return 0 }
        return max(0, Int(((goldPerUnit(pack) / goldPerUnit(base) - 1) * 100).rounded()))
    }

    public static func priceText(cents: Int) -> String {
        String(format: "$%d.%02d", cents / 100, cents % 100)
    }

    public static func price(_ box: BoxKind) -> Int { box.price }
}

public enum StoreAccess {
    public static let paidBoxRestrictedCountries: Set<String> = []

    public enum Access: Equatable, Sendable {
        case hidden
        case open(paidBoxes: Bool)
    }

    public static func access(adultConfirmed: Bool?, countryCode: String?, restricted: Set<String> = paidBoxRestrictedCountries) -> Access {
        guard adultConfirmed == true else { return .hidden }
        let code: String = (countryCode ?? "").uppercased()
        let blocked: Set<String> = Set(restricted.map { $0.uppercased() })
        return .open(paidBoxes: !blocked.contains(code))
    }
}
