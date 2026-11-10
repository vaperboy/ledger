import Foundation
import GameCore
import Countries

public enum LocationNames {
    static let config: JSONValue = {
        guard let url = Bundle.module.url(forResource: "location_names", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    static func strings(_ v: JSONValue) -> [String] { v.array.map { $0.string }.filter { !$0.isEmpty } }

    public static func places(countryCode: String, cityID: String) -> [String] {
        strings(config["cities"]["\(countryCode):\(cityID)"]) + strings(config["countries"][countryCode])
    }

    public static func fallbacks() -> [String] {
        let areas = strings(config["areas"]), compass = strings(config["compass"])
        let base = areas.isEmpty ? ["Old Town", "Riverside", "Station", "Harbour"] : areas
        let points = compass.isEmpty ? ["North", "South", "East", "West"] : compass
        return points + points.flatMap { p in base.map { "\(p) \($0)" } } + base
    }

    static let lastResort = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa", "Lambda", "Sigma", "Omega"]

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
