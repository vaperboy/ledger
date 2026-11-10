import SwiftUI

struct DrawInOnce: ViewModifier {
    var duration: Double = Motion.revealSeconds
    @State private var progress: CGFloat = 0
    @State private var started: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: reduceMotion ? 1 : max(progress, 0.001), y: 1, anchor: .leading)
            }
            .onAppear {
                guard !started else { return }
                started = true
                if reduceMotion { progress = 1 } else { Motion.animate(Motion.revealAnimation) { progress = 1 } }
            }
    }
}

extension Motion {
    static func fill(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Motion.quickAnimation }
    static func count(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Motion.quickAnimation }
}

struct GoldPulse: ViewModifier {
    var trigger: Bool
    func body(content: Content) -> some View { content }
}

struct StaggerReveal: ViewModifier {
    var index: Int
    @State private var shown: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true; return }
                Motion.animate(Motion.quickAnimation.delay(Double(min(index, 12)) * 0.04)) { shown = true }
            }
    }
}

extension View {
    func drawsItself(duration: Double = Motion.revealSeconds) -> some View { modifier(DrawInOnce(duration: duration)) }
    func goldPulse(_ trigger: Bool) -> some View { modifier(GoldPulse(trigger: trigger)) }
    func staggerReveal(_ index: Int) -> some View { modifier(StaggerReveal(index: index)) }
}

struct MotionOverlay: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                if let c = store.transferChip {
                    TransferChipView(chip: c, top: proxy.frame(in: .global))
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }
}

struct TransferChipView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var chip: TransferChip
    var top: CGRect = .zero
    @State private var step: Int = 0

    private var flies: Bool { chip.origin != nil && !reduceMotion }

    private var startOffset: CGSize {
        guard flies, let o = chip.origin else { return CGSize(width: 0, height: 24) }
        return CGSize(width: o.x - top.midX, height: o.y - (top.minY + 30))
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(chip.label).textStyle(.caption, tint: Theme.inkSoft)
            Text((chip.outgoing ? "\u{2212}" : "+") + (chip.text ?? store.short(chip.amount)))
                .textStyle(.body, tint: chip.outgoing ? Theme.loss : Theme.accent, numeric: true, weight: .semibold)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(Capsule().fill(Theme.surfaceRaised))
        .elevation(.raised)
        .opacity(step == 1 ? 1 : 0)
        .scaleEffect(flies && step == 0 ? 0.9 : 1)
        .offset(reduceMotion ? .zero : (step == 0 ? startOffset : (step == 1 ? .zero : CGSize(width: 0, height: -24))))
        .task(id: chip.id) {
            step = 0
            if flies {
                Motion.animate(.easeInOut(duration: 0.5)) { step = 1 }
                try? await Task.sleep(nanoseconds: 750_000_000)
                Motion.animate(Motion.quickAnimation) { step = 2 }
                try? await Task.sleep(nanoseconds: 250_000_000)
            } else {
                Motion.animate(Motion.quickAnimation) { step = 1 }
                try? await Task.sleep(nanoseconds: 900_000_000)
                Motion.animate(Motion.quickAnimation) { step = 2 }
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            if store.transferChip?.id == chip.id { store.clearChip() }
        }
        .accessibilityHidden(true)
    }
}

struct MoneyBurst: Equatable {
    let id = UUID()
    var label: String
    var amount: Double
    var outgoing: Bool = false
    var text: String? = nil
    var source: Int = 0
}

struct MoneyTravel: ViewModifier {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var burst: MoneyBurst?
    var source: Int

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.onChange(of: burst) { _, new in
                    guard let new, new.source == source else { return }
                    burst = nil
                    guard !reduceMotion, new.amount >= 1 else { return }
                    let r: CGRect = proxy.frame(in: .global)
                    store.flyChip(new.label, amount: new.amount, from: CGPoint(x: r.midX, y: r.midY), outgoing: new.outgoing, text: new.text)
                }
            }
        )
    }
}

extension View {
    func moneyTravel(_ burst: Binding<MoneyBurst?>, source: Int = 0) -> some View { modifier(MoneyTravel(burst: burst, source: source)) }
}

struct GoldReveal<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false
    var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.surface))
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .onAppear {
                guard !reduceMotion else { return }
                Motion.animate(Motion.quickAnimation) { shown = true }
            }
    }
}

struct GoldRingMark: View {
    var glyph: String
    var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.gold.opacity(0.18), lineWidth: 3)
            Circle().trim(from: 0, to: reduceMotion ? 1 : draw)
                .stroke(Theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            GlyphView(glyph: glyph, size: size * 0.42, weight: 1.6, tint: Theme.gold)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            Motion.animate(Motion.revealAnimation) { draw = 1 }
        }
    }
}
