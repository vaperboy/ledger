import SwiftUI
import Simulation
#if canImport(UIKit)
import UIKit
#endif

/// Supplied pictures for the drawn art. An image set named `art.<category>.<id>` in `Assets.xcassets/Art` (for example `art.trade.cafe`,
/// `art.artifact.compass`, `art.avatar.av.briefcase`) replaces the drawn emblem for that id; nothing else needs to change. Ids are the
/// engine ids (trade ids, artifact ids, cosmetic and reward ids, `BoxKind` raw values, avatar ids). `native/tools/add_art.py` makes the image set.
extension ArtLibrary {
    static func catalogueName(_ category: ArtCategory, _ id: String) -> String { "art." + category.rawValue + "." + id }

    #if canImport(UIKit)
    static func catalogueImage(_ category: ArtCategory, _ id: String) -> UIImage? {
        UIImage(named: catalogueName(category, id))
    }
    #endif
}

/// The art of one thing, by category and id: a supplied picture when the asset catalogue has one, else the drawn emblem. The rarity gives
/// the frame. `size` is the height; plates and backdrops are drawn as squares unless `wide` is set.
struct ItemArt: View {
    var category: ArtCategory
    var id: String
    var rarity: BoxRarity? = nil
    var colors: [UInt32] = []
    var size: CGFloat = 44
    var wide: Bool = false
    /// Forces a shape (a round slot for a trade, for instance).
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
        let r: BoxRarity = kind == .grand ? .epic : (kind == .cabinet ? .rare : .common)
        self.init(category: .box, id: kind.rawValue, rarity: r, size: size)
    }

    /// A season reward or store cosmetic. `rarity` is the frame; a Plus-track reward with none given gets the rare frame.
    init(reward r: SeasonReward, rarity: BoxRarity? = nil, size: CGFloat = 44, wide: Bool = false) {
        self.init(category: ItemArt.category(of: r), id: r.id, rarity: rarity ?? (r.premium ? .rare : nil), colors: r.colors, size: size, wide: wide)
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
        case .box: return .box
        case .gold: return .gold
        }
    }

    /// True when there is art for this id (always, except a trade the game does not know).
    var hasArt: Bool { EmblemCatalog.spec(category: category, id: id, colors: colors) != nil }

    private var resolved: EmblemSpec? {
        guard var spec = EmblemCatalog.spec(category: category, id: id, colors: colors) else { return nil }
        if let s = shape { spec.shape = s }
        return spec
    }

    var body: some View {
        if let spec = resolved {
            EmblemView(spec: spec, frame: EmblemFrame(rarity), size: size, wide: wide, picture: supplied)
        }
    }

    private var supplied: Image? {
        #if canImport(UIKit)
        if let ui = ArtLibrary.catalogueImage(category, id) { return Image(uiImage: ui) }
        #endif
        return nil
    }
}
