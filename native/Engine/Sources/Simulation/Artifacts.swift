import Foundation
import GameCore

public enum ContentFile {
    public static func load(_ kind: String, _ name: String) -> JSONValue {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources/Content/" + kind),
              let raw = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return json
    }

    public static func color(_ v: JSONValue) -> UInt32 { UInt32(v.string, radix: 16) ?? 0 }

    public static func colors(_ v: JSONValue) -> [UInt32] { v.array.map { (c: JSONValue) -> UInt32 in color(c) } }

    public static func rarity(_ s: String) -> BoxRarity { BoxRarity(rawValue: s) ?? .common }
}

public struct ArtifactDef: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var collection: String
    public var rarity: BoxRarity
    public var note: String
    public var symbol: String = ""
    public var edition: Int { ArtifactCatalog.edition(rarity) }
}

public struct CollectionLook: Equatable, Sendable {
    public var top: UInt32
    public var bottom: UInt32
    public var ink: UInt32
    public var motif: String
}

public struct ArtifactCollection: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var blurb: String
    public var rewardID: String
    public var members: [String]
    public var look: CollectionLook = CollectionLook(top: 0x9C957F, bottom: 0x45423A, ink: 0xF1ECDD, motif: "grid")
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

    public static let defs: [ArtifactDef] = ContentFile.load("artifacts", "artifacts")["artifacts"].array.map { (e: JSONValue) -> ArtifactDef in
        ArtifactDef(id: e["id"].string, name: e["name"].string, collection: e["collection"].string, rarity: ContentFile.rarity(e["rarity"].string),
                    note: e["note"].string, symbol: e["symbol"].string)
    }

    public static let collections: [ArtifactCollection] = ContentFile.load("artifacts", "artifacts")["collections"].array.map { (c: JSONValue) -> ArtifactCollection in
        let id: String = c["id"].string
        let l: JSONValue = c["look"]
        return ArtifactCollection(id: id, name: c["name"].string, blurb: c["blurb"].string, rewardID: c["reward"].string,
                                  members: ArtifactCatalog.defs.filter { (d: ArtifactDef) -> Bool in d.collection == id }.map { (d: ArtifactDef) -> String in d.id },
                                  look: CollectionLook(top: ContentFile.color(l["top"]), bottom: ContentFile.color(l["bottom"]), ink: ContentFile.color(l["ink"]), motif: l["motif"].string))
    }

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
