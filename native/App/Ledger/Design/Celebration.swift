import SwiftUI

// The pieces of a celebration card (reward, goal complete, level up, unlock): a confetti burst, a counting reward figure and a
// pulsing Claim button. No assets: the confetti is drawn with a Canvas. Every piece is still under Reduce Motion.

/// One confetti piece, worked out from its index alone (deterministic, so the burst looks the same every time and is unit-tested).
struct ConfettiPiece: Equatable {
    var angle: Double
    var speed: Double
    var width: Double
    var height: Double
    var spin: Double
    var palette: Int

    /// A repeatable number in 0..<1 from an index and a salt.
    static func unit(_ i: Int, _ salt: Int) -> Double {
        let x: Double = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    static func make(count: Int) -> [ConfettiPiece] {
        var out: [ConfettiPiece] = []
        for i in 0..<max(0, count) {
            // A fan upwards: angles from -160 to -20 degrees (screen y points down), so pieces rise first and then fall.
            let angle: Double = (-160 + 140 * unit(i, 1)) * Double.pi / 180
            let piece = ConfettiPiece(angle: angle, speed: 150 + 190 * unit(i, 2), width: 5 + 4 * unit(i, 3), height: 3 + 4 * unit(i, 4),
                                      spin: (unit(i, 5) - 0.5) * 14, palette: i % 4)
            out.append(piece)
        }
        return out
    }

    /// Position (from the origin) and fade of the piece `t` seconds after the burst: it flies out, slows down and falls under gravity.
    func position(at t: Double) -> CGPoint {
        let drag: Double = 1 - exp(-3 * t)
        let x: Double = cos(angle) * speed * drag / 1.6
        let y: Double = sin(angle) * speed * drag / 1.6 + 260 * t * t
        return CGPoint(x: x, y: y)
    }

    static let duration: Double = 1.9

    static func opacity(at t: Double) -> Double {
        if t <= 1.1 { return 1 }
        return max(0, 1 - (t - 1.1) / (duration - 1.1))
    }
}

/// A one-time burst of confetti from the top middle of whatever it overlays. It draws for `ConfettiPiece.duration` seconds and then
/// removes itself. Does not take touches.
struct ConfettiBurst: View {
    var count: Int = 46
    /// Gold pieces only (the full-screen celebration); the default mixes in white and green.
    var goldOnly: Bool = false
    /// Where the burst starts as a fraction of the height; nil keeps the top-middle origin.
    var originFraction: CGFloat? = nil
    @State private var start: Date = Date()
    @State private var finished = false
    private let pieces: [ConfettiPiece]

    init(count: Int = 46, goldOnly: Bool = false, originFraction: CGFloat? = nil) {
        self.count = count
        self.goldOnly = goldOnly
        self.originFraction = originFraction
        self.pieces = ConfettiPiece.make(count: count)
    }

    var body: some View {
        Group {
            if !finished {
                TimelineView(.animation) { timeline in
                    canvas(elapsed: timeline.date.timeIntervalSince(start))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            start = Date()
            try? await Task.sleep(nanoseconds: UInt64((ConfettiPiece.duration + 0.1) * 1_000_000_000))
            finished = true
        }
    }

    private func canvas(elapsed: Double) -> some View {
        let list: [ConfettiPiece] = pieces
        let colors: [Color] = goldOnly ? [Theme.gold, Theme.goldDeep, Theme.gold, Theme.goldDeep] : [Theme.gold, Theme.goldDeep, Color.white, Theme.gain]
        let fraction: CGFloat? = originFraction
        return Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let origin = CGPoint(x: size.width / 2, y: fraction.map { $0 * size.height } ?? 24)
            for piece in list {
                ConfettiBurst.draw(piece, in: &ctx, origin: origin, t: elapsed, color: colors[piece.palette % colors.count])
            }
        }
    }

    private static func draw(_ piece: ConfettiPiece, in ctx: inout GraphicsContext, origin: CGPoint, t: Double, color: Color) {
        let alpha: Double = ConfettiPiece.opacity(at: t)
        if alpha <= 0 { return }
        let offset: CGPoint = piece.position(at: t)
        var c: GraphicsContext = ctx
        c.translateBy(x: origin.x + offset.x, y: origin.y + offset.y)
        c.rotate(by: Angle.radians(piece.spin * t))
        c.opacity = alpha
        let rect = CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height)
        c.fill(Path(rect), with: GraphicsContext.Shading.color(color))
    }
}

extension View {
    /// Throws a confetti burst over this view when it appears (nothing under Reduce Motion).
    func confettiBurst() -> some View { modifier(ConfettiBurstModifier()) }
}

private struct ConfettiBurstModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                // A canvas larger than the view, its origin on the view's middle, so the burst is not cut off at the view's edge.
                ConfettiBurst().frame(width: 340, height: 300).offset(y: 126)
            }
        }
    }
}

