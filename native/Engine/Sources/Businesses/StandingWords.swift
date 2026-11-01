import Foundation

/// Words for the standing figures the screens must not show as bare numbers: how well known a company is, how well it is regarded, and
/// a rating as stars. One shared helper, so Marketing, Customers, Overview and the Reviews app say the same thing. The thresholds read the
/// engine's own values: awareness and reputation are 0...100 (`Company.awareness`, `Company.reputation`; a new company starts at 25 and 45),
/// a rating is 1...5 (`Reviews.rating`).
public enum StandingWords {
    /// How well known the company is. Below 12 hardly anyone has heard of it; from 78 up it is a household name.
    public static func awareness(_ value: Double) -> String {
        switch value {
        case ..<12: return "Unknown"
        case ..<30: return "Few know you"
        case ..<55: return "Known locally"
        case ..<78: return "Well known"
        default: return "Famous"
        }
    }

    /// How well the company is regarded (reputation 0...100).
    public static func reputation(_ value: Double) -> String {
        switch value {
        case ..<25: return "Poor"
        case ..<50: return "Fair"
        case ..<70: return "Good"
        case ..<85: return "Very good"
        default: return "Excellent"
        }
    }

    /// How the press and public see you on one of the three press-image axes (0...100): `trust`, `bold` or `care`. Words for the screens instead of the bare numbers.
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

    /// The three axes in words, in the order trust, bold, care.
    public static func pressImage(trust: Double, bold: Double, care: Double) -> [(axis: String, word: String)] {
        [("Trust", pressImage("trust", trust)), ("Boldness", pressImage("bold", bold)), ("Care", pressImage("care", care))]
    }

    /// Five star glyphs for a rating out of 5: filled for each whole star the rating reaches when rounded, empty for the rest.
    public static func starGlyphs(_ rating: Double) -> String {
        let filled: Int = min(5, max(0, Int(rating.rounded())))
        return String(repeating: "★", count: filled) + String(repeating: "☆", count: 5 - filled)
    }

    /// "★★★★☆ 4.2 / 5".
    public static func ratingText(_ rating: Double) -> String {
        starGlyphs(rating) + String(format: " %.1f / 5", rating)
    }
}

public extension MarketMap.Knowledge.Level {
    /// The market-share graph is only drawn when somebody measures the market: a data analyst in the head office or a market analyst in
    /// a company. With nobody measuring (`feeling`) the share is a guess and shows in words only.
    var canDrawShareGraph: Bool { self != .feeling }
}
