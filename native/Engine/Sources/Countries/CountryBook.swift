import Foundation
import GameCore

/// All countries of the game, in menu order. Loaded from `Resources/countries.json`.
public struct CountryBook: Sendable {
    public let countries: [Country]
    private let byCode: [String: Country]

    /// The country whose currency is the accounting unit; its exchange rate never moves. Original: `BASE_COUNTRY`.
    public static let baseCountryCode = "NO"

    public init(countries: [Country]) {
        self.countries = countries
        self.byCode = Dictionary(uniqueKeysWithValues: countries.map { ($0.code, $0) })
    }

    public subscript(code: String) -> Country? { byCode[code] }

    /// Which country hosts a city id. Original: `cityOf` (searches the current country first).
    public func city(_ id: String, preferring code: String? = nil) -> (country: Country, city: Country.City)? {
        if let c = code.flatMap({ byCode[$0] }), let city = c.city(id) { return (c, city) }
        for c in countries { if let city = c.city(id) { return (c, city) } }
        return nil
    }

    /// Load the bundled data file.
    public static func bundled() throws -> CountryBook {
        guard let url = Bundle.module.url(forResource: "countries", withExtension: "json", subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try CountryBook(jsonData: Data(contentsOf: url))
    }

    public init(jsonData: Data) throws {
        let list = try JSONDecoder().decode([JSONValue].self, from: jsonData)
        self.init(countries: list.map { Country(pack: $0) })
    }
}
