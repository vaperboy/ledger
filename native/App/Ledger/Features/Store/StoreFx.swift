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

/// Kept for callers; the Store no longer floats or sweeps a sheen, so it stays light on every phone.
struct StoreFloat: ViewModifier {
    var amplitude: CGFloat = 3
    var period: Double = 4.2
    var phase: Double = 0

    func body(content: Content) -> some View { content }
}

struct StoreSheen: ViewModifier {
    var radius: CGFloat
    var enabled = true
    var period: Double = 4.6
    var offset: Double = 0
    var strength: Double = 0.30

    func body(content: Content) -> some View { content }
}

extension View {
    func storeAppear(_ index: Int = 0) -> some View { modifier(StoreAppear(index: index)) }
    func storeFloat(amplitude: CGFloat = 3, period: Double = 4.2, phase: Double = 0) -> some View { modifier(StoreFloat(amplitude: amplitude, period: period, phase: phase)) }
    func storeSheen(radius: CGFloat, enabled: Bool = true, offset: Double = 0, strength: Double = 0.30) -> some View {
        modifier(StoreSheen(radius: radius, enabled: enabled, offset: offset, strength: strength))
    }
}

/// A flat card surface tinted with a colour; a glowing one gets a brighter edge, no animation.
struct StoreSurface: View {
    var tint: Color = Theme.gold
    var glow = false
    var radius: CGFloat = Theme.Radius.hero

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.22), Theme.surfaceRaised], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(tint.opacity(glow ? 0.75 : 0.3), lineWidth: glow ? 1.2 : 0.8))
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
    var body: some View { Text(Int(saturating: value.rounded()).formatted()) }
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
        case .elite: return [Color(hex: 0xF0CF6A), Color(hex: 0x3A2A08)]
        case .event1, .event2, .event3, .event4, .event5, .event6:
            let c: [UInt32] = EventBoxes.box(kind)?.colors ?? []
            return [Color(hex: c.first ?? 0xE5577A), Color(hex: c.count > 1 ? c[1] : 0x3A0F1E)]
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

/// Still rays behind a reveal.
struct StoreRays: View {
    var tint: Color
    var size: CGFloat
    var strength: Double = 0.5

    var body: some View {
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
            .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: size * 0.1, endRadius: size / 2))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
