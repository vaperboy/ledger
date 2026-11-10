import Foundation
import GameCore

public enum BoxRarity: String, Codable, CaseIterable, Sendable, Comparable {
    case common, rare, epic, legendary
    public var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public var title: String { rawValue.capitalized }
    public static func < (a: BoxRarity, b: BoxRarity) -> Bool { a.rank < b.rank }
}

public enum BoxKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case free
    case cabinet
    case grand
    case cardBasic
    case cardPremium
    case cardElite
    public var id: String { rawValue }
    public var title: String { BoxCatalog.entries[rawValue]?.title ?? rawValue }
    public var price: Int { BoxCatalog.entries[rawValue]?.price ?? 0 }
    public var theme: String { BoxCatalog.entries[rawValue]?.theme ?? ItemThemes.classicID }
    public var isPaid: Bool { price > 0 }
    public var isCardPack: Bool { self == .cardBasic || self == .cardPremium || self == .cardElite }
    public static var standard: [BoxKind] { allCases.filter { !$0.isCardPack } }
    public static var cardPacks: [BoxKind] { allCases.filter { $0.isCardPack } }
}

public enum BoxPrizeClass: Equatable, Sendable {
    case cosmetic, artifact, gold(Int)
    case money(Int)
    case profileCard, companyCard
}

public struct BoxRow: Equatable, Sendable {
    public var rarity: BoxRarity
    public var prize: BoxPrizeClass
    public var weight: Int
    public var percent: Double { Double(weight) / 100 }
}

public struct BoxResult: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case cosmetic(String)
        case artifact(ArtifactItem)
        case gold(Int, doubled: Bool)
        case money(Int)
    }
    public var rarity: BoxRarity
    public var content: Content
    public var guaranteed: Bool
}

public struct BoxHaul: Equatable, Sendable {
    public var gold = 0
    public var money = 0
    public var cosmetics: [String] = []
    public var artifacts: [ArtifactItem] = []

    public init(_ results: [BoxResult]) {
        for r in results {
            switch r.content {
            case .gold(let g, _): gold += g
            case .money(let m): money += m
            case .cosmetic(let id): cosmetics.append(id)
            case .artifact(let item): artifacts.append(item)
            }
        }
    }
}

public struct BoxPity: Codable, Equatable, Sendable {
    public static let threshold = 10
    public var sinceRare = 0
    public init(sinceRare: Int = 0) { self.sinceRare = sinceRare }

    public var nextIsGuaranteed: Bool { sinceRare >= Self.threshold - 1 }

    public var text: String {
        if nextIsGuaranteed { return "Your next paid box is guaranteed to hold a rare or better item." }
        let left: Int = Self.threshold - sinceRare
        return "A rare or better item is guaranteed within \(left) more paid boxes. Finding one sooner starts the count again."
    }

    public mutating func record(_ rarity: BoxRarity) {
        if rarity >= .rare { sinceRare = 0 } else { sinceRare += 1 }
    }
}

enum BoxCatalog {
    struct Entry {
        var title: String
        var price: Int
        var theme: String
        var rows: [BoxRow]
    }

    static let entries: [String: Entry] = {
        var out: [String: Entry] = [:]
        for e in ContentFile.load("boxes", "boxes")["boxes"].array {
            out[e["id"].string] = Entry(title: e["title"].string, price: GoldPrices.box(e["id"].string), theme: ItemThemes.id(e), rows: e["rows"].array.map { (r: JSONValue) -> BoxRow in BoxCatalog.row(r) })
        }
        return out
    }()

    static func row(_ r: JSONValue) -> BoxRow {
        let amount: Int = r["amount"].int
        let prize: BoxPrizeClass
        switch r["prize"].string {
        case "cosmetic": prize = .cosmetic
        case "artifact": prize = .artifact
        case "gold": prize = .gold(amount)
        case "money": prize = .money(amount)
        case "profileCard": prize = .profileCard
        default: prize = .companyCard
        }
        return BoxRow(rarity: ContentFile.rarity(r["rarity"].string), prize: prize, weight: r["weight"].int)
    }
}

public enum BoxOdds {
    public static let totalWeight = 10_000
    public static let doubleGoldChance = 100

    public static func rows(_ kind: BoxKind) -> [BoxRow] { BoxCatalog.entries[kind.rawValue]?.rows ?? [] }

    public static func animatedPercent(_ kind: BoxKind) -> Double {
        var total = 0.0
        for row in rows(kind) {
            let k: CardDef.Kind
            switch row.prize {
            case .profileCard: k = .profile
            case .companyCard: k = .company
            default: continue
            }
            let pool: [CardDef] = CardCatalog.defs(k, row.rarity)
            guard !pool.isEmpty else { continue }
            total += row.percent * Double(pool.filter { $0.isAnimated }.count) / Double(pool.count)
        }
        return total
    }

    public static func rarityPercent(_ kind: BoxKind) -> [(rarity: BoxRarity, percent: Double)] {
        BoxRarity.allCases.map { (rar: BoxRarity) in
            (rar, Double(rows(kind).filter { $0.rarity == rar }.reduce(0) { $0 + $1.weight }) / 100)
        }
    }

    public static func expectedGold(_ kind: BoxKind) -> Double {
        let boost: Double = kind == .free ? 1 + Double(doubleGoldChance) / Double(totalWeight) : 1
        return rows(kind).reduce(0.0) { sum, row in
            if case .gold(let g) = row.prize { return sum + Double(row.weight) / Double(totalWeight) * Double(g) * boost }
            return sum
        }
    }

