import SwiftUI

/// Organisation motion (animation stage: Team, Group, Projects, Market). Every helper reacts to a real state change the view detects
/// itself with `.onChange(of:)` on derived values; first appearance never animates. Gold = milestone or opportunity, green = gain,
/// red = loss. Nothing here blocks touches or loops. Reduce Motion: the root view already drops animation transactions, and the
/// helpers also pass `nil` animations, so only a static colour highlight can remain.
enum OrgMotion {
    /// Row insertion and removal: 250 ms.
    static func row(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Animation.easeOut(duration: 0.25) }
    /// Hierarchy changes: the app's arrive spring (response 0.38, damping 0.86).
    static func hierarchy(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Animation.spring(response: 0.38, dampingFraction: 0.86) }
    /// Progress bars and small value changes: 350 ms.
    static func fill(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Animation.easeInOut(duration: 0.35) }
    /// Chart redraw: 700 ms.
    static func chart(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Animation.easeInOut(duration: 0.7) }
    /// How long a new item stays marked as new.
    static let flashSeconds: Double = 1.6
}

extension AnyTransition {
    /// A row slides in from its own top edge while fading in; it only fades out.
    static var orgRow: AnyTransition {
        AnyTransition.asymmetric(insertion: AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity), removal: AnyTransition.opacity)
    }
    /// An avatar or node scales in from 0.8 while fading in.
    static var orgNode: AnyTransition {
        AnyTransition.scale(scale: 0.8).combined(with: AnyTransition.opacity)
    }
}

// MARK: Arrivals

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
    /// Watches a list of ids. What was added is kept in `fresh` for about 1.6 s (rows read it to highlight themselves); `changed` gets
    /// (added, gone) on every change. Changes of the list animate with the row animation, so rows with `.transition(.orgRow)` slide.
    /// The first appearance never fires.
    func orgArrivals<ID: Hashable>(_ ids: [ID], fresh: Binding<Set<ID>>, changed: @escaping (Set<ID>, Set<ID>) -> Void = { _, _ in }) -> some View {
        modifier(OrgArrivals(ids: ids, fresh: fresh, changed: changed))
    }

    /// Animates layout changes of the container when `value` changes (the hierarchy spring).
    func orgHierarchy<V: Equatable>(_ value: V) -> some View { modifier(OrgHierarchy(value: value)) }

    /// A brief edge highlight (1.5 pt ring, fades in 250 ms, out after about 1.2 s) whenever `tint` becomes non-nil.
    /// Pass gold for new or an opportunity, green for a gain, red for a loss. `radius` 17 on a 34 pt icon makes a ring.
    func orgEdge(_ tint: Color?, radius: CGFloat = 14) -> some View { modifier(OrgEdge(tint: tint, radius: radius)) }

    /// A drawn connector (elbow line, trim 0 to 1 in 700 ms, fades out after about 2 s) at the leading edge when `active` turns true.
    func orgConnector(_ active: Bool) -> some View { modifier(OrgConnector(active: active)) }

    /// A location pin that drops in (fade and scale) at the top leading corner while `active`.
    func orgPin(_ active: Bool) -> some View { modifier(OrgPin(active: active)) }

    /// A short scale pulse with a gold glow when `value` changes (badge, milestone). Not on first appearance.
    func orgPulse<V: Equatable>(_ value: V, tint: Color = Theme.gold) -> some View { modifier(OrgPulse(value: value, tint: tint)) }

    /// Text that cross-fades (or morphs with `interpolate`) when `value` changes.
    func orgTextSwap<V: Equatable>(_ value: V, interpolate: Bool = false) -> some View { modifier(OrgTextSwap(value: value, interpolate: interpolate)) }

    /// A chart or line that redraws with a left to right sweep (700 ms) when `value` changes.
    func orgRedraw<V: Equatable>(_ value: V) -> some View { modifier(OrgRedraw(value: value)) }

    /// A small dismissible completion card over the top of this view (acquisition).
    func orgCompletion(_ item: Binding<OrgCompletion?>) -> some View { modifier(OrgCompletionHost(item: item)) }
}

private struct OrgHierarchy<V: Equatable>: ViewModifier {
    var value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View { content.animation(OrgMotion.hierarchy(reduceMotion), value: value) }
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
        withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 0.25)) { shown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 0.6)) { shown = false }
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
        withAnimation(.easeInOut(duration: 0.7)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.6)) { visible = false }
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

