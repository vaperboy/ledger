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
    public var theme: String = ItemThemes.classicID
    public var founderEdition: Bool = false

    public var isAnimated: Bool { motion != .none }
}

public enum CardCatalog {
    public struct LevelReward: Equatable, Sendable {
        public var level: Int
        public var defID: String
    }

    private static let file: JSONValue = ContentFile.load("cards", "cards")

    /// Every card, including those of seasons that have not started. For lookups of ids only.
    public static let everything: [CardDef] = CardCatalog.file["cards"].array.map { (e: JSONValue) -> CardDef in
        CardDef(id: e["id"].string, kind: e["kind"].string == "company" ? .company : .profile, name: e["name"].string, rarity: ContentFile.rarity(e["rarity"].string),
                colors: ContentFile.colors(e["colors"]), motion: CardDef.Motion(rawValue: e["motion"].string) ?? .none, logo: e["logo"].string,
                theme: ItemThemes.id(e), founderEdition: e["founderEdition"].bool)
    }

    public static let levelRewards: [LevelReward] = CardCatalog.file["levelRewards"].array.map { (e: JSONValue) -> LevelReward in
        LevelReward(level: e["level"].int, defID: e["card"].string)
    }

    /// The cards a player can see today.
    public static var all: [CardDef] { visible() }

    public static func visible(today: Int = SeasonCatalog.today()) -> [CardDef] {
        let hidden: Set<String> = SeasonCatalog.hiddenThemes(today: today)
        return everything.filter { !hidden.contains($0.theme) }
    }

    public static func def(_ id: String) -> CardDef? { everything.first { $0.id == id } }

    public static func defID(ofItem itemID: String) -> String {
        itemID.firstIndex(of: "#").map { String(itemID[itemID.startIndex..<$0]) } ?? itemID
    }

    public static func def(forItem itemID: String) -> CardDef? { def(defID(ofItem: itemID)) }

    public static func defs(_ kind: CardDef.Kind, _ rarity: BoxRarity, today: Int = SeasonCatalog.today()) -> [CardDef] {
        visible(today: today).filter { $0.kind == kind && $0.rarity == rarity }
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
