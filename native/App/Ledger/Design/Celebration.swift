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
    @State private var start: Date = Date()
    @State private var finished = false
    private let pieces: [ConfettiPiece]

    init(count: Int = 46) {
        self.count = count
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
        let colors: [Color] = [Theme.gold, Theme.goldDeep, Color.white, Theme.gain]
        return Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let origin = CGPoint(x: size.width / 2, y: 24)
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
