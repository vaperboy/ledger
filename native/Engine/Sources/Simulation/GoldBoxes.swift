import Foundation
import GameCore

public enum BoxRarity: String, Codable, CaseIterable, Sendable, Comparable {
    case common, rare, epic, legendary
    public var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public var title: String { rawValue.capitalized }
    public static func < (a: BoxRarity, b: BoxRarity) -> Bool { a.rank < b.rank }
}

public enum BoxKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Given by the Season Pass; never sold.
    case free
    case cabinet
    case grand
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .free: return "Season box"
        case .cabinet: return "Cabinet box"
        case .grand: return "Grand box"
        }
    }
    /// Gold price; 0 for the free box.
    public var price: Int {
        switch self {
        case .free: return 0
        case .cabinet: return 120
        case .grand: return 400
        }
    }
    public var isPaid: Bool { price > 0 }
}

/// What a row of the odds table hands out. Gold is a small prize: never more than the box costs.
public enum BoxPrizeClass: Equatable, Sendable {
    case cosmetic, artifact, gold(Int)
    /// A small prize of in-game money, in reference-economy units (scaled to the player's currency when claimed). Free boxes only.
    case money(Int)
}

/// One line of a box's published odds. `weight` is in basis points (out of 10,000).
public struct BoxRow: Equatable, Sendable {
    public var rarity: BoxRarity
    public var prize: BoxPrizeClass
    public var weight: Int
    public var percent: Double { Double(weight) / 100 }
}

/// What came out of a box.
public struct BoxResult: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case cosmetic(String)
        case artifact(ArtifactItem)
        case gold(Int, doubled: Bool)
        /// Reference-economy money; `BoxMoney.claim` pays it into the player's account through the ledger.
        case money(Int)
    }
    public var rarity: BoxRarity
    public var content: Content
    /// True when the guarantee decided this box (a rare or better was owed).
    public var guaranteed: Bool
}

/// The count towards the guaranteed rare. Applies to paid boxes: after `threshold - 1` boxes without a rare or better, the next one has one.
public struct BoxPity: Codable, Equatable, Sendable {
    public static let threshold = 10
    /// Paid boxes opened since the last rare or better.
    public var sinceRare = 0
    public init(sinceRare: Int = 0) { self.sinceRare = sinceRare }

    public var nextIsGuaranteed: Bool { sinceRare >= Self.threshold - 1 }

    /// The count in words.
    public var text: String {
        if nextIsGuaranteed { return "Your next paid box is guaranteed to hold a rare or better item." }
        let left: Int = Self.threshold - sinceRare
        return "A rare or better item is guaranteed within \(left) more paid boxes. Finding one sooner starts the count again."
    }

    public mutating func record(_ rarity: BoxRarity) {
        if rarity >= .rare { sinceRare = 0 } else { sinceRare += 1 }
    }
}

/// The published odds of every box, and the rules that keep paid boxes from paying out gold. Pure data and arithmetic.
public enum BoxOdds {
    public static let totalWeight = 10_000
    /// Chance (basis points) that a gold prize from a free box is doubled: 1 in 100.
    public static let doubleGoldChance = 100

    private static func r(_ rarity: BoxRarity, _ prize: BoxPrizeClass, _ w: Int) -> BoxRow { BoxRow(rarity: rarity, prize: prize, weight: w) }

    public static func rows(_ kind: BoxKind) -> [BoxRow] {
        switch kind {
        case .free:
            return [r(.common, .cosmetic, 1500), r(.common, .artifact, 3450), r(.common, .gold(5), 3000), r(.common, .money(1_000), 50),
                    r(.rare, .cosmetic, 370), r(.rare, .artifact, 800), r(.rare, .gold(10), 500), r(.rare, .money(5_000), 30),
                    r(.epic, .cosmetic, 100), r(.epic, .artifact, 150),
                    r(.legendary, .artifact, 50)]
        case .cabinet:
            return [r(.common, .cosmetic, 2800), r(.common, .artifact, 2800), r(.common, .gold(20), 1400),
                    r(.rare, .cosmetic, 900), r(.rare, .artifact, 1000), r(.rare, .gold(40), 400),
                    r(.epic, .cosmetic, 300), r(.epic, .artifact, 250), r(.epic, .gold(60), 50),
                    r(.legendary, .cosmetic, 40), r(.legendary, .artifact, 60)]
        case .grand:
            return [r(.common, .cosmetic, 1500), r(.common, .artifact, 2500), r(.common, .gold(40), 500),
                    r(.rare, .cosmetic, 1400), r(.rare, .artifact, 2000), r(.rare, .gold(80), 400),
                    r(.epic, .cosmetic, 500), r(.epic, .artifact, 800), r(.epic, .gold(150), 100),
                    r(.legendary, .cosmetic, 120), r(.legendary, .artifact, 180)]
        }
    }

