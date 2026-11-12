import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum AvatarArt {
    /// A layer image from the asset catalogue or the dropped art folder, if the art exists.
    static func image(_ name: String) -> Image? {
        #if canImport(UIKit)
        if let ui = ArtAsset.uiImage(name) { return Image(uiImage: ui) }
        #endif
        return nil
    }

    /// Height of the layer canvas relative to its width.
    static let aspect: CGFloat = 1.1
}

/// The half-body avatar, drawn in layers: hair behind, body and outfit, face, front hair.
/// Each layer uses its art asset when present and a vector placeholder otherwise.
struct HalfBodyAvatar: View {
    var look: AvatarLook
    var width: CGFloat

    var body: some View {
        let outfit: OutfitDef = AvatarParts.outfit(look.outfit) ?? AvatarParts.outfits[0]
        let face: FaceDef = AvatarParts.faces[AvatarParts.clamp(look.face, AvatarParts.faces.count)]
        let hairKey: String = AvatarParts.hairStyles[AvatarParts.clamp(look.hair, AvatarParts.hairStyles.count)].key
        let tint: Color = AvatarParts.hairColour(look.hairColour)
        let skin: Color = look.skin >= 0 ? AvatarParts.skinTone(look.skin) : Color(hex: face.skin)
        ZStack {
            tinted("avatar.hair." + hairKey + ".back", tint: tint) { AvatarHairBack(key: hairKey, w: width).foregroundStyle(tint) }
            plain("avatar.body." + outfit.id) { AvatarBodyArt(outfit: outfit, skin: skin, w: width) }
            if look.skin >= 0 { tinted("avatar.skin.\(face.id)", tint: skin) { EmptyView() } }
            plain("avatar.face.\(face.id)") { AvatarFaceArt(face: face, skin: skin, w: width) }
            tinted("avatar.hair." + hairKey, tint: tint) { AvatarHairFront(key: hairKey, w: width).foregroundStyle(tint) }
        }
        .frame(width: width, height: width * AvatarArt.aspect)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func plain<P: View>(_ name: String, @ViewBuilder placeholder: () -> P) -> some View {
        if let img = AvatarArt.image(name) {
            img.resizable().scaledToFit()
        } else {
            placeholder()
        }
    }

    @ViewBuilder private func tinted<P: View>(_ name: String, tint: Color, @ViewBuilder placeholder: () -> P) -> some View {
        if let img = AvatarArt.image(name) {
            img.resizable().renderingMode(.template).scaledToFit().foregroundStyle(tint)
        } else {
            placeholder()
        }
    }
}

/// The head of an avatar cropped to a circle, for lists, rows and small portraits.
struct AvatarHead: View {
    var look: AvatarLook
    var size: CGFloat
    var backdrop: Color = Color(hex: 0x2A2C30)

    var body: some View {
        let big: CGFloat = size * 1.9
        HalfBodyAvatar(look: look, width: big)
            .offset(y: -size * 0.19)
            .frame(width: size, height: size, alignment: .top)
            .background(backdrop)
            .clipShape(Circle())
    }
}

private struct VShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct AvatarFaceArt: View {
    var face: FaceDef
    var skin: Color
    var w: CGFloat

