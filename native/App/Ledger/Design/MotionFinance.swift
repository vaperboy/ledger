import SwiftUI

// Animation stage helpers (money, charts, goals, luxury). Each one is driven by a real value change and respects Reduce Motion.

// MARK: Profit glow

/// A soft green band sweeps once across a figure when `value` rises (0.8 s). Nothing for a fall, the first appearance or Reduce Motion.
struct ProfitGlow: ViewModifier {
    var value: Double
    @State private var phase: CGFloat = -0.6
    @State private var active: Bool = false
    @State private var token: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [Color.clear, Theme.gain, Color.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: geo.size.width * phase)
                        .opacity(active ? 0.85 : 0)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onChange(of: value) { old, new in
                guard new > old, !reduceMotion else { return }
                token += 1
                let mine: Int = token
                phase = -0.6
                active = true
                withAnimation(.easeInOut(duration: 0.8)) { phase = 1.1 }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    if mine == token { active = false }
                }
            }
    }
}

// MARK: Chart draws itself

/// Reveals a chart from left to right once, the first time it appears (700 ms). Instant under Reduce Motion.
struct DrawInOnce: ViewModifier {
    var duration: Double = 0.7
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
                if reduceMotion { progress = 1 } else { withAnimation(.easeOut(duration: duration)) { progress = 1 } }
            }
    }
}

// MARK: Debt falling

/// A debt or loan figure: rolls down and flashes red to neutral when it falls (`moneyFlash`), and the bar beside it should use `.animation(Motion.fill(...))`.
extension Motion {
    /// A progress bar or ring filling to a new value (500 ms ease-out); nil under Reduce Motion.
    static func fill(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.5) }
    /// A figure counting to a new value (350 ms); nil under Reduce Motion.
    static func count(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.35) }
}

// MARK: Gold pulse

/// One gold ring pulse (700 ms) outward from the view when `trigger` turns true: an achievement unlocked or a goal completed.
struct GoldPulse: ViewModifier {
    var trigger: Bool
    @State private var pulse: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                Circle().strokeBorder(Theme.gold, lineWidth: 2)
                    .scaleEffect(pulse ? 1.5 : 0.9)
                    .opacity(pulse ? 0 : (trigger ? 0.9 : 0))
                    .allowsHitTesting(false)
            }
            .onChange(of: trigger) { old, new in
                guard new, !old, !reduceMotion else { return }
                pulse = false
                withAnimation(.easeOut(duration: 0.7)) { pulse = true }
            }
    }
}

// MARK: Staggered reveal

/// A section fades and rises a few points in, `index` x 40 ms after the page appears; first appearance only.
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
                withAnimation(.easeOut(duration: 0.28).delay(Double(min(index, 12)) * 0.04)) { shown = true }
            }
    }
}

extension View {
    /// A soft green sweep across the figure when `value` rises (see `ProfitGlow`).
    func profitGlow(_ value: Double) -> some View { modifier(ProfitGlow(value: value)) }
    /// The chart draws itself from left to right the first time it appears (see `DrawInOnce`).
    func drawsItself(duration: Double = 0.7) -> some View { modifier(DrawInOnce(duration: duration)) }
    /// A gold ring pulse when `trigger` turns true (see `GoldPulse`).
    func goldPulse(_ trigger: Bool) -> some View { modifier(GoldPulse(trigger: trigger)) }
    /// Reveals this section 40 ms after the previous one (see `StaggerReveal`).
    func staggerReveal(_ index: Int) -> some View { modifier(StaggerReveal(index: index)) }
    /// A new row slides in from the top and fades; it leaves with a fade.
    func rowArrival() -> some View {
        transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
    }
}

// MARK: Payment notice and transfer chip (app shell)

/// The top-of-screen overlay of the shell: a big customer payment slides in and leaves after 2.5 s; a transfer chip fades and slides.
/// Never takes a tap, never blocks.
struct MotionOverlay: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if let n = store.paymentNotice {
                HStack(spacing: 8) {
                    Circle().fill(Theme.gain).frame(width: 7, height: 7)
                    Text("Payment received").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                    Text("+" + store.short(n.amount)).font(.system(size: 13.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.gain)
                    Text(n.from).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                .id(n.id)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: n.id) {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if store.paymentNotice?.id == n.id { withAnimation(Motion.standard(reduceMotion)) { store.dismissPaymentNotice() } }
                }
                .accessibilityElement(children: .combine)
            }
            if let c = store.transferChip {
                TransferChipView(chip: c)
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.arrive(reduceMotion), value: store.paymentNotice?.id)
        .allowsHitTesting(false)
    }
}

/// An amount chip that fades in, slides up 24 pt and fades out (1.4 s) toward the personal account, then clears itself.
struct TransferChipView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var chip: TransferChip
    @State private var step: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            Text(chip.label).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            Text("+" + store.short(chip.amount)).font(.system(size: 13.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.gold)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
        .opacity(step == 1 ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (step == 0 ? 24 : (step == 1 ? 0 : -24)))
        .task(id: chip.id) {
            step = 0
            withAnimation(.easeOut(duration: 0.35)) { step = 1 }
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeIn(duration: 0.4)) { step = 2 }
            try? await Task.sleep(nanoseconds: 450_000_000)
            if store.transferChip?.id == chip.id { store.clearChip() }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Luxury reveal

/// The card shown over a high-value purchase confirmation: a gold-edged panel whose edge draws round once (900 ms) while it fades in.
struct GoldReveal<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var edge: CGFloat = 0
    @State private var shown: Bool = false
    var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .trim(from: 0, to: reduceMotion ? 1 : edge)
                    .stroke(Theme.gold, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            )
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.35)) { shown = true }
                withAnimation(.easeInOut(duration: 0.9)) { edge = 1 }
            }
    }
}

// MARK: Milestone ring

/// The milestone mark: a gold ring that draws round (800 ms) with a single light shimmer sweeping across it, then rests. No particles.
struct GoldRingMark: View {
    var glyph: String
    var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: CGFloat = 0
    @State private var sweep: CGFloat = -0.4

    var body: some View {
        ZStack {
            Circle().stroke(Theme.gold.opacity(0.18), lineWidth: 3)
            Circle().trim(from: 0, to: reduceMotion ? 1 : draw)
                .stroke(Theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().stroke(Color.white.opacity(0.7), lineWidth: 3)
                .mask(
                    LinearGradient(colors: [Color.clear, Color.white, Color.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: size * 0.4).offset(x: size * sweep)
                )
                .opacity(reduceMotion ? 0 : 0.8)
            GlyphView(glyph: glyph, size: size * 0.42, weight: 1.6, tint: Theme.gold)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8)) { draw = 1 }
            withAnimation(.easeInOut(duration: 0.6).delay(0.5)) { sweep = 0.5 }
        }
    }
}
