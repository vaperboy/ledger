import Foundation
import Countries

/// The game's static data: countries, trades and balance numbers. Loaded once from the bundled JSON files.
public struct GameData: Sendable {
    public let countries: CountryBook
    public let catalog: TradeCatalog
    public let balance: Balance

    public init(countries: CountryBook, catalog: TradeCatalog, balance: Balance) {
        self.countries = countries
        self.catalog = catalog
        self.balance = balance
    }

    public static func bundled() throws -> GameData {
        GameData(countries: try CountryBook.bundled(), catalog: try TradeCatalog.bundled(), balance: try Balance.bundled())
    }
}
