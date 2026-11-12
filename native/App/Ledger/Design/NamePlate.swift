import SwiftUI
import Simulation
#if canImport(UIKit)
import UIKit
#endif

/// The shape a worn name plate takes behind the name: the catalogue `style` of the plate (ribbon, chalkboard, slate, mosaic, wood, enamel,
/// neon), and for plates without one a guess from the id and title so every plate has a shape.
enum PlateStyle: CaseIterable {
    case ribbon, plaque, neon, slab

    static func of(_ r: SeasonReward) -> PlateStyle {
        switch r.style.lowercased() {
        case "ribbon": return .ribbon
        case "chalkboard", "slate", "mosaic", "marble", "stone": return .slab
        case "wood", "enamel", "brass", "metal": return .plaque
        case "neon": return .neon
        default: break
        }
        let key: String = (r.id + " " + r.title).lowercased()
        func has(_ words: [String]) -> Bool { words.contains { (w: String) -> Bool in key.contains(w) } }
        if has(["marble", "onyx", "walnut", "stone", "slab"]) { return .slab }
        if has(["brass", "copper", "pewter", "leaf", "counting", "bronze", "silver"]) { return .plaque }
        if has(["neon", "glow", "light", "lamp"]) { return .neon }
        if has(["ledger", "egg", "ribbon", "blossom"]) { return .ribbon }
        return allCases[EmblemCatalog.hash(r.id) % allCases.count]
    }
}

/// A real plate behind the name, sized to the name. Art slot `plate.<plate id>` (png in the art folder, or catalogue image
/// `art.namePlate.<id>`) replaces the vector placeholder.
/// Plate art spec: a horizontal strip, 6:1 (for example 1200 x 200 px), transparent outside the plate. The left and right 18% are never
/// stretched (ends, rivets, ribbon tails); the middle stretches to fit the name. Keep the middle plain so text stays readable.
struct NamePlateView: View {
    var name: String
    var plate: SeasonReward?
    var compact = false

    var body: some View {
        let ink: Color = plate.map { (r: SeasonReward) -> Color in LookKit.ink(r) } ?? Theme.ink
        let style: PlateStyle? = plate.map { (r: SeasonReward) -> PlateStyle in PlateStyle.of(r) }
        let hPad: CGFloat = compact ? Theme.Space.m : (style == .ribbon ? Theme.Space.xl + Theme.Space.xs : Theme.Space.l + Theme.Space.xs)
        let vPad: CGFloat = compact ? 3 : Theme.Space.s
        Text(name)
            .textStyle(compact ? .caption : .title, tint: ink, weight: .semibold)
            .lineLimit(1).minimumScaleFactor(0.6)
            .shadow(color: Color.black.opacity(plate == nil ? 0.55 : 0), radius: 6, x: 0, y: 1)
            .padding(.horizontal, plate == nil ? 0 : hPad).padding(.vertical, plate == nil ? 0 : vPad)
            .background { if let plate, let style { back(plate, style, ink) } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(name)
    }

    @ViewBuilder private func back(_ r: SeasonReward, _ style: PlateStyle, _ ink: Color) -> some View {
        if let art = Self.art(r.id) {
            art
        } else {
            switch style {
            case .ribbon:
                RibbonShape().fill(LookKit.plate(r))
                    .overlay(RibbonShape().stroke(ink.opacity(0.6), lineWidth: 1))
            case .plaque:
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(LookKit.plate(r))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ink.opacity(0.7), lineWidth: 1.5))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(ink.opacity(0.3), lineWidth: 1).padding(4))
                    .overlay { rivets(ink) }
            case .neon:
                Capsule().fill(Color.black.opacity(0.62))
                    .overlay(Capsule().strokeBorder(ink, lineWidth: 2))
                    .shadow(color: ink.opacity(0.75), radius: 7)
            case .slab:
                SlabShape().fill(LookKit.plate(r))
                    .overlay(VeinShape().stroke(ink.opacity(0.28), lineWidth: 1))
                    .overlay(SlabShape().stroke(ink.opacity(0.55), lineWidth: 1))
                    .clipShape(SlabShape())
            }
        }
    }

    private func rivets(_ ink: Color) -> some View {
        func dot() -> some View { Circle().fill(ink.opacity(0.75)).frame(width: 3, height: 3) }
        return VStack {
            HStack { dot(); Spacer(minLength: 0); dot() }
            Spacer(minLength: 0)
            HStack { dot(); Spacer(minLength: 0); dot() }
        }
        .padding(2)
    }

    /// The plate art, stretched in the middle only, or nil when none has been supplied.
    static func art(_ id: String) -> Image? {
        #if canImport(UIKit)
        if let ui = ArtLibrary.droppedImage("plate." + id) ?? ArtLibrary.catalogueImage(.namePlate, id) {
            let cap: CGFloat = ui.size.width * 0.18
            return Image(uiImage: ui).resizable(capInsets: EdgeInsets(top: 0, leading: cap, bottom: 0, trailing: cap), resizingMode: .stretch)
        }
        #endif
        return nil
    }
}

/// A strip with swallow-tail ends.
private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let n: CGFloat = rect.height * 0.32
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - n, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + n, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// A rectangle with cut corners.
private struct SlabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c: CGFloat = min(rect.height * 0.24, 10)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.closeSubpath()
        return p
    }
}

/// Two faint veins across a slab.
private struct VeinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.midY), control2: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.midY))
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + rect.width * 0.7, y: rect.midY), control2: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.midY))
        return p
    }
}
