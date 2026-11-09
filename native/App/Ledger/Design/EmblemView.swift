import SwiftUI

// Drawn artwork for the game's things (trades, artifacts, cosmetics, boxes, pass rewards, player icons): a gradient field, a quiet pattern,
// one or two SF Symbols and a rarity frame. Everything is vector, so it is sharp at any size. `ItemArt` picks the right emblem by id and
// swaps in a supplied picture when one exists (see `ArtLibrary.catalogueImage`).

/// The tier of the frame drawn round an emblem. Plain has only a hairline (trades, avatars of no rarity).
enum EmblemFrame: Int, Comparable {
    case plain, common, rare, epic, legendary
    static func < (a: EmblemFrame, b: EmblemFrame) -> Bool { a.rawValue < b.rawValue }
}

enum EmblemShape: Equatable {
    case round, tile, medal, shield
    /// A wide plate (name plates, backdrops); drawn as a tile when the caller wants a square slot.
    case plate
}

/// The pattern behind the symbol.
enum EmblemMotif: Equatable {
    case none, rays, rings, dots, stripes, waves, grid, hills, stars, plateLines
}

/// Where the main symbol sits.
enum EmblemPlacement: Equatable {
    case center, leading, corner
}

struct EmblemSpec: Equatable {
    var symbol: String
    /// A small second symbol in a disc at the bottom right.
    var badge: String? = nil
    var top: UInt32
    var bottom: UInt32
    var ink: UInt32
    var motif: EmblemMotif = .none
    var shape: EmblemShape = .tile
    var placement: EmblemPlacement = .center
}

// MARK: Outlines

struct OctagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c: CGFloat = min(rect.width, rect.height) * 0.29
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

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w: CGFloat = rect.width, h: CGFloat = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.1))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX + w * 0.3, y: rect.minY + h * 0.1))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - w * 0.08, y: rect.minY + h * 0.1), control: CGPoint(x: rect.maxX - w * 0.3, y: rect.minY + h * 0.1))
        p.addLine(to: CGPoint(x: rect.maxX - w * 0.08, y: rect.minY + h * 0.5))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX - w * 0.08, y: rect.minY + h * 0.85))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.5), control: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.85))
        p.closeSubpath()
        return p
    }
}

extension EmblemShape {
    func outline(height: CGFloat) -> AnyShape {
        switch self {
        case .round: return AnyShape(Circle())
        case .tile: return AnyShape(RoundedRectangle(cornerRadius: height * 0.24, style: .continuous))
        case .medal: return AnyShape(OctagonShape())
        case .shield: return AnyShape(ShieldShape())
        case .plate: return AnyShape(RoundedRectangle(cornerRadius: height * 0.16, style: .continuous))
        }
    }
}

// MARK: Pattern

private struct EmblemMotifLayer: View {
    var motif: EmblemMotif
    var color: Color

