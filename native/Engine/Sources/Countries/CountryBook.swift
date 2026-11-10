import Foundation
import GameCore

public struct CountryBook: Sendable {
    public let countries: [Country]
    private let byCode: [String: Country]

    public init(countries: [Country]) {
        self.countries = countries
        self.byCode = Dictionary(countries.map { ($0.code, $0) }, uniquingKeysWith: { (a, _) in a })
    }

    public subscript(code: String) -> Country? { byCode[code] }

    public func resolve(_ code: String, orHome home: String) -> Country { byCode[code] ?? byCode[home] ?? countries[0] }

    public func city(_ id: String, preferring code: String? = nil) -> (country: Country, city: Country.City)? {
        if let c = code.flatMap({ byCode[$0] }), let city = c.city(id) { return (c, city) }
        for c in countries { if let city = c.city(id) { return (c, city) } }
        return nil
    }

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
