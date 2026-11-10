import SwiftUI
import Simulation

struct StoreAppear: ViewModifier {
    var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true; return }
                Motion.animate(.spring(response: 0.5, dampingFraction: 0.78).delay(Double(min(index, 8)) * 0.07)) { shown = true }
            }
    }
}

struct StoreFloat: ViewModifier {
    var amplitude: CGFloat = 3
    var period: Double = 4.2
    var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                let t: Double = tl.date.timeIntervalSinceReferenceDate
                content.offset(y: CGFloat(sin((t / period + phase) * 2 * Double.pi)) * amplitude)
            }
        }
    }
}

struct StoreSheen: ViewModifier {
    var radius: CGFloat
    var enabled = true
    var period: Double = 4.6
    var offset: Double = 0
    var strength: Double = 0.30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if enabled && !reduceMotion {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    let t: Double = (tl.date.timeIntervalSinceReferenceDate + offset).truncatingRemainder(dividingBy: period) / period
                    let sweeping: Bool = t < 0.26
                    let s: Double = min(1, t / 0.26)
                    GeometryReader { (g: GeometryProxy) in
                        LinearGradient(colors: [.clear, Color.white.opacity(strength), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.4, height: g.size.height * 1.8)
                            .rotationEffect(.degrees(16))
                            .offset(x: -g.size.width * 0.5 + g.size.width * 1.6 * s, y: -g.size.height * 0.4)
                            .opacity(sweeping ? 1 : 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .allowsHitTesting(false)
                }
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}

extension View {
    func storeAppear(_ index: Int = 0) -> some View { modifier(StoreAppear(index: index)) }
    func storeFloat(amplitude: CGFloat = 3, period: Double = 4.2, phase: Double = 0) -> some View { modifier(StoreFloat(amplitude: amplitude, period: period, phase: phase)) }
    func storeSheen(radius: CGFloat, enabled: Bool = true, offset: Double = 0, strength: Double = 0.30) -> some View {
        modifier(StoreSheen(radius: radius, enabled: enabled, offset: offset, strength: strength))
    }
}

struct StoreSurface: View {
    var tint: Color = Theme.gold
    var glow = false
    var radius: CGFloat = Theme.Radius.hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if glow && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                let s: Double = (sin(tl.date.timeIntervalSinceReferenceDate / 2.8 * 2 * Double.pi) + 1) / 2
                card(shadow: 0.26 + 0.22 * s, blur: 14 + 8 * s)
            }
        } else {
            card(shadow: glow ? 0.34 : 0, blur: 16)
        }
    }

    private func card(shadow: Double, blur: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.16), Theme.surfaceRaised, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(tint.opacity(glow ? 0.65 : 0.28), lineWidth: glow ? 1.2 : 0.8))
            .shadow(color: tint.opacity(shadow), radius: blur, y: 2)
    }
}

struct StoreTag: View {
    var text: String
    var tint: Color = Theme.gold

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint))
            .fixedSize()
    }
}

struct StoreCoin: View {
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.goldLight, Theme.gold, Theme.goldDeep], center: .topLeading, startRadius: 1, endRadius: size))
            .overlay(Circle().strokeBorder(Theme.goldDeep.opacity(0.8), lineWidth: max(1, size / 14)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: max(0.5, size / 28)).padding(size * 0.2))
            .frame(width: size, height: size)
            .storeSheen(radius: size / 2, offset: 1.3, strength: 0.45)
            .accessibilityHidden(true)
    }
}

struct StoreCoinHeap: View {
    var tier: Int

    var body: some View {
        ZStack {
            ForEach(0..<max(1, min(5, tier)), id: \.self) { (i: Int) in
                StoreCoin(size: 26)
                    .offset(x: CGFloat(i % 2 == 0 ? -1 : 1) * CGFloat(i) * 3.5, y: -CGFloat(i) * 5)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

struct CountingNumber: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(Int(value.rounded()).formatted()) }
}

struct BoxArt: View {
    var kind: BoxKind
    var size: CGFloat = 84

    private var colors: [Color] {
        switch kind {
        case .free: return [Color(hex: 0x7FC79B), Color(hex: 0x2F5A44)]
        case .cabinet: return [Color(hex: 0xD6B889), Color(hex: 0x7A5A2E)]
        case .grand: return [Color(hex: 0xB59AD6), Color(hex: 0x4B3470)]
        case .cardBasic: return [Color(hex: 0x8FB4C9), Color(hex: 0x2E4A5C)]
        case .cardPremium: return [Color(hex: 0xC9A0D6), Color(hex: 0x4A2E5C)]
        case .cardElite: return [Color(hex: 0xE6C463), Color(hex: 0x6B4E12)]
        }
    }

    var body: some View {
        let w: CGFloat = size
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.1, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: w * 0.62)
                .offset(y: w * 0.14)
            RoundedRectangle(cornerRadius: w * 0.1, style: .continuous)
                .fill(LinearGradient(colors: [colors[0].opacity(0.95), colors[0].opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 1.04, height: w * 0.3)
                .offset(y: -w * 0.18)
            Rectangle().fill(Theme.goldLight.opacity(0.85)).frame(width: w * 0.14, height: w * 0.62).offset(y: w * 0.14)
            Image(systemName: "diamond.fill").font(.system(size: w * 0.2)).foregroundStyle(Theme.accentInk.opacity(0.85)).offset(y: w * 0.02)
        }
        .frame(width: w * 1.04, height: w * 0.95)
        .storeSheen(radius: w * 0.1, offset: Double(kind.price % 7) * 0.5)
        .shadow(color: colors[0].opacity(0.35), radius: 12, y: 4)
        .accessibilityHidden(true)
    }
}

struct StoreRays: View {
    var tint: Color
    var size: CGFloat
    var strength: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            rays(angle: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                rays(angle: tl.date.timeIntervalSinceReferenceDate * 9)
            }
        }
    }

    private func rays(angle: Double) -> some View {
        let count: Int = 10
        var stops: [Gradient.Stop] = []
        for i in 0..<count {
            let a: Double = Double(i) / Double(count)
            let b: Double = Double(i + 1) / Double(count)
            stops.append(Gradient.Stop(color: tint.opacity(0), location: a))
            stops.append(Gradient.Stop(color: tint.opacity(strength), location: a + (b - a) / 2))
            stops.append(Gradient.Stop(color: tint.opacity(0), location: b))
        }
        return AngularGradient(gradient: Gradient(stops: stops), center: .center)
            .rotationEffect(.degrees(angle))
            .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: size * 0.1, endRadius: size / 2))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
