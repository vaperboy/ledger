import SwiftUI
import Businesses
import Simulation
#if canImport(UIKit)
import UIKit
#endif

extension ArtLibrary {
    static func catalogueName(_ category: ArtCategory, _ id: String) -> String { "art." + category.rawValue + "." + id }

    #if canImport(UIKit)
    static func catalogueImage(_ category: ArtCategory, _ id: String) -> UIImage? {
        let key: NSString = (category.rawValue + "." + id) as NSString
        if let hit = catalogue.object(forKey: key) { return hit }
        if missing.object(forKey: key) != nil { return nil }
        let tier: UIImage? = category == .gold ? rewardTierStem(id).flatMap { (stem: String) -> UIImage? in droppedImage(stem) } : nil
        guard let img = UIImage(named: catalogueName(category, id)) ?? droppedImage(category.rawValue + "." + id) ?? tier else {
            missing.setObject(NSNumber(value: true), forKey: key)
            return nil
        }
        catalogue.setObject(img, forKey: key)
        return img
    }

    /// Season gold and XP rewards without their own picture share one by size: a coin pile or a star.
    static func rewardTierStem(_ id: String) -> String? {
        guard let r = SeasonRewards.item(id), r.amount > 0 else { return nil }
        if r.kind == .xp { return "reward.xp." + (r.amount >= 250 ? "250" : "200") }
        guard r.kind == .gold else { return nil }
        let tiers: [Int] = [12, 18, 24, 40, 55]
        let best: Int = tiers.min { (a: Int, b: Int) -> Bool in abs(a - r.amount) < abs(b - r.amount) } ?? 12
        return "reward.gold.\(best)"
    }

    private static let catalogue = NSCache<NSString, UIImage>()
    private static let dropped = NSCache<NSString, UIImage>()
    /// Names already looked up and not found, so emblems do not hit the file system on every redraw.
    private static let missing = NSCache<NSString, NSNumber>()

    static func droppedImage(_ name: String) -> UIImage? {
        let key: NSString = name as NSString
        if let hit = dropped.object(forKey: key) { return hit }
        if missing.object(forKey: ("file." + name) as NSString) != nil { return nil }
        guard !name.isEmpty, let root = Bundle.main.resourcePath, let raw = UIImage(contentsOfFile: root + "/Content/art/" + name + ".png") else {
            missing.setObject(NSNumber(value: true), forKey: ("file." + name) as NSString)
            return nil
        }
        // Decoded once here and kept, instead of being decoded again on the main thread each time it is drawn.
        let img: UIImage = raw.preparingForDisplay() ?? raw
        dropped.setObject(img, forKey: key)
        return img
    }
    #endif
}

struct ItemArt: View {
    var category: ArtCategory
    var id: String
    var rarity: BoxRarity? = nil
    var colors: [UInt32] = []
    var size: CGFloat = 44
    var wide: Bool = false
    var shape: EmblemShape? = nil

    init(category: ArtCategory, id: String, rarity: BoxRarity? = nil, colors: [UInt32] = [], size: CGFloat = 44, wide: Bool = false, shape: EmblemShape? = nil) {
        self.category = category; self.id = id; self.rarity = rarity; self.colors = colors; self.size = size; self.wide = wide; self.shape = shape
    }

    init(trade id: String, size: CGFloat = 44, shape: EmblemShape? = nil) {
        self.init(category: .trade, id: id, size: size, shape: shape)
    }

    init(artifact def: ArtifactDef, size: CGFloat = 44) {
        self.init(category: .artifact, id: def.id, rarity: def.rarity, size: size)
    }

    init(box kind: BoxKind, size: CGFloat = 44) {
        let r: BoxRarity = kind == .grand || kind == .cardElite ? .epic : (kind == .cabinet || kind == .cardPremium ? .rare : .common)
        self.init(category: .box, id: kind.rawValue, rarity: r, size: size)
    }

    init(reward r: SeasonReward, rarity: BoxRarity? = nil, size: CGFloat = 44, wide: Bool = false) {
        self.init(category: ItemArt.category(of: r), id: r.id, rarity: rarity ?? r.rarity ?? (r.premium ? .rare : nil), colors: r.colors, size: size, wide: wide)
    }

    init(cosmetic c: GoldCosmetic, size: CGFloat = 44, wide: Bool = false) {
        self.init(reward: c.item, rarity: c.rarity, size: size, wide: wide)
    }