/// A reward amount that counts up from 0 in the large gold reward figure (about 0.9 s, after a short wait for the card to arrive).
struct RewardFigure: View {
    var amount: Double
    var format: (Double) -> String

    var body: some View {
        CountedFigure(value: amount, format: format, duration: 0.9, delay: 0.25)
            .popupText(.figure, variant: .reward)
            .lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// The Claim button of a celebration card: the sole-action champagne button with a gentle breathing pulse while it waits to be
/// pressed, and a success haptic when it is. No pulse under Reduce Motion.
struct ClaimButton: View {
    var title: String = "Claim"
    var identifier: String = "claim"
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        Button {
            Haptics.play(.success)
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(PopupPrimaryButtonStyle())
        .accessibilityIdentifier(identifier)
        .scaleEffect(breathe && !reduceMotion ? 1.03 : 1)
        .animation(reduceMotion ? nil : Motion.pulseAnimation, value: breathe)
        .onAppear { breathe = true }
    }
}

/// The full-screen moment for a trophy or a net-worth milestone (about 2 s): a dim backdrop, gold confetti, the art large in a gold
/// ring, the title, a reward that rolls up and a success haptic when the ring lands. The caller shows the plain card under Reduce Motion.
struct FullScreenCelebration<Badge: View>: View {
    var kicker: String
    var title: String
    var detail: String
    var reward: String
    var onClaim: () -> Void
    @ViewBuilder var badge: () -> Badge
    @State private var ringShown = false
    @State private var textShown = false
    @State private var claimShown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea().contentShape(Rectangle())
            ConfettiBurst(count: 110, goldOnly: true, originFraction: 0.42).ignoresSafeArea()
            VStack(spacing: Theme.Space.l) {
                Text(kicker).font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Theme.gold)
                    .opacity(textShown ? 1 : 0)
                badge()
                    .scaleEffect(ringShown ? 1 : 0.6).opacity(ringShown ? 1 : 0)
                Text(title).font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(Color.white)
                    .multilineTextAlignment(.center).opacity(textShown ? 1 : 0)
                if !detail.isEmpty {
                    Text(detail).font(.subheadline).foregroundStyle(Color.white.opacity(0.75))
                        .multilineTextAlignment(.center).opacity(textShown ? 1 : 0)
                }
                rewardView.opacity(textShown ? 1 : 0)
                ClaimButton(title: "Claim", identifier: "celebration-dismiss", action: onClaim)
                    .padding(.top, Theme.Space.s).opacity(claimShown ? 1 : 0).allowsHitTesting(claimShown)
            }
            .padding(.horizontal, Theme.Space.page)
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task {
            Motion.animate(Motion.moveAnimation) { ringShown = true }
            try? await Task.sleep(nanoseconds: 450_000_000)
            Haptics.play(.success)
            Motion.animate(Motion.revealAnimation) { textShown = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            Motion.animate(Motion.quickAnimation) { claimShown = true }
        }
    }

    /// The reward line; its first whole number counts up from 0 (CountedFigure), anything else shows as written.
    @ViewBuilder private var rewardView: some View {
        if reward.isEmpty {
            EmptyView()
        } else if let parts = FullScreenCelebration.rollParts(reward) {
            CountedFigure(value: parts.value, format: { (v: Double) -> String in parts.prefix + Int(saturating: v.rounded()).formatted() + parts.suffix },
                          tint: Theme.gold, duration: 0.9, delay: 0.5)
                .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        } else {
            Text(reward).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(Theme.gold)
        }
    }

    /// Splits "+25 legacy points" into "+", 25 and " legacy points"; nil when there is no whole number to roll.
    static func rollParts(_ text: String) -> (prefix: String, value: Double, suffix: String)? {
        let chars: [Character] = Array(text)
        guard let start = chars.firstIndex(where: { $0.isNumber }) else { return nil }
        var end: Int = start
        while end < chars.count, chars[end].isNumber || chars[end] == "," || chars[end] == "." { end += 1 }
        while end > start, !chars[end - 1].isNumber { end -= 1 }
        let digits: String = String(chars[start..<end]).replacingOccurrences(of: ",", with: "")
        guard !digits.contains("."), let v = Double(digits) else { return nil }
        return (String(chars[..<start]), v, String(chars[end...]))
    }
}
