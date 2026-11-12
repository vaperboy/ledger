import SwiftUI
import Simulation

/// The half-body avatar a player builds: a face, a hair style and colour, and an outfit.
struct AvatarLook: Equatable, Hashable, Sendable {
    var face: Int = 0
    var hair: Int = 0
    var hairColour: Int = 0
    var outfit: String = AvatarParts.outfits[0].id

    /// Short text form stored with the profile, for example "3,2,5,blazer".
    var code: String { "\(face),\(hair),\(hairColour),\(outfit)" }

    init(face: Int = 0, hair: Int = 0, hairColour: Int = 0, outfit: String = AvatarParts.outfits[0].id) {
        self.face = AvatarParts.clamp(face, AvatarParts.faces.count)
        self.hair = AvatarParts.clamp(hair, AvatarParts.hairStyles.count)
        self.hairColour = AvatarParts.clamp(hairColour, AvatarParts.hairColours.count)
        self.outfit = AvatarParts.outfit(outfit) == nil ? AvatarParts.outfits[0].id : outfit
    }

    init?(code: String) {
        let parts: [Substring] = code.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4, let f = Int(parts[0]), let h = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        self.init(face: f, hair: h, hairColour: c, outfit: String(parts[3]))
    }

    /// A stable look for players who have not made one (rivals, older profiles).
    static func generated(for name: String) -> AvatarLook {
        let h: Int = EmblemCatalog.hash("look" + name)
        return AvatarLook(face: h % AvatarParts.faces.count,
                          hair: (h / 11) % AvatarParts.hairStyles.count,
                          hairColour: (h / 101) % AvatarParts.hairColours.count,
                          outfit: AvatarParts.freeOutfits[(h / 1009) % AvatarParts.freeOutfits.count].id)
    }
}

struct FaceDef: Identifiable, Equatable {
    var id: Int
    var title: String
    var skin: UInt32
    var variant: Int
}

struct HairStyleDef: Identifiable, Equatable {
    var id: Int
    var key: String
    var title: String
}

struct OutfitDef: Identifiable, Equatable {
    var id: String
    var title: String
    var main: UInt32
    var trim: UInt32
    var level: Int
    var isFree: Bool { level <= 1 }
}

/// Every choice the avatar builder offers.
/// Art slots (all optional, placeholders are drawn when missing):
///   avatar.body.<outfit id>      shoulders and outfit, full canvas
///   avatar.face.<n>              face with skin, eyes and mouth, full canvas
///   avatar.hair.<key>            front hair, white or grey so it can be tinted
///   avatar.hair.<key>.back       hair behind the head and shoulders, tinted the same way
/// Every layer is the same square-ish canvas (width 1, height 1.1) so they stack without offsets.
enum AvatarParts {
    static let faces: [FaceDef] = [
        FaceDef(id: 0, title: "Calm", skin: 0xF1D2B5, variant: 0), FaceDef(id: 1, title: "Friendly", skin: 0xE0B48E, variant: 0),
        FaceDef(id: 2, title: "Warm", skin: 0xC68E63, variant: 0), FaceDef(id: 3, title: "Bright", skin: 0x8D5A3C, variant: 0),
        FaceDef(id: 4, title: "Sharp", skin: 0xF1D2B5, variant: 1), FaceDef(id: 5, title: "Bold", skin: 0xE0B48E, variant: 1),
        FaceDef(id: 6, title: "Wry", skin: 0xC68E63, variant: 1), FaceDef(id: 7, title: "Kind", skin: 0x8D5A3C, variant: 1)
    ]

    static let hairStyles: [HairStyleDef] = [
        HairStyleDef(id: 0, key: "short", title: "Short"), HairStyleDef(id: 1, key: "side", title: "Side part"),
        HairStyleDef(id: 2, key: "buzz", title: "Buzz"), HairStyleDef(id: 3, key: "long", title: "Long"),
        HairStyleDef(id: 4, key: "bun", title: "Bun"), HairStyleDef(id: 5, key: "curly", title: "Curly"),
        HairStyleDef(id: 6, key: "tail", title: "Ponytail"), HairStyleDef(id: 7, key: "bald", title: "None")
    ]

    static let hairColours: [UInt32] = [0x1E1B1A, 0x4A3426, 0x7A4B2A, 0xD9B96C, 0xB5532C, 0x9A9A9A, 0xE8E4DC, 0x3C8C84]

    static let outfits: [OutfitDef] = [
        OutfitDef(id: "shirt", title: "Shirt", main: 0x6F8FB5, trim: 0xF1EBDD, level: 1),
        OutfitDef(id: "polo", title: "Polo", main: 0x5E8C74, trim: 0xE6E0D0, level: 1),
        OutfitDef(id: "hoodie", title: "Hoodie", main: 0x6B6F78, trim: 0x4B4E55, level: 1),
        OutfitDef(id: "blazer", title: "Blazer", main: 0x3B4252, trim: 0xF1EBDD, level: 1),
        OutfitDef(id: "suit", title: "Suit and tie", main: 0x2B2F3A, trim: 0xB5453A, level: 5),
        OutfitDef(id: "turtleneck", title: "Turtleneck", main: 0x2E2A28, trim: 0x4A4440, level: 10),
        OutfitDef(id: "vest", title: "Waistcoat", main: 0x7A4B2A, trim: 0xE6E0D0, level: 15),
        OutfitDef(id: "tux", title: "Dinner jacket", main: 0x16171A, trim: 0xD6B889, level: 25)
    ]

    static var freeOutfits: [OutfitDef] { outfits.filter { $0.isFree } }

    static func outfit(_ id: String) -> OutfitDef? { outfits.first { $0.id == id } }

    static func clamp(_ n: Int, _ count: Int) -> Int { max(0, min(count - 1, n)) }

    static func hairColour(_ i: Int) -> Color { Color(hex: hairColours[clamp(i, hairColours.count)]) }
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
