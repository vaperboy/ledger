import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// What the player can fund today, trade by trade, for the New company list. Nothing is blocked: this only measures the
/// start-up cost (`CompanySetup.estimate`) against the money available (current account plus savings) and reports the shortfall.
public struct TradeAffordability: Identifiable, Equatable, Sendable {
    public var id: String { tradeID }
    public var tradeID: String
    /// The engine's full start-up cost; nil when the trade cannot be priced here (banned or not yet startable).
    public var cost: Double?
    public var available: Double
    /// Why the trade cannot be started at all (ban or not yet built); nil if it can.
    public var blocked: String?
    public var shortfall: Double { max(0, (cost ?? 0) - available) }
    public var isFunded: Bool { blocked == nil && cost != nil && shortfall == 0 }

    /// Every trade, priced for the home country in `cityID` at the recommended size (a limited company only where the trade needs one).
    /// Funded trades first, cheapest first; then the ones that need more money, cheapest first; then the ones that cannot be started.
    public static func rows(state s: GameState, data: GameData, cityID: String, countryCode: String? = nil) -> [TradeAffordability] {
        let country = data.countries.resolve(countryCode ?? s.homeCountryCode, orHome: s.homeCountryCode)
        let city = country.city(cityID) ?? country.cities[0]
        let available = Payments.liquid(s)
        // A limited company needs its share capital in the account before it can even be priced; price it on a copy that has it.
        var probe = s; probe.cash += Double(Int32.max)
        let rows: [TradeAffordability] = data.catalog.all.map { t in
            let blocked = CompanySetup.banReason(t.id, country: country) ?? (SpecialFamilies.isStartable(t) ? nil : "Coming in a later update")
            guard blocked == nil else { return TradeAffordability(tradeID: t.id, cost: nil, available: available, blocked: blocked) }
            let form: LegalForm = t.needsLimitedCompany ? .limited : .soleTrader
            let est = CompanySetup.estimate(tradeID: t.id, cityID: city.id, form: form, size: CompanySetup.recommendedSize(t, city: city), countryCode: country.code, state: probe, data: data)
            return TradeAffordability(tradeID: t.id, cost: est?.total, available: available, blocked: est == nil ? "Cannot be priced here" : nil)
        }
        func rank(_ r: TradeAffordability) -> Int { r.blocked != nil ? 2 : (r.isFunded ? 0 : 1) }
        let order = Dictionary(uniqueKeysWithValues: data.catalog.all.enumerated().map { ($1.id, $0) })
        return rows.sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            if $0.cost != $1.cost { return ($0.cost ?? 0) < ($1.cost ?? 0) }
            return (order[$0.tradeID] ?? 0) < (order[$1.tradeID] ?? 0)
        }
    }
}

public extension GameEngine {
    func tradeAffordability(cityID: String? = nil) -> [TradeAffordability] {
        TradeAffordability.rows(state: state, data: data, cityID: cityID ?? state.player.cityID)
    }
}
