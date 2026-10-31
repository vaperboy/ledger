import Foundation
import GameCore
import Countries
import Employees

/// Static knowledge the money code needs: the countries, the trade catalogue and lending hooks.
/// Built once when the game starts and passed to every Finance function.
public struct FinanceContext: Sendable {
    public var countries: CountryBook
    public var trades: any TradeCatalogProviding
    public var lending: LendingModifiers

    public init(countries: CountryBook, trades: any TradeCatalogProviding, lending: LendingModifiers = .init()) {
        self.countries = countries
        self.trades = trades
        self.lending = lending
    }

    public func country(_ code: String, fallback: String) -> Country { countries.resolve(code, orHome: fallback) }
    public func homeCountry(_ s: GameState) -> Country { country(s.homeCountryCode, fallback: s.homeCountryCode) }
    public func country(of co: Company, _ s: GameState) -> Country { country(co.countryCode, fallback: s.homeCountryCode) }
    public func rates(_ s: GameState) -> ExchangeRates { ExchangeRates(drift: s.exchangeRates.values) }
    public func currency(_ code: String, _ s: GameState) -> Currency { Currency(country: country(code, fallback: s.homeCountryCode), rates: rates(s)) }
    public func homeCurrency(_ s: GameState) -> Currency { Currency(country: homeCountry(s), rates: rates(s)) }

    /// What the company spends in a typical week; sets its overdraft room. Original: `coWeekCost`.
    public func weeklyCost(_ co: Company, _ s: GameState) -> Double {
        let fixed = trades.facts(for: co.type)?.fixedWeekly ?? 0
        return CompanyFigures.weeklyCostEstimate(co, fixedCost: fixed, country: country(of: co, s))
    }

    /// How far below zero the company's account may go. Original: `coOverdraft`.
    public func overdraftRoom(_ co: Company, _ s: GameState) -> Double {
        CompanyFigures.overdraftRoom(weeklyCost: weeklyCost(co, s))
    }
}
