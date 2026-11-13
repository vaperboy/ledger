import SwiftUI

/// A flat translucent surface with a thin light edge. It keeps the frosted look without live blur,
/// Liquid Glass or shadows, which were redrawn on every frame of every scroll and transition.
struct LiquidGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let base: Color = tint ?? Theme.walnutRaised
        let fill: Double = reduceTransparency ? 1 : 0.88
        return content
            .background(shape.fill(base.opacity(fill)))
            .overlay(shape.strokeBorder(Color.white.opacity(reduceTransparency ? 0.3 : 0.12), lineWidth: 1))
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

/// Kept for call sites that group glass shapes; with flat surfaces there is nothing to merge.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View { content() }
}
