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

    /// The icon shown while no picture has been supplied.
    var fallbackGlyph: String {
        switch self {
        case .premises: return Glyph.home
        case .person: return Glyph.person
        case .trade: return Glyph.group
        case .luxury: return Glyph.luxury
        }
    }
}

enum ThumbShape {
    case round
    case square
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

    var body: some View {
        slot.frame(width: size, height: size).accessibilityHidden(true)
    }

    /// The portrait cut from the faces sheet for an employee; nil for anything else, when the engine gave none, or when the sheet is missing.
    private var facePicture: CGImage? { kind == .person ? FaceSheet.image(face) : nil }

    @ViewBuilder private var slot: some View {
        if let cg = facePicture {
            let image = Image(decorative: cg, scale: 1).resizable().scaledToFill().frame(width: size, height: size)
            image.clipShape(Circle()).overlay(Circle().strokeBorder(Theme.ivory.opacity(0.45), lineWidth: 1))
        } else {
            artSlot
        }
    }

    @ViewBuilder private var artSlot: some View {
        #if canImport(UIKit)
        if let ui = UIImage(named: Self.assetName(kind, key)) {
            pictureView(ui)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    #if canImport(UIKit)
    @ViewBuilder private func pictureView(_ ui: UIImage) -> some View {
        let image = Image(uiImage: ui).resizable().scaledToFill().frame(width: size, height: size)
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
            if kind == .person, let initials, !initials.isEmpty {
                TeamInitials(name: initials, size: size)
            } else {
                IconCircle(glyph: glyph ?? kind.fallbackGlyph, size: size, tint: tint)
            }
        } else {
            let box = RoundedRectangle(cornerRadius: corner, style: .continuous)
            GlyphView(glyph: glyph ?? kind.fallbackGlyph, size: size * 0.5, weight: 1.5, tint: tint)
                .frame(width: size, height: size)
                .overlay(box.strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
    }
}
