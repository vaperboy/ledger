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
        UIImage(named: catalogueName(category, id))
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
        let r: BoxRarity = kind == .grand ? .epic : (kind == .cabinet ? .rare : .common)
        self.init(category: .box, id: kind.rawValue, rarity: r, size: size)
    }

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

enum ArtAsset {
    static func exists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return !name.isEmpty && UIImage(named: name) != nil
        #else
        return false
        #endif
    }

    static func equipment(_ id: String) -> String { "equipment." + id }
}

struct SlotImage: View {
    var asset: String
    var glyph: String
    var size: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            if ArtAsset.exists(asset) {
                Image(asset).resizable().scaledToFill().frame(width: size, height: size).clipShape(shape)
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
