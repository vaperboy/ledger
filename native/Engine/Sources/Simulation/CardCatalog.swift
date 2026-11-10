import Foundation
import GameCore

public struct CardDef: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case profile, company
        public var title: String { self == .profile ? "Profile card" : "Company card" }
        var collection: String { self == .profile ? "profilecards" : "companycards" }
    }

    public enum Motion: String, Sendable {
        case none, shimmer, drift, pulse, aurora
    }

    public var id: String
    public var kind: Kind
    public var name: String
    public var rarity: BoxRarity
    public var colors: [UInt32]
    public var motion: Motion
    public var logo: String

    public var isAnimated: Bool { motion != .none }
}

public enum CardCatalog {
    public struct LevelReward: Equatable, Sendable {
        public var level: Int
        public var defID: String
    }

    private static func p(_ id: String, _ name: String, _ r: BoxRarity, _ colors: [UInt32], _ motion: CardDef.Motion = .none) -> CardDef {
        CardDef(id: "card.p." + id, kind: .profile, name: name, rarity: r, colors: colors, motion: motion, logo: "")
    }

    private static func c(_ id: String, _ name: String, _ r: BoxRarity, _ logo: String, _ colors: [UInt32], _ motion: CardDef.Motion = .none) -> CardDef {
        CardDef(id: "card.c." + id, kind: .company, name: name, rarity: r, colors: colors, motion: motion, logo: logo)
    }

    public static let all: [CardDef] = [
        p("slate", "Slate card", .common, [0x3A4350, 0x252B33]),
        p("olive", "Olive card", .common, [0x4B5640, 0x2B3226]),
        p("clay", "Clay card", .common, [0x6A4A3C, 0x3A281F]),
        p("ink", "Ink card", .common, [0x2E3A57, 0x1B2234]),
        p("twilight", "Twilight card", .rare, [0x5B4A7A, 0x2A2340]),
        p("harbour", "Harbour card", .rare, [0x2F6670, 0x173238]),
        p("ember", "Ember card", .rare, [0x9A5A34, 0x3F2210]),
        p("glass", "Northern glass", .epic, [0x2E7D6B, 0x3A2E7D], .shimmer),
        p("gilt", "Gilt edge", .epic, [0xC9A24A, 0x4A3812], .drift),
        p("aurora", "Aurora veil", .legendary, [0x43D9A8, 0x6A4BD6, 0x12202E], .aurora),
        p("flare", "Solar flare", .legendary, [0xF2B84B, 0xD1502F, 0x2A140C], .pulse),
        p("tide", "Midnight tide", .legendary, [0x3A6FD6, 0x0E1B3D], .drift),
        c("navy", "Navy card", .common, "briefcase.fill", [0x2F4A78, 0x17233D]),
        c("forest", "Forest card", .common, "leaf.fill", [0x3E6B4C, 0x1C3225]),
        c("burgundy", "Burgundy card", .common, "building.2.fill", [0x7A3340, 0x3A1620]),
        c("charcoal", "Charcoal card", .common, "gearshape.fill", [0x555A63, 0x25282D]),
        c("brass", "Brass card", .rare, "key.fill", [0xB89B6A, 0x4A3A1C]),
        c("teal", "Teal wave card", .rare, "water.waves", [0x2C8A8A, 0x123A3C]),
        c("copper", "Copper card", .rare, "hammer.fill", [0xC27C5A, 0x4A2616]),
        c("silver", "Silver leaf", .epic, "star.fill", [0xD9DEE6, 0x4A505C], .shimmer),
        c("violet", "Royal violet", .epic, "rosette", [0x8C6FD6, 0x2A1E4F], .drift),
        c("standard", "Gold standard", .legendary, "seal.fill", [0xF0CF73, 0x8A5A10, 0x2A1C06], .shimmer),
        c("skyline", "Neon skyline", .legendary, "building.2.fill", [0x4CE0D2, 0xD64BC4, 0x0E1224], .aurora),
        c("diamond", "Black diamond", .legendary, "diamond.fill", [0xB8C4E8, 0x1A1D2E], .pulse)
    ]

    public static let levelRewards: [LevelReward] = [
        LevelReward(level: 2, defID: "card.p.slate"),
        LevelReward(level: 4, defID: "card.c.navy"),
        LevelReward(level: 6, defID: "card.p.olive"),
        LevelReward(level: 9, defID: "card.c.forest"),
        LevelReward(level: 12, defID: "card.p.harbour"),
        LevelReward(level: 16, defID: "card.c.teal")
    ]