    public static func largestGold(_ kind: BoxKind) -> Int {
        let top: Int = rows(kind).reduce(0) { m, row in
            if case .gold(let g) = row.prize { return max(m, g) }
            return m
        }
        return kind == .free ? top * 2 : top
    }

    public static func moneyPercent(_ kind: BoxKind) -> Double {
        Double(rows(kind).filter { if case .money = $0.prize { return true } else { return false } }.reduce(0) { $0 + $1.weight }) / 100
    }
    public static func largestMoney(_ kind: BoxKind) -> Int {
        rows(kind).reduce(0) { m, row in
            if case .money(let v) = row.prize { return max(m, v) }
            return m
        }
    }
    public static let moneyCap = 5_000

    public static func isFair(_ kind: BoxKind) -> Bool {
        guard rows(kind).reduce(0, { $0 + $1.weight }) == totalWeight else { return false }
        guard largestMoney(kind) <= moneyCap else { return false }
        if kind.isPaid { return moneyPercent(kind) <= 5 && expectedGold(kind) < Double(kind.price) && largestGold(kind) < kind.price }
        return largestGold(kind) <= 50 && moneyPercent(kind) <= 2
    }

    public static func disclosure(_ kind: BoxKind) -> [(title: String, percent: Double)] {
        rows(kind).map { row in
            let what: String
            switch row.prize {
            case .cosmetic: what = "cosmetic"
            case .artifact: what = "artifact"
            case .gold(let g): what = "\(g) gold"
            case .money(let m): what = "cash prize (\(m) in the reference economy, scaled to your country's money)"
            case .profileCard: what = "profile card"
            case .companyCard: what = "company card"
            }
            return ("\(row.rarity.title) \(what)", row.percent)
        }
    }

    public static func open(_ kind: BoxKind, pity: BoxPity, ownedCosmetics: Set<String>, seed: String) -> (result: BoxResult, pity: BoxPity) {
        var rng = HashedRandom("box|" + seed)
        let guaranteed: Bool = kind.isPaid && pity.nextIsGuaranteed
        var table: [BoxRow] = rows(kind)
        if guaranteed {
            table = table.filter { (row: BoxRow) -> Bool in
                if case .gold = row.prize { return false }
                if case .money = row.prize { return false }
                return row.rarity >= .rare
            }
        }
        let total: Int = table.reduce(0) { $0 + $1.weight }
        let pick: Double = rng.next() * Double(total)
        var acc = 0.0
        var row: BoxRow = table[table.count - 1]
        for candidate in table {
            acc += Double(candidate.weight)
            if pick < acc { row = candidate; break }
        }
        let itemRoll: Double = rng.next()
        let serialRoll: Double = rng.next()
        let doubleRoll: Double = rng.next()
        var content: BoxResult.Content
        switch row.prize {
        case .gold(let g):
            let doubled: Bool = kind == .free && doubleRoll * Double(totalWeight) < Double(doubleGoldChance)
            content = .gold(doubled ? g * 2 : g, doubled: doubled)
        case .money(let m):
            content = .money(m)
        case .cosmetic:
            let pool: [GoldCosmetic] = GoldCosmetics.boxPool(row.rarity, owned: ownedCosmetics)
            if pool.isEmpty { content = .artifact(artifact(row.rarity, itemRoll, serialRoll)) }
            else { content = .cosmetic(pool[min(pool.count - 1, Int(itemRoll * Double(pool.count)))].id) }
        case .artifact:
            content = .artifact(artifact(row.rarity, itemRoll, serialRoll))
        case .profileCard:
            content = .artifact(card(.profile, row.rarity, itemRoll, serialRoll))
        case .companyCard:
            content = .artifact(card(.company, row.rarity, itemRoll, serialRoll))
        }
        var next: BoxPity = pity
        if kind.isPaid { next.record(row.rarity) }
        return (BoxResult(rarity: row.rarity, content: content, guaranteed: guaranteed), next)
    }

    public static func openMany(_ kind: BoxKind, count: Int, pity: BoxPity, ownedCosmetics: Set<String>, seed: String) -> (results: [BoxResult], pity: BoxPity) {
        var next: BoxPity = pity
        var owned: Set<String> = ownedCosmetics
        var results: [BoxResult] = []
        for n in 0..<max(0, count) {
            let out = open(kind, pity: next, ownedCosmetics: owned, seed: seed + "|" + String(n))
            next = out.pity
            if case .cosmetic(let id) = out.result.content { owned.insert(id) }
            results.append(out.result)
        }
        return (results, next)
    }

    private static func card(_ kind: CardDef.Kind, _ rarity: BoxRarity, _ itemRoll: Double, _ serialRoll: Double) -> ArtifactItem {
        let pool: [CardDef] = CardCatalog.defs(kind, rarity)
        return CardCatalog.item(pool[min(pool.count - 1, Int(itemRoll * Double(pool.count)))], roll: serialRoll)
    }

    private static func artifact(_ rarity: BoxRarity, _ itemRoll: Double, _ serialRoll: Double) -> ArtifactItem {
        let pool: [ArtifactDef] = ArtifactCatalog.defs(of: rarity)
        let def: ArtifactDef = pool[min(pool.count - 1, Int(itemRoll * Double(pool.count)))]
        return ArtifactItem(defID: def.id, serial: ArtifactCatalog.serial(of: def, roll: serialRoll))
    }
}
