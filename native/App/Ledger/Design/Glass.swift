import SwiftUI

/// Liquid Glass, used where it belongs: on things that float above the content (the Next day bar, tab pills, the
/// country chip, toasts, steppers) and on the few hero boxes (net worth, company value, the next 30 days).
///
/// Built with the iOS 26 SDK and running on iOS 26, this is Apple's real Liquid Glass (`glassEffect`). Everywhere else
/// it is drawn by hand in the same spirit: a blurred material over the dark page, a charcoal tint so the colours stay
/// those of the concept, a bright specular rim at the top edge that fades round the sides, and a soft inner sheen.
struct LiquidGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var interactive = false

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            drawn(content)
        }
        #else
        drawn(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.35)) }
        if interactive { g = g.interactive() }
        return g
    }
    #endif

    private func drawn(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill((tint ?? Theme.walnutRaised).opacity(tint == nil ? 0.55 : 0.42))
                    // Sheen: light caught in the upper part of the glass
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)], startPoint: .top, endPoint: .center))
                }
            )
            .overlay(
                // Specular rim: bright along the top, fading down the sides, a faint return at the bottom
                shape.strokeBorder(
                    LinearGradient(stops: [
                        .init(color: Color.white.opacity(0.42), location: 0),
                        .init(color: Color.white.opacity(0.10), location: 0.35),
                        .init(color: Color.white.opacity(0.04), location: 0.7),
                        .init(color: Color.white.opacity(0.14), location: 1),
                    ], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.9
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }
}

extension View {
    /// Liquid Glass in a rounded rectangle.
    func liquidGlass(cornerRadius: CGFloat = Theme.Radius.m, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive))
    }
    /// Liquid Glass in a capsule (pills, chips, floating bars).
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: Capsule(), tint: tint, interactive: interactive))
    }
}

/// The main box of a screen. It used to be glass; content boxes now share the calm card surface so that glass is kept for
/// controls that float above the content (the Next day bar, toasts, tab pills). Kept as a type so the hero boxes stay marked.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.l
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        Card(padding: padding, content: content)
    }
}

/// Soft light behind the content, so glass has something to bend: a warm bronze glow high on the right and a cool one
/// low on the left, both faint enough that the page stays charcoal.
struct AmbientLight: View {
    var body: some View {
        GeometryReader { g in
            ZStack {
                RadialGradient(colors: [Theme.gold.opacity(0.09), .clear], center: .topTrailing, startRadius: 0, endRadius: g.size.width * 0.9)
                RadialGradient(colors: [Theme.slateBlue.opacity(0.06), .clear], center: UnitPoint(x: 0, y: 0.55), startRadius: 0, endRadius: g.size.width * 0.8)
                RadialGradient(colors: [Theme.roseGold.opacity(0.04), .clear], center: .bottom, startRadius: 0, endRadius: g.size.width * 0.7)
            }
        }
        .allowsHitTesting(false)
    }
}
