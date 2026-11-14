import SwiftUI
import Simulation

/// How long the build-up lasts and how long a face-down card waits before it flips, by best rarity.
enum LootTiming {
    static func buildUp(_ r: BoxRarity) -> Double {
        switch r {
        case .common, .rare: return 2.0
        case .epic: return 2.4
        case .legendary: return 3.4
        }
    }

    static func hold(_ r: BoxRarity) -> Double {
        switch r {
        case .common: return 0.35
        case .rare: return 0.45
        case .epic: return 0.7
        case .legendary: return 1.1
        }
    }
}

@MainActor
enum LootHaptics {
    /// Rising taps while the box builds up.
    static func buildUp(progress: Double) {
        if progress > 0.6 { Haptics.countDone() } else { Haptics.tap() }
    }

    /// One pulse for a plain card, more for the rare ones, a long run for ultra-rare.
    static func flip(_ r: BoxRarity) async {
        switch r {
        case .common:
            Haptics.tap()
        case .rare:
            Haptics.success()
        case .epic:
            Haptics.success()
            try? await Task.sleep(nanoseconds: 180_000_000)
            Haptics.success()
        case .legendary:
            Haptics.countDone()
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 140_000_000)
                Haptics.success()
            }
        }
    }
}

/// The box opening: its clip (or a shaking still when there is none, or with Reduce Motion or Low Power Mode) under a glow
/// in the colour of the best rarity inside, rising until it opens. Every box kind gets the glow; the clip is the box's own or a shared one.
struct BoxShake: View {
    var kind: BoxKind
    var rarity: BoxRarity
    var start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let total: Double = LootTiming.buildUp(rarity)
        let glow: LootGlow = LootGlow(rarity)
        let clip: URL? = reduceMotion || lowPower ? nil : ArtLibrary.openingURL(kind)
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { (tl: TimelineViewDefaultContext) in
            let t: Double = tl.date.timeIntervalSince(start)
            let p: Double = min(1, max(0, t / total))
            let rise: Double = p * p
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [glow.color.opacity(glow.strength * (0.15 + 0.75 * rise)), .clear], center: .center, startRadius: 4, endRadius: 50 + 110 * rise))
                    .frame(width: 280, height: 280)
                Circle()
                    .strokeBorder(glow.color.opacity(0.55 * rise), lineWidth: glow.flashy ? 3 : 2)
                    .frame(width: 120 + 130 * CGFloat(rise), height: 120 + 130 * CGFloat(rise))
                if let clip {
                    OneShotClip(url: clip, duration: total)
                        .frame(width: 200, height: 200)
                        .mask(RadialGradient(colors: [.white, .white, .clear], center: .center, startRadius: 10, endRadius: 100))
                        .overlay(
                            // the box picks up the rarity colour as the lid starts to open
                            RadialGradient(colors: [glow.color.opacity(glow.strength * 0.6 * rise), .clear], center: .center, startRadius: 2, endRadius: 90)
                                .blendMode(.plusLighter)
                                .allowsHitTesting(false)
                        )
                } else {
                    let shake: Double = reduceMotion ? 0 : 1
                    BoxArt(kind: kind, size: 110)
                        .scaleEffect(1 + 0.14 * rise * shake)
                        .rotationEffect(.degrees(shake * sin(t * (16 + 24 * p)) * (1 + 11 * rise)))
                        .offset(x: CGFloat(shake * sin(t * 47) * (0.5 + 5 * rise)))
                        .shadow(color: glow.color.opacity(0.8 * rise), radius: 6 + 24 * CGFloat(rise))
                }
                if glow.flashy && !reduceMotion {
                    LootSparks(t: t, rise: rise, color: glow.color, count: rarity == .legendary ? 28 : 16)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { (_: Notification) in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .accessibilityHidden(true)
    }
}

/// The opening glow of a rarity: grey, blue, purple or gold; purple and gold are brighter and throw sparks.
struct LootGlow {
    var color: Color
    var strength: Double
    var flashy: Bool

    init(_ r: BoxRarity) {
        switch r {
        case .common: color = Color(hex: 0xA7ABB3); strength = 0.55; flashy = false
        case .rare: color = Color(hex: 0x4C8DFF); strength = 0.75; flashy = false
        case .epic: color = Color(hex: 0xA65CFF); strength = 1.0; flashy = true
        case .legendary: color = Color(hex: 0xFFC93C); strength = 1.0; flashy = true
        }
    }
}

