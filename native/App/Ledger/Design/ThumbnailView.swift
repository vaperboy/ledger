import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum ThumbKind: String, CaseIterable {
    case premises
    case person
    case trade
    case luxury
    case premisesPhoto
    case logo
    case trophy

    var fallbackGlyph: String {
        switch self {
        case .premises: return Glyph.home
        case .person: return Glyph.person
        case .trade: return Glyph.group
        case .luxury: return Glyph.luxury
        case .premisesPhoto: return Glyph.home
        case .logo: return Glyph.group
        case .trophy: return Glyph.achievements
        }
    }
}

enum ThumbShape {
    case round
    case square
    case wide
}

struct ThumbSpec {
    var kind: ThumbKind
    var key: String
    var glyph: String? = nil
    var initials: String? = nil
    var shape: ThumbShape = .round
    var face: String? = nil
}

struct ThumbnailView: View {
    var kind: ThumbKind
    var key: String
    var size: CGFloat = 40
    var shape: ThumbShape = .round
    var glyph: String? = nil
    var initials: String? = nil
    var tint: Color = Theme.gold
    var face: String? = nil

    init(kind: ThumbKind, key: String, size: CGFloat = 40, shape: ThumbShape = .round, glyph: String? = nil, initials: String? = nil, tint: Color = Theme.gold,
         face: String? = nil) {
        self.kind = kind; self.key = key; self.size = size; self.shape = shape
        self.glyph = glyph; self.initials = initials; self.tint = tint
        self.face = face
    }

    init(_ spec: ThumbSpec, size: CGFloat = 40, tint: Color = Theme.gold) {
        self.init(kind: spec.kind, key: spec.key, size: size, shape: spec.shape, glyph: spec.glyph, initials: spec.initials, tint: tint, face: spec.face)
    }

    private var corner: CGFloat { max(6, size * 0.22) }

    private var slotWidth: CGFloat { shape == .wide ? (size * 16 / 9).rounded() : size }

    var body: some View {
        slot.frame(width: slotWidth, height: size).accessibilityHidden(true)
    }

    private var facePicture: CGImage? { kind == .person ? FaceSheet.image(face) : nil }

    @ViewBuilder private var slot: some View {
        if let cg = facePicture {
            let image = Image(decorative: cg, scale: 1).resizable().interpolation(.high).aspectRatio(1, contentMode: .fill).frame(width: size, height: size).clipped()
            image.clipShape(Circle()).overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
        } else {
            artSlot
        }
    }

    @ViewBuilder private var artSlot: some View {
        #if canImport(UIKit)
        if let ui = picture {
            pictureView(ui)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    #if canImport(UIKit)
    private var picture: UIImage? {
        switch kind {
        case .premises, .person, .trade:
            return nil
        case .luxury:
            return ArtLibrary.luxuryImage(itemID: key)
        case .premisesPhoto:
            if key.hasPrefix("items:") { return ArtLibrary.image(.items, String(key.dropFirst(6))) }
            return ArtLibrary.premisesImage(key)
        case .logo:
            if let own = ArtLibrary.droppedImage("logo." + key) { return own }
            return ArtLibrary.logoKey(for: key).flatMap { ArtLibrary.image(.logos, $0) }
        case .trophy:
            return ArtLibrary.image(.trophies, key)
        }
    }
    #endif

    #if canImport(UIKit)
    @ViewBuilder private func pictureView(_ ui: UIImage) -> some View {
        let image = Image(uiImage: ui).resizable().interpolation(.high).scaledToFill().frame(width: slotWidth, height: size).clipped()
        if shape == .round {
            image.clipShape(Circle()).overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
        } else {
            let box = RoundedRectangle(cornerRadius: corner, style: .continuous)
            image.clipShape(box).overlay(box.strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
    }
    #endif

    @ViewBuilder private var placeholder: some View {
        if kind == .trade && EmblemCatalog.hasTrade(key) {
            ItemArt(trade: key, size: size, shape: shape == .round ? .round : .tile)
        } else if shape == .round {
            if kind == .person || kind == .logo, let initials, !initials.isEmpty {
                TeamInitials(name: initials, size: size)
            } else {
                IconCircle(glyph: glyph ?? kind.fallbackGlyph, size: size, tint: tint)
            }
        } else {
            let box = RoundedRectangle(cornerRadius: corner, style: .continuous)
            squareFallback
                .frame(width: slotWidth, height: size)
                .overlay(box.strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
    }

    @ViewBuilder private var squareFallback: some View {
        if kind == .logo, let initials, !initials.isEmpty {
            Text(ArtLibrary.initials(initials)).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(tint)
        } else {
            GlyphView(glyph: glyph ?? kind.fallbackGlyph, size: size * 0.5, weight: 1.5, tint: tint)
        }
    }
}
