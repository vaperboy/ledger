import Foundation
import GameCore
import Countries
import Employees

/// Everything the company model reads: the game state plus the static game data. Passed to the demand,
/// capacity and cost calculations so none of them needs a global.
public struct World {
    public var state: GameState
    public let countries: CountryBook
    public let catalog: TradeCatalog
    public let balance: Balance

    public init(state: GameState, data: GameData) {
        self.init(state: state, countries: data.countries, catalog: data.catalog, balance: data.balance)
    }

    public init(state: GameState, countries: CountryBook, catalog: TradeCatalog, balance: Balance) {
        self.state = state
        self.countries = countries
        self.catalog = catalog
        self.balance = balance
    }

    public var week: Int { state.week }
    public var economy: Economy { state.economy }
    public var rates: ExchangeRates { ExchangeRates(drift: state.exchangeRates.values) }

    public func country(_ co: Company) -> Country {
        countries[co.countryCode] ?? countries[state.homeCountryCode] ?? countries[CountryBook.baseCountryCode]!
    }
    public func currency(_ co: Company) -> Currency { Currency(country: country(co), rates: rates) }
    public func city(_ co: Company) -> Country.City? {
        countries.city(co.cityID, preferring: co.countryCode)?.city
    }
    public func trade(_ co: Company) -> Trade? { catalog[co.type] }

    /// Prices grow with inflation over the years. Original: `Math.pow(1 + S.econ.infl, S.week / 52)`.
    public var inflationIndex: Double { pow(1 + economy.inflation, Double(state.week) / 52) }

    /// The competitor market a company sells in. Original: `S.mk[mkKey(co)]`.
    public func market(for co: Company) -> JSONValue? {
        let m = state.rest["mk"]?[co.type + "|" + co.cityID]
        return (m == nil || m!.isNull) ? nil : m
    }

    public func person(_ id: Int) -> Person? { state.people[id] }
}

/// Smooth, repeatable "noise" that depends on the game seed, so the same game always gets the same wiggles.
enum SeededNoise {
    /// Original: `wave(key, wk)`.
    static func wave(seed: Int, key: String, week: Int) -> Double {
        sin(2 * Double.pi * (Double(week) + HashedRandom.first("\(seed):ph:\(key)") * 52) / 52)
    }
    /// Smooth value between 0 and 1 that changes every `span` weeks. Original: `nz(key, wk, span)`.
    static func smooth(seed: Int, key: String, week: Int, span: Double) -> Double {
        let b = (Double(week) / span).rounded(.down)
        let f = Double(week) / span - b
        let a = HashedRandom.first("\(seed):\(key):\(Int(b))")
        let c = HashedRandom.first("\(seed):\(key):\(Int(b) + 1)")
        return a + (c - a) * (f * f * (3 - 2 * f))
    }
}
