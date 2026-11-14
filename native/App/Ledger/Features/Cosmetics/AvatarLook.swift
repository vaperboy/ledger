import SwiftUI
import Simulation

/// The half-body avatar a player builds: a face, a skin tone, a hair style and colour, and an outfit. Every choice is an item of the cosmetics
/// catalogue (`outfit.<key>`, `face.<n>`, `hair.<key>`, `skin.<key>`); the look stores the short key.
struct AvatarLook: Equatable, Hashable, Sendable {
    var face: Int = 0
    var hair: String = "short"
    var hairColour: Int = 0
    var outfit: String = AvatarParts.defaultOutfit
    /// Skin tone key (the id without "skin."), or empty to keep the skin the chosen face is drawn with.
    var skin: String = ""

    /// Short text form stored with the profile, for example "3,2,5,blazer". The first eight hair styles keep their old number so codes made
    /// before the catalogue still decode; other styles are written by key. A chosen skin tone is a fifth part ("3,2,5,blazer,olive").
    var code: String {
        let h: String = AvatarParts.legacyHair.firstIndex(of: hair).map { (i: Int) -> String in String(i) } ?? hair
        return "\(face),\(h),\(hairColour),\(outfit)" + (skin.isEmpty ? "" : ",\(skin)")
    }

    init(face: Int = 0, hair: String = "short", hairColour: Int = 0, outfit: String = AvatarParts.defaultOutfit, skin: String = "") {
        self.face = AvatarParts.face(face) == nil ? 0 : face
        self.hair = AvatarParts.hair(hair) == nil ? "short" : hair
        self.hairColour = AvatarParts.clamp(hairColour, AvatarParts.hairColours.count)
        self.outfit = AvatarParts.outfit(outfit) == nil ? AvatarParts.defaultOutfit : outfit
        self.skin = AvatarParts.skin(skin) == nil ? "" : skin
    }

    init?(code: String) {
        let parts: [Substring] = code.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 || parts.count == 5, let f = Int(parts[0]), let c = Int(parts[2]) else { return nil }
        let hairKey: String = Int(parts[1]).map { (i: Int) -> String in AvatarParts.legacyHair[AvatarParts.clamp(i, AvatarParts.legacyHair.count)] } ?? String(parts[1])
        var tone: String = ""
        if parts.count == 5, Int(parts[4]) == nil { tone = String(parts[4]) }
        self.init(face: f, hair: hairKey, hairColour: c, outfit: String(parts[3]), skin: tone)
    }

    /// A stable look for players who have not made one (rivals, older profiles), from the free faces, hair styles and outfits.
    static func generated(for name: String) -> AvatarLook {
        let h: Int = EmblemCatalog.hash("look" + name)
        let faces: [FaceDef] = AvatarParts.faces.filter { (f: FaceDef) -> Bool in AvatarParts.isFree(f.itemID) }
        let hairs: [HairStyleDef] = AvatarParts.hairStyles.filter { (x: HairStyleDef) -> Bool in AvatarParts.isFree(x.itemID) }
        let outfits: [OutfitDef] = AvatarParts.outfits.filter { (o: OutfitDef) -> Bool in AvatarParts.isFree(o.itemID) }
        return AvatarLook(face: faces.isEmpty ? 0 : faces[h % faces.count].id,
                          hair: hairs.isEmpty ? "short" : hairs[(h / 11) % hairs.count].id,
                          hairColour: (h / 101) % AvatarParts.hairColours.count,
                          outfit: outfits.isEmpty ? AvatarParts.defaultOutfit : outfits[(h / 1009) % outfits.count].id)
    }
}

struct FaceDef: Identifiable, Equatable {
    var id: Int
    var itemID: String
    var title: String
    var rarity: BoxRarity
    /// Placeholder drawing only: the skin the face is drawn with and its look.
    var skin: UInt32
    var variant: Int
}

struct HairStyleDef: Identifiable, Equatable {
    /// The key, the item id without "hair.".
    var id: String
    var itemID: String
    var title: String
    var rarity: BoxRarity
}

