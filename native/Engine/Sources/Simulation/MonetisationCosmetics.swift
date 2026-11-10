import Foundation
import GameCore

public enum Cosmetics {
    public struct Badge: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var symbol: String
        public var premium: Bool
    }

    public struct Palette: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var red: Double, green: Double, blue: Double
        public var premium: Bool
    }

    public static let defaultBadgeID = "logo.default"
    public static let defaultThemeID = "gold"

    private static let file: JSONValue = ContentFile.load("cosmetics", "badges_themes")

    public static let badges: [Badge] = Cosmetics.file["badges"].array.map { (e: JSONValue) -> Badge in
        Badge(id: e["id"].string, title: e["title"].string, symbol: e["symbol"].string, premium: e["premium"].bool)
    }

    public static let themes: [Palette] = Cosmetics.file["themes"].array.map { (e: JSONValue) -> Palette in
        Palette(id: e["id"].string, title: e["title"].string, red: e["red"].double, green: e["green"].double, blue: e["blue"].double, premium: e["premium"].bool)
    }

    public static func badge(_ id: String) -> Badge { badges.first { $0.id == id } ?? badges[0] }
    public static func theme(_ id: String) -> Palette { themes.first { $0.id == id } ?? themes[0] }

    public static func isBadgeUnlocked(_ id: String, earned: [String], pro: Bool) -> Bool {
        guard let b = badges.first(where: { $0.id == id }) else { return false }
        if id == defaultBadgeID { return true }
        return b.premium ? pro : earned.contains(id)
    }

    public static func isThemeUnlocked(_ id: String, pro: Bool) -> Bool {
        guard let t = themes.first(where: { $0.id == id }) else { return false }
        return !t.premium || pro
    }

    public static func resolvedBadge(_ selected: String?, earned: [String], pro: Bool) -> Badge {
        guard let s = selected, isBadgeUnlocked(s, earned: earned, pro: pro) else { return badges[0] }
        return badge(s)
    }

    public static func resolvedTheme(_ selected: String?, pro: Bool) -> Palette {
        guard let s = selected, isThemeUnlocked(s, pro: pro) else { return themes[0] }
        return theme(s)
    }

    public static func careerBadgesLeft(earned: [String]) -> Int {
        badges.filter { !$0.premium && $0.id != defaultBadgeID && !earned.contains($0.id) }.count
    }
}

public enum HomeProgress {
    public static func clamp(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }

    public static func percent(_ p: Double) -> Int {
        let c = clamp(p)
        return c >= 1 ? 100 : min(99, Int(saturating: (c * 100).rounded(.down)))
    }

    public static func runwayDays(cash: [Double]) -> Int? {
        guard cash.count >= 3, let last = cash.last, let first = cash.first else { return nil }
        let perDay: Double = (first - last) / Double(cash.count - 1)
        guard perDay > 0.0001, last > 0 else { return nil }
        let d: Double = last / perDay
        return d.isFinite ? Int(min(d, 9999)) : nil
    }

    public static func normalised(_ v: [Double]) -> [Double] {
        guard let lo = v.min(), let hi = v.max() else { return [] }
        guard hi - lo > 1e-9 else { return v.map { _ in 0.5 } }
        return v.map { ($0 - lo) / (hi - lo) }
    }
}
