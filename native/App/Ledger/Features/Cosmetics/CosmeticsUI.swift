import SwiftUI
import GameCore
import Simulation

enum CosmeticKeys {
    static let badge: String = "cosmetics.badge"
    static let theme: String = "cosmetics.theme"
}

extension Cosmetics.Palette {
    var accent: Color { Color(red: red, green: green, blue: blue) }
}

struct CosmeticBadgeView: View {
    var badge: Cosmetics.Badge
    var tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: badge.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.16)))
            .overlay(Circle().strokeBorder(tint.opacity(0.55), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct AccentRing: View {
    var progress: Double
    var tint: Color
    var size: CGFloat = 44

    var body: some View {
        let width: CGFloat = max(3, size * 0.085)
        let arc: Double = HomeProgress.clamp(progress)
        return ZStack {
            Circle().stroke(Theme.border, lineWidth: width)
            Circle().trim(from: 0, to: arc)
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CountUpPercent: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(saturating: value.rounded()))%").monospacedDigit()
    }
}