struct SkinDef: Identifiable, Equatable {
    var id: String
    var itemID: String
    var title: String
    var rarity: BoxRarity
    var colour: UInt32
}

struct OutfitDef: Identifiable, Equatable {
    /// The key, the item id without "outfit.".
    var id: String
    var itemID: String
    var title: String
    var rarity: BoxRarity
    var main: UInt32
    var trim: UInt32
}

/// Every choice the avatar builder offers, read from the cosmetics catalogue (`cosmetics/gold_cosmetics.json` and the season files).
/// Art slots (all optional, placeholders are drawn when missing):
///   avatar.body.<outfit key>     shoulders and outfit, full canvas
///   avatar.face.<n>              face with eyes and mouth, full canvas
///   avatar.skin.<tone key>       optional: head, ears and neck in that skin tone, drawn under avatar.face.<n> (which then keeps its skin
///                                areas transparent); without it a chosen tone recolours the drawn placeholder only
///   avatar.hair.<key>            front hair, white or grey so it can be tinted
///   avatar.hair.<key>.back       hair behind the head and shoulders, tinted the same way
/// Every layer is the same square-ish canvas (width 1, height 1.1) so they stack without offsets.
enum AvatarParts {
    static let defaultOutfit = "shirt"
    /// The first hair styles, in the order old look codes numbered them.
    static let legacyHair: [String] = ["short", "side", "buzz", "long", "bun", "curly", "tail", "bald"]

    private static let rows: [SeasonReward] = GoldCosmetics.everything.map { (c: GoldCosmetic) -> SeasonReward in c.item } + SeasonRewards.everything

    private static func list(_ kind: SeasonReward.Kind) -> [SeasonReward] {
        var seen = Set<String>()
        return rows.filter { (r: SeasonReward) -> Bool in r.kind == kind && seen.insert(r.id).inserted }
    }

    private static func key(_ id: String, _ prefix: String) -> String { id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id }

    private static func rarity(_ r: SeasonReward) -> BoxRarity { r.rarity ?? GoldCosmetics.cosmetic(r.id)?.rarity ?? .common }

    private static func order(_ a: BoxRarity, _ b: BoxRarity, _ x: String, _ y: String) -> Bool { a == b ? x < y : a < b }

    private static let faceSkins: [UInt32] = [0xF1D2B5, 0xE0B48E, 0xC68E63, 0x8D5A3C]

    static let faces: [FaceDef] = list(.face).compactMap { (r: SeasonReward) -> FaceDef? in
        guard let n = Int(key(r.id, "face.")) else { return nil }
        return FaceDef(id: n, itemID: r.id, title: r.title, rarity: rarity(r), skin: faceSkins[n % faceSkins.count], variant: (n / 4) % 2)
    }.sorted { (a: FaceDef, b: FaceDef) -> Bool in a.id < b.id }

    static let hairStyles: [HairStyleDef] = list(.hair).map { (r: SeasonReward) -> HairStyleDef in
        HairStyleDef(id: key(r.id, "hair."), itemID: r.id, title: r.title, rarity: rarity(r))
    }.sorted { (a: HairStyleDef, b: HairStyleDef) -> Bool in order(a.rarity, b.rarity, a.title, b.title) }

    static let skins: [SkinDef] = list(.skin).map { (r: SeasonReward) -> SkinDef in
        SkinDef(id: key(r.id, "skin."), itemID: r.id, title: r.title, rarity: rarity(r), colour: r.colors.first ?? 0xE0B48E)
    }

    static let outfits: [OutfitDef] = list(.outfit).map { (r: SeasonReward) -> OutfitDef in
        OutfitDef(id: key(r.id, "outfit."), itemID: r.id, title: r.title, rarity: rarity(r),
                  main: r.colors.first ?? 0x6B6F78, trim: r.colors.count > 1 ? r.colors[1] : 0xE6E0D0)
    }.sorted { (a: OutfitDef, b: OutfitDef) -> Bool in order(a.rarity, b.rarity, a.title, b.title) }

    static let hairColours: [UInt32] = [0x1E1B1A, 0x4A3426, 0x7A4B2A, 0xD9B96C, 0xB5532C, 0x9A9A9A, 0xE8E4DC, 0x3C8C84]