    /// Chance of each rarity in percent (0...100), from the table.
    public static func rarityPercent(_ kind: BoxKind) -> [(rarity: BoxRarity, percent: Double)] {
        BoxRarity.allCases.map { (rar: BoxRarity) in
            (rar, Double(rows(kind).filter { $0.rarity == rar }.reduce(0) { $0 + $1.weight }) / 100)
        }
    }

    /// Average gold a box hands out, counting the rare doubling of a free box's gold.
    public static func expectedGold(_ kind: BoxKind) -> Double {
        let boost: Double = kind == .free ? 1 + Double(doubleGoldChance) / Double(totalWeight) : 1
        return rows(kind).reduce(0.0) { sum, row in
            if case .gold(let g) = row.prize { return sum + Double(row.weight) / Double(totalWeight) * Double(g) * boost }
            return sum
        }
    }

    /// The biggest gold prize a box can hold, doubled where doubling applies.
    public static func largestGold(_ kind: BoxKind) -> Int {
        let top: Int = rows(kind).reduce(0) { m, row in
            if case .gold(let g) = row.prize { return max(m, g) }
            return m
        }
        return kind == .free ? top * 2 : top
    }

    /// Chance in percent that a box holds a money prize (only the free box has any), and the most such a prize is worth in reference-economy money.
    public static func moneyPercent(_ kind: BoxKind) -> Double {
        Double(rows(kind).filter { if case .money = $0.prize { return true } else { return false } }.reduce(0) { $0 + $1.weight }) / 100
    }
    public static func largestMoney(_ kind: BoxKind) -> Int {
        rows(kind).reduce(0) { m, row in
            if case .money(let v) = row.prize { return max(m, v) }
            return m
        }
    }
    /// The most a money prize can be worth: a few days of a small shop's takings, never a way to buy a company.
    public static let moneyCap = 5_000

    /// The check behind the promise: weights add up, a paid box returns less gold than it costs on average (and no single gold prize reaches its price),
    /// a free box's gold stays small.
    public static func isFair(_ kind: BoxKind) -> Bool {
        guard rows(kind).reduce(0, { $0 + $1.weight }) == totalWeight else { return false }
        guard largestMoney(kind) <= moneyCap else { return false }
        if kind.isPaid { return moneyPercent(kind) == 0 && expectedGold(kind) < Double(kind.price) && largestGold(kind) < kind.price }
        return largestGold(kind) <= 50 && moneyPercent(kind) <= 2
    }

    /// The disclosure lines for a box: the prize and its chance, e.g. "Rare artifact" and "10.00%".
    public static func disclosure(_ kind: BoxKind) -> [(title: String, percent: Double)] {
        rows(kind).map { row in
            let what: String
            switch row.prize {
            case .cosmetic: what = "cosmetic"
            case .artifact: what = "artifact"
            case .gold(let g): what = "\(g) gold"
            case .money(let m): what = "cash prize (\(m) in the reference economy, scaled to your country's money)"
            }
            return ("\(row.rarity.title) \(what)", row.percent)
        }
    }

    // MARK: Opening

    /// Opens a box. `seed` makes the result repeatable (the real server would roll it; the stand-in uses a fresh seed each time).
    /// The pity count moves only for paid boxes. Cosmetics the player owns are not offered again: that prize becomes an artifact of the same rarity.
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
        }
        var next: BoxPity = pity
        if kind.isPaid { next.record(row.rarity) }
        return (BoxResult(rarity: row.rarity, content: content, guaranteed: guaranteed), next)
    }

    private static func artifact(_ rarity: BoxRarity, _ itemRoll: Double, _ serialRoll: Double) -> ArtifactItem {
        let pool: [ArtifactDef] = ArtifactCatalog.defs(of: rarity)
        let def: ArtifactDef = pool[min(pool.count - 1, Int(itemRoll * Double(pool.count)))]
        return ArtifactItem(defID: def.id, serial: ArtifactCatalog.serial(of: def, roll: serialRoll))
    }
}
