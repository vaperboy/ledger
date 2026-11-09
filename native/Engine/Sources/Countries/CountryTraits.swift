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

    /// Enforcement strictness and openness to influence (1 = average), data: `politics` in `country_traits.json`.
    public static func politics(_ code: String, _ key: String) -> Double {
        let v = file["politics"][code][key]
        return v.isNull ? 1 : v.double
    }

    /// Labour law of a country (minimum wage, hours, notice, severance ...), data: `labour` in `country_traits.json`; see `LabourRules`.
    public static func labour(_ code: String) -> JSONValue { file["labour"][code] }

    public static var globalBrandOrigins: [String] { file["globalBrandOrigins"].array.map { $0.string } }
    /// Hours from UTC (standard time); 0 when the country has none.
    public static func utcOffset(_ code: String) -> Int { entry(code)["utcOffset"].int }
    /// The capital's latitude and longitude, nil when the country has none.
    public static func capital(_ code: String) -> (lat: Double, lon: Double)? {
        let e = entry(code)
        return e["lat"].isNull || e["lon"].isNull ? nil : (e["lat"].double, e["lon"].double)
    }
    /// The customs union the country belongs to; a country outside any is a zone of its own.
    public static func customsZone(_ code: String) -> String { text(code, "customsZone") ?? code }
    /// The land region goods can be driven across, nil for a country on its own.
    public static func region(_ code: String) -> String? { text(code, "region") }

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
