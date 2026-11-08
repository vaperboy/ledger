import Foundation
import GameCore
import Countries

/// Names that tell the locations of one brand apart: the first location in a city carries the city's name, the others a district, a well-known
/// area or street of that city or country (`Resources/location_names.json`), and when those run out a compass or area word. Never a number.
public enum LocationNames {
    static let config: JSONValue = {
        guard let url = Bundle.module.url(forResource: "location_names", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    static func strings(_ v: JSONValue) -> [String] { v.array.map { $0.string }.filter { !$0.isEmpty } }

    /// Place names for a city, best first: the city's own districts, then the country's well-known areas.
    public static func places(countryCode: String, cityID: String) -> [String] {
        strings(config["cities"]["\(countryCode):\(cityID)"]) + strings(config["countries"][countryCode])
    }

    /// Words for any place when a city has no list or its list is used up: compass points, then compass with area words.
    public static func fallbacks() -> [String] {
        let areas = strings(config["areas"]), compass = strings(config["compass"])
        let base = areas.isEmpty ? ["Old Town", "Riverside", "Station", "Harbour"] : areas
        let points = compass.isEmpty ? ["North", "South", "East", "West"] : compass
        return points + points.flatMap { p in base.map { "\(p) \($0)" } } + base
    }

    /// Greek letters: the last resort when every combination of place words is taken.
    static let lastResort = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa", "Lambda", "Sigma", "Omega"]

    /// "Brand Place" for a location of `brand` in the city: the city name for the first one there, then districts. Skips any name a company
    /// other than `excluding` already has.
    public static func locationName(_ s: GameState, brand: String, countryCode: String, cityID: String, cityName: String, excluding: Int? = nil, data: GameData) -> String {
        let taken = Set(s.companies.filter { $0.id != excluding }.map { $0.name.lowercased() })
        func free(_ place: String) -> String? {
            let n = place.isEmpty ? brand : "\(brand) \(place)"
            return taken.contains(n.lowercased()) ? nil : n
        }
        if let n = free(cityName) { return n }
        let cityPlaces = places(countryCode: countryCode, cityID: cityID)
        for p in cityPlaces { if let n = free(p) { return n } }
        for p in fallbacks() { if let n = free(p) { return n } }
        for p in fallbacks() { for l in lastResort { if let n = free("\(p) \(l)") { return n } } }
        return "\(brand) \(cityName) \(lastResort[s.companies.count % lastResort.count])"
    }
}