    private static let starPoints: [(CGFloat, CGFloat, CGFloat)] = [
        (0.14, 0.2, 1.0), (0.3, 0.12, 0.6), (0.52, 0.22, 0.8), (0.74, 0.1, 1.0), (0.88, 0.28, 0.6),
        (0.2, 0.42, 0.5), (0.64, 0.4, 0.5), (0.4, 0.34, 0.7)
    ]

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let w: CGFloat = size.width, h: CGFloat = size.height
            let m: CGFloat = min(w, h)
            let c = CGPoint(x: w / 2, y: h / 2)
            let line: CGFloat = max(1, m * 0.025)
            switch motif {
            case .none:
                break
            case .rays:
                let n: Int = 14
                let reach: CGFloat = hypot(w, h)
                for i in 0..<n {
                    let a0: Double = Double(i) / Double(n) * 2 * Double.pi
                    let a1: Double = a0 + Double.pi / Double(n)
                    var p = Path()
                    p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a0)) * reach, y: c.y + CGFloat(sin(a0)) * reach))
                    p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a1)) * reach, y: c.y + CGFloat(sin(a1)) * reach))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(color))
                }
            case .rings:
                for i in 1...4 {
                    let r: CGFloat = m * 0.17 * CGFloat(i)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color), lineWidth: line)
                }
            case .dots:
                let step: CGFloat = m / 6
                var y: CGFloat = step / 2
                var row: Int = 0
                while y < h + step {
                    var x: CGFloat = row % 2 == 0 ? step / 2 : step
                    while x < w + step {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - step * 0.1, y: y - step * 0.1, width: step * 0.2, height: step * 0.2)), with: .color(color))
                        x += step
                    }
                    y += step
                    row += 1
                }
            case .stripes:
                let step: CGFloat = m / 5
                var x: CGFloat = -h
                while x < w {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: h))
                    p.addLine(to: CGPoint(x: x + h, y: 0))
                    ctx.stroke(p, with: .color(color), lineWidth: line * 1.6)
                    x += step
                }
            case .waves:
                for row in 0..<5 {
                    let y: CGFloat = h * (0.25 + 0.15 * CGFloat(row))
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    var sx: CGFloat = 0
                    while sx <= w {
                        p.addLine(to: CGPoint(x: sx, y: y + CGFloat(sin(Double(sx / w) * 4 * Double.pi)) * h * 0.04))
                        sx += 2
                    }
                    ctx.stroke(p, with: .color(color), lineWidth: line)
                }
            case .grid:
                let step: CGFloat = m / 5
                var x: CGFloat = step / 2
                while x < w {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                    ctx.stroke(p, with: .color(color), lineWidth: line * 0.8)
                    x += step
                }
                var y: CGFloat = step / 2
                while y < h {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                    ctx.stroke(p, with: .color(color), lineWidth: line * 0.8)
                    y += step
                }
            case .hills:
                var far = Path()
                far.move(to: CGPoint(x: 0, y: h))
                far.addLine(to: CGPoint(x: 0, y: h * 0.7))
                far.addQuadCurve(to: CGPoint(x: w * 0.6, y: h * 0.66), control: CGPoint(x: w * 0.25, y: h * 0.38))
                far.addQuadCurve(to: CGPoint(x: w, y: h * 0.6), control: CGPoint(x: w * 0.85, y: h * 0.84))
                far.addLine(to: CGPoint(x: w, y: h))
                far.closeSubpath()
                ctx.fill(far, with: .color(color.opacity(0.6)))
                var near = Path()
                near.move(to: CGPoint(x: 0, y: h))
                near.addLine(to: CGPoint(x: 0, y: h * 0.86))
                near.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.88), control: CGPoint(x: w * 0.22, y: h * 0.7))
                near.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: w * 0.78, y: h * 1.0))
                near.addLine(to: CGPoint(x: w, y: h))
                near.closeSubpath()
                ctx.fill(near, with: .color(color))
            case .stars:
                for s in Self.starPoints {
                    let r: CGFloat = m * 0.025 * s.2 + 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: w * s.0 - r, y: h * s.1 - r, width: 2 * r, height: 2 * r)), with: .color(color))
                }
            case .plateLines:
                for y in [h * 0.2, h * 0.8] {
                    var p = Path()
                    p.move(to: CGPoint(x: w * 0.08, y: y)); p.addLine(to: CGPoint(x: w * 0.92, y: y))
                    ctx.stroke(p, with: .color(color), lineWidth: line)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: The emblem

/// One drawn emblem. `size` is the height; a plate is 1.6 times as wide when `wide` is true, otherwise every emblem is `size` square.
struct EmblemView: View {
    var spec: EmblemSpec
    var frame: EmblemFrame = .plain
    var size: CGFloat = 44
    var wide: Bool = false
    /// A supplied picture; replaces the drawn field and symbol, the shape and frame stay.
    var picture: Image? = nil

    private var isWide: Bool { wide && spec.shape == .plate }
    private var width: CGFloat { isWide ? (size * 1.6).rounded() : size }
    private var shape: EmblemShape { spec.shape == .plate && !isWide ? .tile : spec.shape }

    var body: some View {
        let outline: AnyShape = shape.outline(height: size)
        let line: CGFloat = max(1, size * 0.025)
        ZStack {
            if let picture {
                picture.resizable().scaledToFill().frame(width: width, height: size).clipShape(outline)
            } else {
                outline.fill(LinearGradient(colors: [Color(hex: spec.top), Color(hex: spec.bottom)], startPoint: .top, endPoint: .bottom))
                EmblemMotifLayer(motif: isWide || spec.motif != .plateLines ? spec.motif : .none, color: Color(hex: spec.ink))
                    .opacity(0.17)
                    .clipShape(outline)
                outline.fill(RadialGradient(colors: [Color.white.opacity(0.2), Color.clear], center: .topLeading, startRadius: 0, endRadius: size * 0.95))
                symbolLayer
                if let badge = spec.badge { badgeLayer(badge) }
            }
            frameLayer(outline: outline, line: line)
            if frame == .legendary && size >= 28 {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFE9A0))
                    .padding(size * 0.1)
                    .frame(width: width, height: size, alignment: .topTrailing)
            }
        }
        .frame(width: width, height: size)
        .shadow(color: glow, radius: size >= 28 ? size * 0.11 : 0)
        .accessibilityHidden(true)
    }

    private var glow: Color {
        switch frame {
        case .legendary: return Color(hex: 0xE0BC5E).opacity(0.5)
        case .epic: return Color(hex: 0xB59AD6).opacity(0.32)
        default: return Color.clear
        }
    }

    @ViewBuilder private var symbolLayer: some View {
        let ink: Color = Color(hex: spec.ink)
        switch spec.placement {
        case .center:
            Image(systemName: spec.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(ink)
                .shadow(color: Color.black.opacity(0.35), radius: size * 0.03, y: size * 0.02)
        case .leading:
            Image(systemName: spec.symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(ink)
                .shadow(color: Color.black.opacity(0.3), radius: size * 0.03, y: size * 0.02)
                .padding(.leading, isWide ? size * 0.28 : 0)
                .frame(width: width, height: size, alignment: isWide ? .leading : .center)
        case .corner:
            Image(systemName: spec.symbol)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(ink)
                .shadow(color: Color.black.opacity(0.3), radius: size * 0.03, y: size * 0.02)
                .padding(size * 0.14)
                .frame(width: width, height: size, alignment: .topTrailing)
        }
    }

    private func badgeLayer(_ name: String) -> some View {
        let d: CGFloat = size * 0.32
        return Image(systemName: name)
            .font(.system(size: d * 0.5, weight: .bold))
            .foregroundStyle(Color(hex: spec.ink))
            .frame(width: d, height: d)
            .background(Circle().fill(Color(hex: spec.bottom)))
            .overlay(Circle().stroke(Color(hex: spec.ink).opacity(0.6), lineWidth: max(1, size * 0.02)))
            .padding(size * 0.05)
            .frame(width: width, height: size, alignment: .bottomTrailing)
    }

    @ViewBuilder private func frameLayer(outline: AnyShape, line: CGFloat) -> some View {
        switch frame {
        case .plain:
            outline.stroke(Color.white.opacity(0.14), lineWidth: line).padding(line / 2)
        case .common:
            outline.stroke(Color(hex: 0xA19B8F).opacity(0.75), lineWidth: line * 1.4).padding(line * 0.7)
        case .rare:
            outline.stroke(LinearGradient(colors: [Color(hex: 0xB4CBEB), Color(hex: 0x4F6FA3)], startPoint: .top, endPoint: .bottom), lineWidth: line * 1.8).padding(line * 0.9)
        case .epic:
            outline.stroke(LinearGradient(colors: [Color(hex: 0xDCC6F5), Color(hex: 0x7A56B0)], startPoint: .top, endPoint: .bottom), lineWidth: line * 2).padding(line)
            outline.scale(0.86).stroke(Color(hex: 0xDCC6F5).opacity(0.35), lineWidth: line * 0.7)
        case .legendary:
            outline.stroke(LinearGradient(colors: [Color(hex: 0xFFE9A0), Color(hex: 0xB07A18), Color(hex: 0xFFE9A0)], startPoint: .topLeading, endPoint: .bottomTrailing),
                           lineWidth: line * 2.3).padding(line * 1.15)
            outline.scale(0.86).stroke(Color(hex: 0xFFE9A0).opacity(0.45), lineWidth: line * 0.8)
        }
    }
}
