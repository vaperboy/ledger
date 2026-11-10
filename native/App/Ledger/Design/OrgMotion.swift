import SwiftUI

enum OrgMotion {
    static func row(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Motion.quickAnimation }
    static func hierarchy(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Motion.moveAnimation }
    static func fill(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Motion.quickAnimation }
    static func chart(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Motion.revealAnimation }
    static let flashSeconds: Double = 1.6
}

extension AnyTransition {
    static var orgRow: AnyTransition {
        AnyTransition.asymmetric(insertion: AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity), removal: AnyTransition.opacity)
    }
    static var orgNode: AnyTransition {
        AnyTransition.scale(scale: 0.8).combined(with: AnyTransition.opacity)
    }
}

private struct OrgArrivals<ID: Hashable>: ViewModifier {
    var ids: [ID]
    @Binding var fresh: Set<ID>
    var changed: (Set<ID>, Set<ID>) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(OrgMotion.row(reduceMotion), value: ids)
            .onChange(of: ids) { old, new in
                let added: Set<ID> = Set(new).subtracting(old)
                let gone: Set<ID> = Set(old).subtracting(new)
                changed(added, gone)
                guard !added.isEmpty else { return }
                fresh.formUnion(added)
                DispatchQueue.main.asyncAfter(deadline: .now() + OrgMotion.flashSeconds) { fresh.subtract(added) }
            }
    }
}

extension View {
    func orgArrivals<ID: Hashable>(_ ids: [ID], fresh: Binding<Set<ID>>, changed: @escaping (Set<ID>, Set<ID>) -> Void = { _, _ in }) -> some View {
        modifier(OrgArrivals(ids: ids, fresh: fresh, changed: changed))
    }

    func orgEdge(_ tint: Color?, radius: CGFloat = 14) -> some View { modifier(OrgEdge(tint: tint, radius: radius)) }

    func orgConnector(_ active: Bool) -> some View { modifier(OrgConnector(active: active)) }

    func orgPin(_ active: Bool) -> some View { modifier(OrgPin(active: active)) }
}

private struct OrgEdge: ViewModifier {
    var tint: Color?
    var radius: CGFloat
    @State private var shown = false
    @State private var color: Color = Theme.gold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color, lineWidth: 1.5)
                    .opacity(shown ? 1 : 0).allowsHitTesting(false)
            )
            .onAppear { if let t = tint { start(t) } }
            .onChange(of: tint) { _, new in if let t = new { start(t) } }
    }

    private func start(_ t: Color) {
        color = t
        Motion.animate(reduceMotion ? nil : Motion.quickAnimation) { shown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            Motion.animate(reduceMotion ? nil : Motion.revealAnimation) { shown = false }
        }
    }
}

struct OrgConnectorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 5, y: rect.minY - 10))
        p.addLine(to: CGPoint(x: rect.minX + 5, y: rect.midY - 6))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 11, y: rect.midY), control: CGPoint(x: rect.minX + 5, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + 20, y: rect.midY))
        return p
    }
}

private struct OrgConnector: ViewModifier {
    var active: Bool
    @State private var progress: CGFloat = 0
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                OrgConnectorShape().trim(from: 0, to: progress)
                    .stroke(Theme.gold.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .opacity(visible ? 1 : 0).allowsHitTesting(false)
            )
            .onAppear { if active { start() } }
            .onChange(of: active) { _, on in if on { start() } }
    }

    private func start() {
        guard !reduceMotion else { return }
        progress = 0
        visible = true
        Motion.animate(Motion.revealAnimation) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Motion.animate(Motion.revealAnimation) { visible = false }
        }
    }
}

private struct OrgPin: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if active {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.gold).accessibilityHidden(true)
                        .offset(x: 4, y: -6)
                        .transition(AnyTransition.scale(scale: 0.4, anchor: .bottom).combined(with: AnyTransition.offset(x: 0, y: -10)).combined(with: AnyTransition.opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(OrgMotion.hierarchy(reduceMotion), value: active)
    }
}