    init(avatar id: String, size: CGFloat = 44) {
        let def: AvatarDef? = AvatarCatalog.def(id)
        self.init(category: .avatar, id: id, rarity: def?.tier, size: size, shape: .round)
    }

    static func category(of r: SeasonReward) -> ArtCategory {
        switch r.kind {
        case .badge: return .badge
        case .theme: return .theme
        case .namePlate: return .namePlate
        case .backdrop: return .backdrop
        case .saveSlot: return .saveSlot
        case .advisorLine: return .advisor
        case .richListFlair: return .flair
        case .tradePlate: return .tradePlate
        case .outfit: return .outfit
        case .face: return .face
        case .hair: return .hair
        case .skin: return .skin
        case .box: return .box
        case .profileCard, .companyCard, .artifact: return .artifact
        case .gold, .xp: return .gold
        }
    }

    /// Legendary loops play only from this size up (card, preview, reveal); small thumbnails stay still.
    static let loopMinSize: CGFloat = 120

    var hasArt: Bool { EmblemCatalog.spec(category: category, id: id, colors: colors) != nil || supplied != nil }

    private var resolved: EmblemSpec? {
        guard var spec = EmblemCatalog.spec(category: category, id: id, colors: colors) ?? (supplied != nil ? EmblemCatalog.neutral : nil) else { return nil }
        if let s = shape { spec.shape = s }
        return spec
    }

    var body: some View {
        if let spec = resolved {
            EmblemView(spec: spec, frame: EmblemFrame(rarity), size: size, wide: wide, picture: supplied)
                .overlay { if size >= ItemArt.loopMinSize { AnimatedClip(category: category, id: id, fill: category == .backdrop) } }
        }
    }

    private var supplied: Image? {
        #if canImport(UIKit)
        if let ui = ArtLibrary.catalogueImage(category, id) { return Image(uiImage: ui) }
        #endif
        return nil
    }
}

enum ArtAsset {
    #if canImport(UIKit)
    static func uiImage(_ name: String) -> UIImage? {
        guard !name.isEmpty else { return nil }
        return UIImage(named: name) ?? ArtLibrary.droppedImage(name)
    }
    #endif

    static func exists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return uiImage(name) != nil
        #else
        return false
        #endif
    }

    /// The picture of an equipment item. Ids shared by several trades can point at a better picture for one trade ("trade.id").
    static func equipment(_ id: String, trade: String = "") -> String {
        "equipment." + (equipmentAlias[trade + "." + id] ?? equipmentAlias[id] ?? id)
    }

    /// Items whose own picture shows something else: the existing picture that fits.
    private static let equipmentAlias: [String: String] = [
        "kit": "kitch", "tbar": "ilift", "ilift": "tbar", "pay": "sw",
        "skires.chair": "tbar", "photo.cam": "photo", "laundry.wash": "laun", "laundry.dry": "laun",
        "trucking.truck": "dtruck", "wholesale.truck": "dtruck", "electrician.lift": "lad", "mktg.tools": "crm",
    ]

    static func cellFallback(_ equipmentID: String, group: String, seed: String) -> String {
        exists(equipment(equipmentID)) ? "" : (ArtLibrary.itemKey(group: group, familyKey: equipmentID, seed: seed) ?? "")
    }
}

private struct EquipmentTradeKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    /// The trade of the company whose equipment is listed, for trade-specific equipment pictures.
    var equipmentTrade: String {
        get { self[EquipmentTradeKey.self] }
        set { self[EquipmentTradeKey.self] = newValue }
    }
}

struct SlotImage: View {
    var asset: String
    var glyph: String
    var size: CGFloat = 36

    private var slotPicture: Image? {
        #if canImport(UIKit)
        if let ui = ArtAsset.uiImage(asset) { return Image(uiImage: ui) }
        #endif
        return nil
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            if let picture = slotPicture {
                picture.resizable().scaledToFill().frame(width: size, height: size).clipShape(shape)
            } else {
                shape.fill(Theme.inkFaint.opacity(0.14))
                LedgerGlyph(glyph: glyph, size: size * 0.5, tint: Theme.inkFaint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct LogoBadge: View {
    var logoID: String
    var size: CGFloat = 36
    var glyph: String = Glyph.home

    var body: some View {
        SlotImage(asset: LogoCatalogue.logo(logoID)?.asset ?? "", glyph: glyph, size: size)
    }
}
