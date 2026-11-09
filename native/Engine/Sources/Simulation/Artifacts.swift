import Foundation

/// Collectible artifacts: numbered pieces ("14 of 500") in rarity tiers, grouped into collections. A finished collection pays a cosmetic.
/// Artifacts are the one thing players trade (through auctions); they carry no game effect.
public struct ArtifactDef: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var collection: String
    public var rarity: BoxRarity
    public var note: String
    /// How many exist; the serial of a piece runs from 1 to this.
    public var edition: Int { ArtifactCatalog.edition(rarity) }
}

public struct ArtifactCollection: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var blurb: String
    /// The cosmetic (`GoldCosmetics`) granted once, when every piece is in the cabinet.
    public var rewardID: String
    public var members: [String]
}

/// One numbered piece. `id` is unique per piece.
public struct ArtifactItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var defID: String
    public var serial: Int
    public var id: String { "\(defID)#\(serial)" }
    public init(defID: String, serial: Int) { self.defID = defID; self.serial = serial }
}

public enum ArtifactCatalog {
    public static func edition(_ rarity: BoxRarity) -> Int {
        switch rarity {
        case .common: return 5_000
        case .rare: return 1_500
        case .epic: return 500
        case .legendary: return 100
        }
    }

    private static func d(_ id: String, _ name: String, _ col: String, _ r: BoxRarity, _ note: String) -> ArtifactDef {
        ArtifactDef(id: id, name: name, collection: col, rarity: r, note: note)
    }

    public static let defs: [ArtifactDef] = [
        d("abacus", "Boxwood abacus", "counting", .common, "Worn smooth by a hundred years of sums."),
        d("scales", "Brass scales", "counting", .rare, "Weights stamped by an honest guild."),
        d("strongbox", "Iron strongbox", "counting", .epic, "The key was lost in the first year."),
        d("seal", "Gilt counting seal", "counting", .legendary, "Pressed on every ledger of a famous house."),
        d("rope", "Tarred rope coil", "harbour", .common, "Smells faintly of the sea."),
        d("lantern", "Ship's lantern", "harbour", .rare, "Lit the last berth of the evening."),
        d("chart", "Sea chart", "harbour", .epic, "Hand drawn, with a few secret shoals."),
        d("compass", "Silver compass", "harbour", .legendary, "Always points to a good deal."),
        d("token", "Clay market token", "market", .common, "Good for one measure of grain."),
        d("banner", "Silk stall banner", "market", .rare, "Faded by a thousand market days."),
        d("bell", "Merchant's bell", "market", .epic, "Rung to open and close the square."),
        d("weights", "Golden weights", "market", .legendary, "A matched set, never used."),
        d("stamp", "Ink stamp", "archive", .common, "Marks a page as seen."),
        d("map", "Old town map", "archive", .rare, "Shows streets that no longer exist."),
        d("scroll", "Charter scroll", "archive", .epic, "Grants the right to hold a fair."),
        d("charter", "Royal charter", "archive", .legendary, "The founding paper of the town.")
    ]

    public static let collections: [ArtifactCollection] = [
        ArtifactCollection(id: "counting", name: "Counting House", blurb: "Tools of the old bookkeepers.", rewardID: "gold.coll.counting", members: ["abacus", "scales", "strongbox", "seal"]),
        ArtifactCollection(id: "harbour", name: "Harbour Trade", blurb: "What came in on the tide.", rewardID: "gold.coll.harbour", members: ["rope", "lantern", "chart", "compass"]),
        ArtifactCollection(id: "market", name: "Market Square", blurb: "Stall, bell and scales of the square.", rewardID: "gold.coll.market", members: ["token", "banner", "bell", "weights"]),
        ArtifactCollection(id: "archive", name: "Town Archive", blurb: "Papers that made the town.", rewardID: "gold.coll.archive", members: ["stamp", "map", "scroll", "charter"])
    ]

    public static func def(_ id: String) -> ArtifactDef? { defs.first { $0.id == id } }
    public static func collection(_ id: String) -> ArtifactCollection? { collections.first { $0.id == id } }
    public static func defs(of rarity: BoxRarity) -> [ArtifactDef] { defs.filter { $0.rarity == rarity } }

    /// A serial in 1...edition from a roll in [0, 1).
    public static func serial(of def: ArtifactDef, roll: Double) -> Int {
        min(def.edition, max(1, 1 + Int(max(0, min(0.999999, roll)) * Double(def.edition))))
    }

    /// "14 of 500".
    public static func label(_ item: ArtifactItem) -> String {
        "\(item.serial) of \(def(item.defID)?.edition ?? 0)"
    }
}

/// The artifacts a player owns, and which collection rewards were already handed out.
public struct Cabinet: Codable, Equatable, Sendable {
    public private(set) var items: [ArtifactItem] = []
    public private(set) var rewarded: Set<String> = []

    public init() {}

    public func owns(_ defID: String) -> Bool { items.contains { $0.defID == defID } }
    public func contains(_ id: String) -> Bool { items.contains { $0.id == id } }

    /// Pieces of a collection held (each piece counted once, however many copies) and the size of the collection.
    public func progress(_ collection: ArtifactCollection) -> (have: Int, total: Int) {
        (collection.members.filter { owns($0) }.count, collection.members.count)
    }

    public func isComplete(_ collection: ArtifactCollection) -> Bool { progress(collection).have == collection.members.count }

    /// Adds a piece. Returns the collections this completed for the first time; their cosmetic is owed to the player (once, ever).
    @discardableResult
    public mutating func add(_ item: ArtifactItem) -> [ArtifactCollection] {
        guard !contains(item.id) else { return [] }
        items.append(item)
        var done: [ArtifactCollection] = []
        for col in ArtifactCatalog.collections where isComplete(col) && !rewarded.contains(col.id) {
            rewarded.insert(col.id)
            done.append(col)
        }
        return done
    }

    @discardableResult
    public mutating func remove(_ id: String) -> ArtifactItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    /// Rarest first, then by piece and serial, for display.
    public var sorted: [ArtifactItem] {
        items.sorted { a, b in
            let ra: Int = ArtifactCatalog.def(a.defID)?.rarity.rank ?? 0
            let rb: Int = ArtifactCatalog.def(b.defID)?.rarity.rank ?? 0
            if ra != rb { return ra > rb }
            return a.defID != b.defID ? a.defID < b.defID : a.serial < b.serial
        }
    }
}
