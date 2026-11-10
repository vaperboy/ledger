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
    public static let packs: [GoldPack] = Pricing.goldPacks

    public static let seasonBundle: SeasonBundle = Pricing.seasonBundle

    public static let boxBundles: [BoxBundle] = Pricing.boxBundles

    public static func firstPurchaseBonus(_ pack: GoldPack) -> Int { pack.gold / 2 }

    public static func totalGold(_ pack: GoldPack, firstPurchase: Bool) -> Int { pack.gold + (firstPurchase ? firstPurchaseBonus(pack) : 0) }

    public static func goldPerUnit(_ pack: GoldPack) -> Double { Double(pack.gold) / (Double(pack.priceCents) / 100) }

    public static func extraPercent(_ pack: GoldPack) -> Int {
        guard let base = packs.first else { return 0 }
        return max(0, Int(((goldPerUnit(pack) / goldPerUnit(base) - 1) * 100).rounded()))
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