private struct OrgPulse<V: Equatable>: ViewModifier {
    var value: V
    var tint: Color
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.1 : 1)
            .shadow(color: tint.opacity(on ? 0.7 : 0), radius: on ? 6 : 0)
            .onChange(of: value) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.18)) { on = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.easeInOut(duration: 0.4)) { on = false } }
            }
    }
}

private struct OrgTextSwap<V: Equatable>: ViewModifier {
    var value: V
    var interpolate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(interpolate ? ContentTransition.interpolate : ContentTransition.opacity)
            .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.3), value: value)
    }
}

private struct OrgRedraw<V: Equatable>: ViewModifier {
    var value: V
    @State private var reveal: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { g in
                    Rectangle().frame(width: g.size.width * reveal, height: g.size.height + 40).frame(width: g.size.width, height: g.size.height, alignment: .leading)
                }
            )
            .onChange(of: value) { _, _ in
                guard !reduceMotion else { return }
                reveal = 0.02
                withAnimation(.easeInOut(duration: 0.7)) { reveal = 1 }
            }
    }
}

// MARK: Pieces

/// A progress bar whose fill animates (350 ms) and that pulses gold when `milestones` goes up.
struct OrgProgressBar: View {
    var fraction: Double
    var milestones: Int
    var height: CGFloat = 5
    var track: Color = Color(hex: 0x26272A)
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(Theme.gold).frame(width: g.size.width * CGFloat(min(1, max(0, fraction))))
                    .shadow(color: Theme.gold.opacity(glow ? 0.8 : 0), radius: glow ? 5 : 0)
            }
        }
        .frame(height: height)
        .animation(OrgMotion.fill(reduceMotion), value: fraction)
        .onChange(of: milestones) { old, new in
            guard new > old, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.2)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withAnimation(.easeInOut(duration: 0.5)) { glow = false } }
        }
    }
}

/// A short horizontal link (manager to department). Draws from nothing to full when `drawn` turns true; otherwise it is simply there.
struct OrgLink: View {
    var drawn: Bool
    var width: CGFloat = 18
    @State private var progress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule().fill(Theme.gold.opacity(0.7)).frame(width: width, height: 1.5)
            .scaleEffect(x: progress, y: 1, anchor: .leading)
            .onAppear { if drawn { draw() } }
            .onChange(of: drawn) { _, on in if on { draw() } }
    }

    private func draw() {
        guard !reduceMotion else { return }
        progress = 0
        withAnimation(.easeInOut(duration: 0.6)) { progress = 1 }
    }
}

/// One line of notice that comes and goes by itself (a resignation reason, a recognition chip).
struct OrgNote: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var tint: Color

    /// Adds a note to `list` and removes it after `seconds`.
    static func show(_ list: Binding<[OrgNote]>, text: String, tint: Color = Theme.ivoryMuted, seconds: Double = 3) {
        let note = OrgNote(text: text, tint: tint)
        withAnimation(.easeOut(duration: 0.25)) { list.wrappedValue.append(note) }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            withAnimation(.easeOut(duration: 0.3)) { list.wrappedValue.removeAll { $0.id == note.id } }
        }
    }
}

/// The notes as small chips; empty when there are none. Never takes touches.
struct OrgNoteStack: View {
    var notes: [OrgNote]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(notes) { n in
                Text(n.text).font(.system(size: 11.5)).foregroundStyle(n.tint).lineLimit(2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(n.tint.opacity(0.6), lineWidth: 1))
                    .transition(AnyTransition.opacity.combined(with: AnyTransition.move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

// MARK: Acquisition completion

struct OrgCompletion: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var name: String
    var detail: String
}

struct OrgCompletionCard: View {
    var item: OrgCompletion
    var dismiss: () -> Void
    @State private var ring: CGFloat = 0
    @State private var textIn = false

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Theme.hairline, lineWidth: 2)
                    Circle().trim(from: 0, to: ring).stroke(Theme.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                }.frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold)
                    Text(item.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text(item.detail).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
                }
                .opacity(textIn ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(item.title): \(item.name). \(item.detail). Tap to dismiss.")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2)) { ring = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) { textIn = true }
        }
    }
}

private struct OrgCompletionHost: ViewModifier {
    @Binding var item: OrgCompletion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let it = item {
                    OrgCompletionCard(item: it) { item = nil }
                        .transition(AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity))
                        .id(it.id)
                }
            }
            .animation(OrgMotion.hierarchy(reduceMotion), value: item?.id)
            .onChange(of: item?.id) { _, new in
                guard let new else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { if item?.id == new { item = nil } }
            }
    }
}
