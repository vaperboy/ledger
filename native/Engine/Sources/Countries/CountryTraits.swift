import Foundation
import GameCore

/// Small per-country facts that game rules look up (data protection law, which hemisphere, local words, a title) kept as data in
/// `Resources/country_traits.json`, so no country code is written into the code. A country without an entry has none of them.
///
/// ```
/// { "globalBrandOrigins": ["US", "US", "UK"],          // home countries the worldwide franchise brands are drawn from (repeats weight)
///   "countries": { "AU": { "southernHemisphere": true, "stormName": "a severe storm", "gdpr": true, "mdirTitle": "President",
///                          "paper": "The Weekly Bottom Line", "cityPaper": "The {city} Chronicle", "groupWord": "Gruppe" } } }
/// ```
/// `cityPaper` uses `{city}` and `{s}` (an "s" unless the city name already ends in one).
public enum CountryTraits {
    private static let file: JSONValue = {
        guard let url = Bundle.module.url(forResource: "country_traits", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    public static func entry(_ code: String) -> JSONValue { file["countries"][code] }
    public static func flag(_ code: String, _ key: String) -> Bool { entry(code)[key].bool }
    public static func text(_ code: String, _ key: String) -> String? { let v = entry(code)[key]; return v.isNull ? nil : v.string }

    public static var globalBrandOrigins: [String] { file["globalBrandOrigins"].array.map { $0.string } }
    public static func isSouthernHemisphere(_ code: String) -> Bool { flag(code, "southernHemisphere") }
    public static func hasDataProtectionLaw(_ code: String) -> Bool { flag(code, "gdpr") }

    /// The local business paper's name for a city, if the country has a pattern for it.
    public static func cityPaperName(_ code: String, city: String) -> String? {
        text(code, "cityPaper").map { $0.replacingOccurrences(of: "{s}", with: city.hasSuffix("s") ? "" : "s").replacingOccurrences(of: "{city}", with: city) }
    }
}

extension Country {
    /// This country's entry in `country_traits.json`.
    public var traits: JSONValue { CountryTraits.entry(code) }
}