    var body: some View {
        let sharp: Bool = face.variant == 1
        let ink: Color = Color(hex: 0x1E1B1A)
        ZStack {
            Circle().fill(skin).frame(width: w * 0.06, height: w * 0.06).position(x: w * 0.315, y: w * 0.385)
            Circle().fill(skin).frame(width: w * 0.06, height: w * 0.06).position(x: w * 0.685, y: w * 0.385)
            Ellipse().fill(skin).frame(width: w * 0.36, height: w * 0.42).position(x: w * 0.5, y: w * 0.36)
            Ellipse().fill(ink).frame(width: w * (sharp ? 0.04 : 0.032), height: w * (sharp ? 0.026 : 0.04)).position(x: w * 0.425, y: w * 0.37)
            Ellipse().fill(ink).frame(width: w * (sharp ? 0.04 : 0.032), height: w * (sharp ? 0.026 : 0.04)).position(x: w * 0.575, y: w * 0.37)
            Capsule().fill(ink.opacity(0.7)).frame(width: w * 0.07, height: w * 0.012)
                .rotationEffect(.degrees(sharp ? 8 : -3)).position(x: w * 0.425, y: w * 0.335)
            Capsule().fill(ink.opacity(0.7)).frame(width: w * 0.07, height: w * 0.012)
                .rotationEffect(.degrees(sharp ? -8 : 3)).position(x: w * 0.575, y: w * 0.335)
            Capsule().fill(Color.black.opacity(0.13)).frame(width: w * 0.022, height: w * 0.05).position(x: w * 0.5, y: w * 0.425)
            Capsule().fill(Color(hex: 0x8A4A44)).frame(width: w * (sharp ? 0.07 : 0.09), height: w * 0.018)
                .rotationEffect(.degrees(sharp ? -6 : 0)).position(x: w * 0.5, y: w * 0.495)
        }
        .frame(width: w, height: w * AvatarArt.aspect)
    }
}

private struct AvatarBodyArt: View {
    var outfit: OutfitDef
    var skin: Color
    var w: CGFloat

    var body: some View {
        let main: Color = Color(hex: outfit.main)
        let trim: Color = Color(hex: outfit.trim)
        ZStack {
            Rectangle().fill(skin).frame(width: w * 0.12, height: w * 0.14).position(x: w * 0.5, y: w * 0.58)
            UnevenRoundedRectangle(topLeadingRadius: w * 0.26, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: w * 0.26)
                .fill(outfit.id == "vest" ? trim : main)
                .frame(width: w * 0.92, height: w * 0.48).position(x: w * 0.5, y: w * 0.86)
            details(main: main, trim: trim)
        }
        .frame(width: w, height: w * AvatarArt.aspect)
    }

    @ViewBuilder private func details(main: Color, trim: Color) -> some View {
        switch outfit.id {
        case "shirt":
            VShape().fill(skin).frame(width: w * 0.2, height: w * 0.1).position(x: w * 0.5, y: w * 0.665)
            VShape().stroke(trim, lineWidth: w * 0.012).frame(width: w * 0.24, height: w * 0.12).position(x: w * 0.5, y: w * 0.675)
        case "polo":
            VShape().fill(skin).frame(width: w * 0.18, height: w * 0.08).position(x: w * 0.5, y: w * 0.655)
            Capsule().fill(trim).frame(width: w * 0.22, height: w * 0.03).position(x: w * 0.5, y: w * 0.63)
            Circle().fill(trim).frame(width: w * 0.02, height: w * 0.02).position(x: w * 0.5, y: w * 0.72)
            Circle().fill(trim).frame(width: w * 0.02, height: w * 0.02).position(x: w * 0.5, y: w * 0.77)
        case "hoodie":
            Ellipse().stroke(trim, lineWidth: w * 0.05).frame(width: w * 0.3, height: w * 0.12).position(x: w * 0.5, y: w * 0.635)
            Capsule().fill(trim).frame(width: w * 0.012, height: w * 0.12).position(x: w * 0.46, y: w * 0.74)
            Capsule().fill(trim).frame(width: w * 0.012, height: w * 0.12).position(x: w * 0.54, y: w * 0.74)
        case "blazer":
            VShape().fill(trim).frame(width: w * 0.22, height: w * 0.2).position(x: w * 0.5, y: w * 0.72)
            VShape().fill(main.opacity(0.7)).frame(width: w * 0.1, height: w * 0.24).rotationEffect(.degrees(24)).position(x: w * 0.4, y: w * 0.74)
            VShape().fill(main.opacity(0.7)).frame(width: w * 0.1, height: w * 0.24).rotationEffect(.degrees(-24)).position(x: w * 0.6, y: w * 0.74)
        case "suit":
            VShape().fill(Color(hex: 0xF1EBDD)).frame(width: w * 0.22, height: w * 0.2).position(x: w * 0.5, y: w * 0.72)
            Capsule().fill(trim).frame(width: w * 0.045, height: w * 0.17).position(x: w * 0.5, y: w * 0.76)
            Circle().fill(trim).frame(width: w * 0.05, height: w * 0.05).position(x: w * 0.5, y: w * 0.665)
        case "turtleneck":
            Capsule().fill(trim).frame(width: w * 0.2, height: w * 0.1).position(x: w * 0.5, y: w * 0.62)
        case "vest":
            VShape().fill(skin).frame(width: w * 0.2, height: w * 0.09).position(x: w * 0.5, y: w * 0.66)
            RoundedRectangle(cornerRadius: w * 0.04).fill(main).frame(width: w * 0.5, height: w * 0.42).position(x: w * 0.5, y: w * 0.89)
            VShape().fill(trim).frame(width: w * 0.16, height: w * 0.16).position(x: w * 0.5, y: w * 0.7)
        default:
            VShape().fill(Color(hex: 0xF1EBDD)).frame(width: w * 0.18, height: w * 0.2).position(x: w * 0.5, y: w * 0.72)
            Capsule().fill(trim).frame(width: w * 0.12, height: w * 0.035).position(x: w * 0.5, y: w * 0.655)
        }
    }
}

private struct AvatarHairBack: View {
    var key: String
    var w: CGFloat

