import Foundation
import GameCore

public enum StandingWords {
    public static func awareness(_ value: Double) -> String {
        switch value {
        case ..<12: return "Unknown"
        case ..<30: return "Few know you"
        case ..<55: return "Known locally"
        case ..<78: return "Well known"
        default: return "Famous"
        }
    }

    public static func reputation(_ value: Double) -> String {
        switch value {
        case ..<25: return "Poor"
        case ..<50: return "Fair"
        case ..<70: return "Good"
        case ..<85: return "Very good"
        default: return "Excellent"
        }
    }

    public static func pressImage(_ axis: String, _ value: Double) -> String {
        let (low, mid, high, top): (String, String, String, String)
        switch axis {
        case "trust": (low, mid, high, top) = ("Doubted", "Not yet trusted", "Trusted", "Deeply trusted")
        case "bold": (low, mid, high, top) = ("Cautious", "Measured", "Bold", "Fearless")
        default: (low, mid, high, top) = ("Seen as cold", "Seen as neutral", "Seen as caring", "Seen as very caring")
        }
        switch value {
        case ..<30: return low
        case ..<55: return mid
        case ..<78: return high
        default: return top
        }
    }

    public static func pressImage(trust: Double, bold: Double, care: Double) -> [(axis: String, word: String)] {
        [("Trust", pressImage("trust", trust)), ("Boldness", pressImage("bold", bold)), ("Care", pressImage("care", care))]
    }

    public static func starGlyphs(_ rating: Double) -> String {
        let filled: Int = min(5, max(0, Int(saturating: rating.rounded())))
        return String(repeating: "★", count: filled) + String(repeating: "☆", count: 5 - filled)
    }

    public static func ratingText(_ rating: Double) -> String {
        starGlyphs(rating) + String(format: " %.1f / 5", rating)
    }
}

public extension MarketMap.Knowledge.Level {
    var canDrawShareGraph: Bool { self != .feeling }
}