    public static func def(_ id: String) -> CardDef? { all.first { $0.id == id } }

    public static func defID(ofItem itemID: String) -> String {
        itemID.firstIndex(of: "#").map { String(itemID[itemID.startIndex..<$0]) } ?? itemID
    }

    public static func def(forItem itemID: String) -> CardDef? { def(defID(ofItem: itemID)) }

    public static func defs(_ kind: CardDef.Kind, _ rarity: BoxRarity) -> [CardDef] {
        all.filter { $0.kind == kind && $0.rarity == rarity }
    }

    public static func levelRewards(upTo level: Int) -> [LevelReward] { levelRewards.filter { $0.level <= level } }

    public static func artifactDef(_ id: String) -> ArtifactDef? {
        guard let d = def(id) else { return nil }
        return ArtifactDef(id: d.id, name: d.name, collection: d.kind.collection, rarity: d.rarity,
                           note: d.kind == .profile ? "A profile card for your profile page." : "A company card with its own colours and logo. One company wears it at a time.")
    }

    public static func item(_ d: CardDef, roll: Double) -> ArtifactItem {
        let a = ArtifactDef(id: d.id, name: d.name, collection: d.kind.collection, rarity: d.rarity, note: "")
        return ArtifactItem(defID: d.id, serial: ArtifactCatalog.serial(of: a, roll: roll))
    }

    public static func roll(_ key: String) -> Double {
        var rng = HashedRandom("card|" + key)
        return rng.next()
    }
}

public enum CompanyCards {
    static let key = "ccard"

    public enum Problem: Equatable, Sendable { case notACompanyCard, notOwned, noCompany }

    public static func assignments(_ s: GameState) -> [Int: String] {
        var out: [Int: String] = [:]
        for (k, v) in (s.rest[key] ?? .null).object {
            if let id = Int(k), !v.string.isEmpty { out[id] = v.string }
        }
        return out
    }

    public static func itemID(for companyID: Int, in s: GameState) -> String? { assignments(s)[companyID] }

    public static func companyUsing(_ itemID: String, in s: GameState) -> Int? {
        assignments(s).first { $0.value == itemID }?.key
    }

    public static func card(for companyID: Int, in s: GameState, cabinet: Cabinet) -> CardDef? {
        guard let item = itemID(for: companyID, in: s), cabinet.contains(item), let d = CardCatalog.def(forItem: item), d.kind == .company else { return nil }
        return d
    }

    @discardableResult
    public static func apply(_ s: inout GameState, itemID: String, companyID: Int, cabinet: Cabinet) -> Problem? {
        guard let d = CardCatalog.def(forItem: itemID), d.kind == .company else { return .notACompanyCard }
        guard cabinet.contains(itemID) else { return .notOwned }
        guard s.company(companyID) != nil else { return .noCompany }
        var map: [String: JSONValue] = (s.rest[key] ?? .null).object
        for (k, v) in map where v.string == itemID { map[k] = nil }
        map[String(companyID)] = .string(itemID)
        s.rest[key] = .object(map)
        return nil
    }

    public static func clear(_ s: inout GameState, companyID: Int) {
        var map: [String: JSONValue] = (s.rest[key] ?? .null).object
        guard map[String(companyID)] != nil else { return }
        map[String(companyID)] = nil
        s.rest[key] = .object(map)
    }
}

public extension GameEngine {
    @discardableResult
    mutating func applyCompanyCard(itemID: String, companyID: Int, cabinet: Cabinet) -> CompanyCards.Problem? {
        var problem: CompanyCards.Problem?
        update { s, _, _ in problem = CompanyCards.apply(&s, itemID: itemID, companyID: companyID, cabinet: cabinet) }
        return problem
    }

    mutating func clearCompanyCard(companyID: Int) {
        update { s, _, _ in CompanyCards.clear(&s, companyID: companyID) }
    }

    func companyCard(_ companyID: Int, cabinet: Cabinet) -> CardDef? { CompanyCards.card(for: companyID, in: state, cabinet: cabinet) }
    func companyCardAssignments() -> [Int: String] { CompanyCards.assignments(state) }
}
