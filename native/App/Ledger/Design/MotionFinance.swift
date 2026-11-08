import SwiftUI

// Animation helpers (money, charts, goals, luxury). Each one is driven by a real value change and respects Reduce Motion.

// MARK: Profit glow

/// Retired decoration: the green sweep across a rising figure. Kept as a no-op so call sites compile; `moneyFlash` carries the change.
struct ProfitGlow: ViewModifier {
    var value: Double
    func body(content: Content) -> some View { content }
}

// MARK: Chart draws itself

/// Reveals a chart from left to right once, the first time it appears (`reveal`, 0.6 s; `duration` is kept for older call sites).
/// Instant under Reduce Motion.
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

// MARK: Debt falling

/// A debt or loan figure: rolls down and flashes red to neutral when it falls (`moneyFlash`), and the bar beside it should use `.animation(Motion.fill(...))`.
extension Motion {
    /// A progress bar or ring filling to a new value (`quick`, 0.22 s); nil under Reduce Motion.
    static func fill(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Motion.quickAnimation }
    /// A figure counting to a new value (`quick`, 0.22 s); nil under Reduce Motion.
    static func count(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : Motion.quickAnimation }
}

// MARK: Gold pulse

/// Retired decoration: the gold ring pulse. Kept as a no-op so call sites compile.
struct GoldPulse: ViewModifier {
    var trigger: Bool
    func body(content: Content) -> some View { content }
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
                Motion.animate(Motion.quickAnimation.delay(Double(min(index, 12)) * 0.04)) { shown = true }
            }
    }
}

extension View {
    /// Retired: does nothing (see `ProfitGlow`).
    func profitGlow(_ value: Double) -> some View { modifier(ProfitGlow(value: value)) }
    /// The chart draws itself from left to right the first time it appears (see `DrawInOnce`).
    func drawsItself(duration: Double = Motion.revealSeconds) -> some View { modifier(DrawInOnce(duration: duration)) }
    /// Retired: does nothing (see `GoldPulse`).
    func goldPulse(_ trigger: Bool) -> some View { modifier(GoldPulse(trigger: trigger)) }
    /// Reveals this section 40 ms after the previous one (see `StaggerReveal`).
    func staggerReveal(_ index: Int) -> some View { modifier(StaggerReveal(index: index)) }
    /// A new row slides in from the top and fades; it leaves with a fade.
    func rowArrival() -> some View {
        transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
    }
}

// MARK: Payment notice and transfer chip (app shell)

/// The top-of-screen overlay of the shell: a transfer chip fades and slides.
/// Never takes a tap, never blocks.
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

/// An amount chip, then it clears itself. Without an origin it fades in, slides up 24 pt and fades out (1.4 s). With one (`MoneyTravel`)
/// it flies from that point to its resting place at the top of the screen in 0.5 s, where the net worth is, and fades.
struct TransferChipView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var chip: TransferChip
    /// The overlay's frame in screen space, to turn the chip's origin into an offset from where it rests.
    var top: CGRect = .zero
    @State private var step: Int = 0

    private var flies: Bool { chip.origin != nil && !reduceMotion }

    /// Distance from the resting place (top centre, one chip below the safe area) back to where the money came from.
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

// MARK: Money travel

/// One payment to show: the label, the amount, and whether it leaves the player's money (payroll) or arrives (a loan, a sale).
struct MoneyBurst: Equatable {
    let id = UUID()
    var label: String
    var amount: Double
    var outgoing: Bool = false
    /// The amount in the payer's own currency ("£2.4k"); nil shows it in the home currency.
    var text: String? = nil
    /// Which view sends it when several share one binding (a list of rows); 0 for a lone view.
    var source: Int = 0
}

/// Sends a chip from this view to the net worth at the top of the screen whenever `burst` is set (then clears it). Off under Reduce Motion
/// and for amounts under one unit, so only real money moves.
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
    /// The one money-travel hook: set the binding to a `MoneyBurst` after a payment and a chip flies from this view to the net worth (0.5 s).
    /// `source` tells rows that share one binding apart (the burst's `source` must match).
    func moneyTravel(_ burst: Binding<MoneyBurst?>, source: Int = 0) -> some View { modifier(MoneyTravel(burst: burst, source: source)) }
}

// MARK: Luxury reveal

/// The card shown over a high-value purchase confirmation: a plain surface panel that fades in (the self-drawing gold edge is retired).
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

// MARK: Milestone ring

/// The milestone mark: a gold ring that draws round (800 ms), then rests. No shimmer, no particles.
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