/// Sparks rising round the box, faster and denser as the opening builds up.
private struct LootSparks: View {
    var t: Double
    var rise: Double
    var color: Color
    var count: Int

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let c: CGPoint = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.blendMode = .plusLighter
            for i in 0..<count {
                let seed: Double = Double(i) * 2.399
                let life: Double = (t * (0.6 + 0.5 * rise) + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                let angle: Double = seed + t * 0.4
                let dist: Double = (40 + 90 * life) * (0.6 + 0.6 * rise)
                let x: Double = Double(c.x) + cos(angle) * dist
                let y: Double = Double(c.y) + sin(angle) * dist * 0.7 - 40 * life
                let r: Double = (1.5 + 2.5 * (1 - life)) * (0.6 + rise)
                let rect: CGRect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity((1 - life) * (0.3 + 0.7 * rise))))
            }
        }
        .frame(width: 280, height: 260)
        .allowsHitTesting(false)
    }
}

/// A view that turns around the vertical axis. The face switches at the half turn, so it works while the angle animates.
struct FlipFaces<Front: View, Back: View>: View, Animatable {
    var angle: Double
    var front: Front
    var back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let up: Bool = angle >= 90
        let bump: CGFloat = 1 + 0.08 * CGFloat(sin(angle * Double.pi / 180))
        return ZStack {
            back.opacity(up ? 0 : 1)
            front.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0)).opacity(up ? 1 : 0)
        }
        .scaleEffect(bump)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
    }
}

/// The picture for a reward: the item, a coin or a banknote.
struct LootArt: View {
    var entry: HaulEntry
    var size: CGFloat

    var body: some View {
        switch entry.kind {
        case .cosmetic:
            if let c = entry.cosmetic { ItemArt(reward: c.item, rarity: c.rarity, size: size, wide: true) } else { Image(systemName: "paintpalette.fill").font(.system(size: size * 0.7)).foregroundStyle(Theme.ink) }
        case .artifact:
            if let d = entry.artifact { ItemArt(artifact: d, size: size) } else { LedgerGlyph(glyph: Glyph.luxury, size: size * 0.8, tint: Theme.ink) }
        case .gold: RewardTile(kind: .gold, size: size)
        case .cash: RewardTile(kind: .money, size: size)
        }
    }
}

private struct LootCardBack: View {
    var tint: Color
    var width: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: 0x2A2C31), Color(hex: 0x15161A)], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(tint.opacity(0.7), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: width * 0.1, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 1).padding(width * 0.08)
            Image(systemName: "questionmark").font(.system(size: width * 0.36, weight: .semibold)).foregroundStyle(tint.opacity(0.85))
        }
        .frame(width: width, height: width * 1.4)
    }
}

private struct LootCardFront: View {
    var entry: HaulEntry
    var width: CGFloat

    var body: some View {
        let tint: Color = entry.rarity.tint
        let shape = RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
        VStack(spacing: width * 0.05) {
            Spacer(minLength: 0)
            LootArt(entry: entry, size: width * 0.5)
            Spacer(minLength: 0)
            Text(entry.kind == .gold ? "+" + entry.goldTotal.formatted() + " gold" : entry.title)
                .textStyle(.caption, tint: Theme.ink, weight: .semibold).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.5)
            Text(entry.rarity.title).textStyle(.label, tint: tint).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(width * 0.08)
        .frame(width: width, height: width * 1.4)
        .background(shape.fill(LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(shape.strokeBorder(tint, lineWidth: 1.5))
        .clipShape(shape)
        .shadow(color: tint.opacity(entry.rarity >= .epic ? 0.7 : 0.35), radius: entry.rarity >= .epic ? width * 0.18 : width * 0.1)
    }
}

/// A reward as a card: face down at first, then it turns to show the item, its rarity colour and its name.
/// With Reduce Motion it cross-fades instead of turning.
struct LootFlipCard: View {
    var entry: HaulEntry
    var faceUp: Bool
    var width: CGFloat = 124
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint: Color = entry.rarity.tint
        Group {
            if reduceMotion {
                ZStack {
                    LootCardBack(tint: tint, width: width).opacity(faceUp ? 0 : 1)
                    LootCardFront(entry: entry, width: width).opacity(faceUp ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.4), value: faceUp)
            } else {
                FlipFaces(angle: faceUp ? 180 : 0, front: LootCardFront(entry: entry, width: width), back: LootCardBack(tint: tint, width: width))
                    .animation(.easeInOut(duration: 0.75), value: faceUp)
            }
        }
        .frame(width: width, height: width * 1.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceUp ? entry.title + ", " + entry.rarity.title : "Face-down card")
    }
}
