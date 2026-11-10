import SwiftUI

struct LiquidGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Theme.walnutRaised))
                .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        } else {
            glassBody(content)
        }
    }

    @ViewBuilder
    private func glassBody(_ content: Content) -> some View {
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
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)], startPoint: .top, endPoint: .center))
                }
            )
            .overlay(
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
    func liquidGlass(cornerRadius: CGFloat = Theme.Radius.m, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive))
    }
    func liquidGlassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: Circle(), tint: tint, interactive: interactive))
    }
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: Capsule(), tint: tint, interactive: interactive))
    }
}

struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
