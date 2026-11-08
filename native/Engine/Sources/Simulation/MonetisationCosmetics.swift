import Foundation
import GameCore

/// Pro cosmetics: logo badges and colour themes. Pure rules, no SwiftUI. Nothing here changes a sim number.
/// Fairness: every badge earned in the career is free to wear for ever; the extra premium badges and the colour themes are Pro.
/// A lapsed Pro falls back to the default badge and theme (the choice is kept and returns with Pro).
public enum Cosmetics {
    public struct Badge: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// An SF Symbol name.
        public var symbol: String
        /// True: Pro only. False: the default badge or one earned in the career.
        public var premium: Bool
    }

    public struct Palette: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// Accent colour as red, green, blue in 0...1.
        public var red: Double, green: Double, blue: Double
        public var premium: Bool
    }

    public static let defaultBadgeID = "logo.default"
    public static let defaultThemeID = "gold"

    /// Default first, then the career badges in the order the career hands them out, then the premium ones.
    public static let badges: [Badge] = [
        Badge(id: "logo.default", title: "Briefcase", symbol: "briefcase.fill", premium: false),
        Badge(id: "logo.star", title: "Star", symbol: "star.fill", premium: false),
        Badge(id: "logo.bell", title: "Bell", symbol: "bell.fill", premium: false),
        Badge(id: "logo.coin", title: "Gold coin", symbol: "dollarsign.circle.fill", premium: false),
        Badge(id: "logo.laurel", title: "Laurel", symbol: "rosette", premium: false),
        Badge(id: "logo.seal", title: "Seal", symbol: "checkmark.seal.fill", premium: false),
        Badge(id: "logo.cup", title: "Cup", symbol: "trophy.fill", premium: false),
        Badge(id: "logo.banner", title: "Banner", symbol: "flag.fill", premium: false),
        Badge(id: "logo.diamond", title: "Diamond", symbol: "diamond.fill", premium: false),
        Badge(id: "logo.crown", title: "Crown", symbol: "sparkles", premium: false),
        Badge(id: "logo.skyline", title: "Skyline", symbol: "building.2.fill", premium: false),
        Badge(id: "logo.crest", title: "Gold crest", symbol: "shield.fill", premium: false),
        Badge(id: "pro.bolt", title: "Bolt", symbol: "bolt.fill", premium: true),
        Badge(id: "pro.moon", title: "Moon", symbol: "moon.stars.fill", premium: true),
        Badge(id: "pro.leaf", title: "Leaf", symbol: "leaf.fill", premium: true),
        Badge(id: "pro.plane", title: "Jet", symbol: "paperplane.fill", premium: true),
        Badge(id: "pro.heart", title: "Heart", symbol: "heart.fill", premium: true),
        Badge(id: "pro.hare", title: "Hare", symbol: "hare.fill", premium: true)
    ]

    public static let themes: [Palette] = [
        Palette(id: "gold", title: "Champagne", red: 0.839, green: 0.722, blue: 0.537, premium: false),
        Palette(id: "emerald", title: "Emerald", red: 0.31, green: 0.78, blue: 0.56, premium: true),
        Palette(id: "sapphire", title: "Sapphire", red: 0.35, green: 0.62, blue: 0.95, premium: true),
        Palette(id: "rose", title: "Rose", red: 0.94, green: 0.48, blue: 0.62, premium: true),
        Palette(id: "violet", title: "Violet", red: 0.67, green: 0.52, blue: 0.95, premium: true),
        Palette(id: "ember", title: "Ember", red: 0.96, green: 0.52, blue: 0.27, premium: true)
    ]

    public static func badge(_ id: String) -> Badge { badges.first { $0.id == id } ?? badges[0] }
    public static func theme(_ id: String) -> Palette { themes.first { $0.id == id } ?? themes[0] }

    /// Whether a badge may be worn: the default always, a career badge once earned, a premium badge with Pro.
    public static func isBadgeUnlocked(_ id: String, earned: [String], pro: Bool) -> Bool {
        guard let b = badges.first(where: { $0.id == id }) else { return false }
        if id == defaultBadgeID { return true }
        return b.premium ? pro : earned.contains(id)
    }

    /// Whether a theme may be used: the default always, the others with Pro.
    public static func isThemeUnlocked(_ id: String, pro: Bool) -> Bool {
        guard let t = themes.first(where: { $0.id == id }) else { return false }
        return !t.premium || pro
    }

    /// The badge to show for a saved choice: the choice if it may be worn now, else the default.
    public static func resolvedBadge(_ selected: String?, earned: [String], pro: Bool) -> Badge {
        guard let s = selected, isBadgeUnlocked(s, earned: earned, pro: pro) else { return badges[0] }
        return badge(s)
    }

    public static func resolvedTheme(_ selected: String?, pro: Bool) -> Palette {
        guard let s = selected, isThemeUnlocked(s, pro: pro) else { return themes[0] }
        return theme(s)
    }

    /// How many career badges are still to win.
    public static func careerBadgesLeft(earned: [String]) -> Int {
        badges.filter { !$0.premium && $0.id != defaultBadgeID && !earned.contains($0.id) }.count
    }
}

/// Maths for the Home rank strip and the Insights charts (pure, so it is testable on Linux).
public enum HomeProgress {
    /// 0...1, clamped; a non-number counts as 0.
    public static func clamp(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }

    /// Whole percent for a ring label (never 100 until it is truly full).
    public static func percent(_ p: Double) -> Int {
        let c = clamp(p)
        return c >= 1 ? 100 : min(99, Int(saturating: (c * 100).rounded(.down)))
    }

    /// Days of cash left at the average daily outflow seen in the series; nil when cash is not falling (no runway to speak of).
    /// `cash` is one value per day, oldest first.
    public static func runwayDays(cash: [Double]) -> Int? {
        guard cash.count >= 3, let last = cash.last, let first = cash.first else { return nil }
        let perDay: Double = (first - last) / Double(cash.count - 1)
        guard perDay > 0.0001, last > 0 else { return nil }
        let d: Double = last / perDay
        return d.isFinite ? Int(min(d, 9999)) : nil
    }

    /// Scales a series to 0...1 for drawing; a flat series sits in the middle.
    public static func normalised(_ v: [Double]) -> [Double] {
        guard let lo = v.min(), let hi = v.max() else { return [] }
        guard hi - lo > 1e-9 else { return v.map { _ in 0.5 } }
        return v.map { ($0 - lo) / (hi - lo) }
    }
}
