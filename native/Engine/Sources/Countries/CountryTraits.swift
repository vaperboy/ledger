import Foundation
import GameCore

public enum CountryTraits {
    private static let file: JSONValue = {
        guard let url = Bundle.module.url(forResource: "country_traits", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    public static func entry(_ code: String) -> JSONValue { file["countries"][code] }
    public static func flag(_ code: String, _ key: String) -> Bool { entry(code)[key].bool }
    public static func text(_ code: String, _ key: String) -> String? { let v = entry(code)[key]; return v.isNull ? nil : v.string }

    public static func politics(_ code: String, _ key: String) -> Double {
        let v = file["politics"][code][key]
        return v.isNull ? 1 : v.double
    }

    public static func labour(_ code: String) -> JSONValue { file["labour"][code] }

    public static var globalBrandOrigins: [String] { file["globalBrandOrigins"].array.map { $0.string } }
    public static func utcOffset(_ code: String) -> Int { entry(code)["utcOffset"].int }
    public static func capital(_ code: String) -> (lat: Double, lon: Double)? {
        let e = entry(code)
        return e["lat"].isNull || e["lon"].isNull ? nil : (e["lat"].double, e["lon"].double)
    }
    public static func customsZone(_ code: String) -> String { text(code, "customsZone") ?? code }
    public static func region(_ code: String) -> String? { text(code, "region") }

    public static func isSouthernHemisphere(_ code: String) -> Bool { flag(code, "southernHemisphere") }
    public static func hasDataProtectionLaw(_ code: String) -> Bool { flag(code, "gdpr") }

    public static func cityPaperName(_ code: String, city: String) -> String? {
        text(code, "cityPaper").map { $0.replacingOccurrences(of: "{s}", with: city.hasSuffix("s") ? "" : "s").replacingOccurrences(of: "{city}", with: city) }
    }
}

extension Country {
    public var traits: JSONValue { CountryTraits.entry(code) }
}