    static func face(_ n: Int) -> FaceDef? { faces.first { $0.id == n } }
    static func hair(_ key: String) -> HairStyleDef? { hairStyles.first { $0.id == key } }
    static func skin(_ key: String) -> SkinDef? { skins.first { $0.id == key } }
    static func outfit(_ key: String) -> OutfitDef? { outfits.first { $0.id == key } }

    /// Items given to every player from the start.
    static func isFree(_ itemID: String) -> Bool { GoldCosmetics.cosmetic(itemID)?.source == .free }

    /// Item ids a player can see today (nothing of a season that has not started).
    static func shown() -> Set<String> { Set(CosmeticCatalog.entries().map { (e: CatalogEntry) -> String in e.id }) }

    static func clamp(_ n: Int, _ count: Int) -> Int { max(0, min(count - 1, n)) }

    static func hairColour(_ i: Int) -> Color { Color(hex: hairColours[clamp(i, hairColours.count)]) }
}

/// Which avatar items the player has. Free items, level, rank and career-goal outfits count once earned; the rest once bought, won or claimed.
@MainActor
struct AvatarOwnership {
    private let owned: Set<String>

    init() {
        let m: AvatarModel = AvatarModel.shared
        let earned: Set<String> = CosmeticCatalog.earned(level: m.bestLevel, bestRank: m.bestRank, goalRewards: Array(m.earnedBadges))
        owned = earned.union(SeasonModel.shared.pass.owned).union(LevelRewards.outfits(upTo: m.bestLevel))
    }

    func owns(_ itemID: String) -> Bool { owned.contains(itemID) }

    /// Where an item comes from, for the note on a locked tile.
    static func how(_ itemID: String) -> String {
        CosmeticCatalog.entries().first { (e: CatalogEntry) -> Bool in e.id == itemID }?.drop ?? "Not available yet"
    }
}

/// What a player shows on their card besides the avatar: worn items by kind and chosen badges.
/// Text form is stored with the profile so other players see it.
struct ProfileLookCode {
    static let keys: [(kind: String, short: String)] = [("backdrop", "bd"), ("namePlate", "np"), ("richListFlair", "fl"), ("theme", "fr"), ("profileCard", "pc")]

    static func encode(avatar: AvatarLook, worn: [String: String], badges: [String]) -> String {
        var parts: [String] = [avatar.code]
        for k in keys {
            guard let id = worn[k.kind], !id.isEmpty else { continue }
            let shareable: String = k.kind == "profileCard" ? CardCatalog.defID(ofItem: id) : id
            if isSafe(shareable) { parts.append(k.short + "=" + shareable) }
        }
        let safe: [String] = badges.filter { isSafe($0) }.prefix(3).map { $0 }
        if !safe.isEmpty { parts.append("bg=" + safe.joined(separator: ",")) }
        return parts.joined(separator: "|")
    }

    static func decode(_ text: String?) -> (avatar: AvatarLook, worn: [String: String], badges: [String])? {
        guard let text, !text.isEmpty else { return nil }
        let segments: [Substring] = text.split(separator: "|", omittingEmptySubsequences: true)
        guard let first = segments.first, let avatar = AvatarLook(code: String(first)) else { return nil }
        var worn: [String: String] = [:]
        var badges: [String] = []
        for seg in segments.dropFirst() {
            let kv: [Substring] = seg.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard kv.count == 2 else { continue }
            let key: String = String(kv[0])
            let value: String = String(kv[1])
            if key == "bg" { badges = value.split(separator: ",").map { String($0) } }
            else { for k in keys where k.short == key { worn[k.kind] = value } }
        }
        return (avatar, worn, badges)
    }

    /// Server text allows lower-case letters, digits and . _ - only.
    private static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 40 && id.unicodeScalars.allSatisfy { (s: Unicode.Scalar) -> Bool in
            (s.value >= 97 && s.value <= 122) || (s.value >= 48 && s.value <= 57) || s == "." || s == "_" || s == "-"
        }
    }
}
