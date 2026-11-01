import Foundation
import GameCore

/// All countries of the game, in menu order. Loaded from `Resources/countries.json`.
public struct CountryBook: Sendable {
    public let countries: [Country]
    private let byCode: [String: Country]

    public init(countries: [Country]) {
        self.countries = countries
        self.byCode = Dictionary(uniqueKeysWithValues: countries.map { ($0.code, $0) })
    }

    public subscript(code: String) -> Country? { byCode[code] }

    /// A country by code; if the code is unknown the player's home country, never a hidden default country.
    public func resolve(_ code: String, orHome home: String) -> Country { byCode[code] ?? byCode[home] ?? countries[0] }

    /// Which country hosts a city id. Original: `cityOf` (searches the current country first).
    public func city(_ id: String, preferring code: String? = nil) -> (country: Country, city: Country.City)? {
        if let c = code.flatMap({ byCode[$0] }), let city = c.city(id) { return (c, city) }
        for c in countries { if let city = c.city(id) { return (c, city) } }
        return nil
    }

    /// Load the bundled data file.
    /// `realCityMarket: false` leaves out `Resources/city_market.json` (the real-life city sizes, incomes and tourism, docs/CITY_DATA.md): the
    /// original game's city data, which the differential tests against the original game use.
    public static func bundled(realCityMarket: Bool = true) throws -> CountryBook {
        guard let url = Bundle.module.url(forResource: "countries", withExtension: "json", subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try CountryBook(jsonData: Data(contentsOf: url), overlay: realCityMarket ? CityMarketData.bundled() : .null)
    }

    public init(jsonData: Data, overlay: JSONValue = .null) throws {
        let list = try JSONDecoder().decode([JSONValue].self, from: jsonData)
        self.init(countries: list.map { Country(pack: overlay.isNull ? $0 : CityMarketData.merge($0, overlay: overlay)) })
    }
}