    var body: some View {
        ZStack {
            switch key {
            case "buzz":
                Ellipse().frame(width: w * 0.38, height: w * 0.36).position(x: w * 0.5, y: w * 0.31)
            case "long":
                RoundedRectangle(cornerRadius: w * 0.18).frame(width: w * 0.5, height: w * 0.64).position(x: w * 0.5, y: w * 0.5)
            case "bun":
                Ellipse().frame(width: w * 0.42, height: w * 0.4).position(x: w * 0.5, y: w * 0.3)
                Circle().frame(width: w * 0.15, height: w * 0.15).position(x: w * 0.5, y: w * 0.115)
            case "curly":
                ForEach(0..<7, id: \.self) { (i: Int) in
                    let a: Double = Double.pi * Double(i) / 6
                    Circle().frame(width: w * 0.15, height: w * 0.15)
                        .position(x: w * (0.5 - 0.21 * CGFloat(cos(a))), y: w * (0.33 - 0.2 * CGFloat(sin(a))))
                }
                Ellipse().frame(width: w * 0.4, height: w * 0.36).position(x: w * 0.5, y: w * 0.32)
            case "tail":
                Ellipse().frame(width: w * 0.42, height: w * 0.4).position(x: w * 0.5, y: w * 0.3)
                Capsule().frame(width: w * 0.09, height: w * 0.28).rotationEffect(.degrees(-18)).position(x: w * 0.74, y: w * 0.44)
            case "bald":
                EmptyView()
            default:
                Ellipse().frame(width: w * 0.42, height: w * 0.4).position(x: w * 0.5, y: w * 0.3)
            }
        }
        .frame(width: w, height: w * AvatarArt.aspect)
    }
}

private struct AvatarHairFront: View {
    var key: String
    var w: CGFloat

    var body: some View {
        ZStack {
            switch key {
            case "bald":
                EmptyView()
            case "buzz":
                Ellipse().frame(width: w * 0.34, height: w * 0.06).position(x: w * 0.5, y: w * 0.185)
            case "side":
                Ellipse().frame(width: w * 0.4, height: w * 0.1).rotationEffect(.degrees(-10)).position(x: w * 0.47, y: w * 0.2)
            case "curly":
                ForEach(0..<3, id: \.self) { (i: Int) in
                    Circle().frame(width: w * 0.1, height: w * 0.1).position(x: w * (0.44 + 0.06 * CGFloat(i)), y: w * 0.19)
                }
            default:
                Ellipse().frame(width: w * 0.37, height: w * 0.11).position(x: w * 0.5, y: w * 0.205)
            }
        }
        .frame(width: w, height: w * AvatarArt.aspect)
    }
}
