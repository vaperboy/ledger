import Foundation

public struct ArtifactDef: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var collection: String
    public var rarity: BoxRarity
    public var note: String
    public var edition: Int { ArtifactCatalog.edition(rarity) }
}

public struct ArtifactCollection: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var blurb: String
    public var rewardID: String
    public var members: [String]
}

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

    public static func def(_ id: String) -> ArtifactDef? { defs.first { $0.id == id } ?? CardCatalog.artifactDef(id) }
    public static func collection(_ id: String) -> ArtifactCollection? { collections.first { $0.id == id } }
    public static func defs(of rarity: BoxRarity) -> [ArtifactDef] { defs.filter { $0.rarity == rarity } }

    public static func serial(of def: ArtifactDef, roll: Double) -> Int {
        min(def.edition, max(1, 1 + Int(max(0, min(0.999999, roll)) * Double(def.edition))))
    }

    public static func label(_ item: ArtifactItem) -> String {
        "\(item.serial) of \(def(item.defID)?.edition ?? 0)"
    }
}

public struct Cabinet: Codable, Equatable, Sendable {
    public private(set) var items: [ArtifactItem] = []
    public private(set) var rewarded: Set<String> = []

    public init() {}

    public func owns(_ defID: String) -> Bool { items.contains { $0.defID == defID } }
    public func contains(_ id: String) -> Bool { items.contains { $0.id == id } }

    public func progress(_ collection: ArtifactCollection) -> (have: Int, total: Int) {
        (collection.members.filter { owns($0) }.count, collection.members.count)
    }

    public func isComplete(_ collection: ArtifactCollection) -> Bool { progress(collection).have == collection.members.count }

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

    @discardableResult
    public mutating func quickSell(_ id: String, priceLevel: Double) -> Int? {
        guard let item = items.first(where: { $0.id == id }), let def = ArtifactCatalog.def(item.defID) else { return nil }
        remove(id)
        return AuctionRules.quickSalePrice(def.rarity, priceLevel: priceLevel)
    }

    public func duplicates(among candidates: [ArtifactItem]) -> [ArtifactItem] {
        var keeper: [String: ArtifactItem] = [:]
        for item in items where keeper[item.defID].map({ item.serial < $0.serial }) ?? true { keeper[item.defID] = item }
        return candidates.filter { c in contains(c.id) && keeper[c.defID]?.id != c.id }
    }

    public var sorted: [ArtifactItem] {
        items.sorted { a, b in
            let ra: Int = ArtifactCatalog.def(a.defID)?.rarity.rank ?? 0
            let rb: Int = ArtifactCatalog.def(b.defID)?.rarity.rank ?? 0
            if ra != rb { return ra > rb }
            return a.defID != b.defID ? a.defID < b.defID : a.serial < b.serial
        }
    }
}
