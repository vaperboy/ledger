import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The four families of things that can carry a picture. The raw value is the middle part of the asset name:
/// `thumb-<kind>-<key>` (see Assets.xcassets/Thumbs/README.md for the keys the game has).
enum ThumbKind: String, CaseIterable {
    case premises
    case person
    case trade
    case luxury
    /// A 16:9 photo of premises from the premises sheet; the key is a cell id from `ArtLibrary.premisesKey`.
    case premisesPhoto
    /// A firm's logo from the logos sheet; the key is a firm key such as `group|g12` (see `ArtLibrary.logoKey`).
    case logo
    /// A trophy, badge or award from the trophies sheet; the key is a cell id from `ArtLibrary.trophyKey` or `awardKey`.
    case trophy

    /// The icon shown while no picture has been supplied.
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
    /// 16:9: `size` is the height, the width is size x 16/9 (premises photos).
    case wide
}

/// What a row needs to say to get a thumbnail, so shared rows (CardRow) can take one as a single value.
struct ThumbSpec {
    var kind: ThumbKind
    var key: String
    /// Replaces the kind's default icon while no picture exists.
    var glyph: String? = nil
    /// People only: the name whose initials fill the circle while no picture exists.
    var initials: String? = nil
    var shape: ThumbShape = .round
    /// Employees only: the portrait key the engine gave the person (`Person.faceKey`, see Design/FaceSheet.swift).
    var face: String? = nil
}

/// One picture slot for a premises, a person (by role), a trade (company) or a luxury item. If the asset catalogue holds
/// `thumb-<kind>-<key>` the picture fills the slot; otherwise the slot shows the house icon circle (or the person's initials), so nothing
/// changes before art arrives. The slot is always exactly `size` square, with or without art, so rows never reflow.
struct ThumbnailView: View {
    var kind: ThumbKind
    var key: String
    var size: CGFloat = 40
    var shape: ThumbShape = .round
    var glyph: String? = nil
    var initials: String? = nil
    var tint: Color = Theme.gold
    /// Employees only: shows a portrait from the faces sheet; the initials or icon stay as the fallback when the sheet cannot be loaded.
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

    /// The asset name for a kind and key: lower case, anything that is not a letter or digit becomes a hyphen.
    static func assetName(_ kind: ThumbKind, _ key: String) -> String {
        var slug = ""
        for ch in key.lowercased() {
            if ch.isLetter || ch.isNumber { slug.append(ch) } else if !slug.hasSuffix("-") { slug.append("-") }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return "thumb-\(kind.rawValue)-\(slug)"
    }

    private var corner: CGFloat { max(6, size * 0.22) }

    /// The slot is always this size, with or without art, so rows never reflow.
    private var slotWidth: CGFloat { shape == .wide ? (size * 16 / 9).rounded() : size }

    var body: some View {
        slot.frame(width: slotWidth, height: size).accessibilityHidden(true)
    }

    /// The portrait cut from the faces sheet for an employee; nil for anything else, when the engine gave none, or when the sheet is missing.
    private var facePicture: CGImage? { kind == .person ? FaceSheet.image(face) : nil }

    @ViewBuilder private var slot: some View {
        if let cg = facePicture {
            // The cut is already a square: fill the slot exactly, clip to the circle, and use the same border as every other avatar.
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
    /// The owner's catalogue asset wins; otherwise the sliced sheet cell for the kind.
    private var picture: UIImage? {
        switch kind {
        case .premises, .person, .trade:
            return UIImage(named: Self.assetName(kind, key))
        case .luxury:
            return UIImage(named: Self.assetName(kind, key)) ?? ArtLibrary.luxuryImage(itemID: key)
        case .premisesPhoto:
            return ArtLibrary.image(.premises, key)
        case .logo:
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
        if shape == .round {
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

    /// Inside a square or wide frame: the logo's initials when it has no picture, else the house icon.
    @ViewBuilder private var squareFallback: some View {
        if kind == .logo, let initials, !initials.isEmpty {
            Text(ArtLibrary.initials(initials)).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(tint)
        } else {
            GlyphView(glyph: glyph ?? kind.fallbackGlyph, size: size * 0.5, weight: 1.5, tint: tint)
        }
    }
}
