import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct TradeAffordability: Identifiable, Equatable, Sendable {
    public var id: String { tradeID }
    public var tradeID: String
    public var cost: Double?
    public var minimum: Double? = nil
    public var size: Double = 1
    public var recommendedSize: Double = 1
    public var isScaledDown: Bool { size < recommendedSize - 0.001 }
    public var available: Double
    public var blocked: String?
    public var shortfall: Double { max(0, (minimum ?? cost ?? 0) - available) }
    public var isFunded: Bool { blocked == nil && cost != nil && shortfall == 0 }

    public static func rows(state s: GameState, data: GameData, cityID: String, countryCode: String? = nil) -> [TradeAffordability] {
        let country = data.countries.resolve(countryCode ?? s.homeCountryCode, orHome: s.homeCountryCode)
        let city = country.city(cityID) ?? country.cities[0]
        let available = Payments.liquid(s)
        var probe = s; probe.cash += Double(Int32.max)
        let rows: [TradeAffordability] = data.catalog.all.filter { !SpecialFamilies.isRetired($0) }.map { t in
            let blocked = CompanySetup.banReason(t.id, country: country) ?? (SpecialFamilies.isStartable(t) ? nil : "Coming in a later update")
            guard blocked == nil else { return TradeAffordability(tradeID: t.id, cost: nil, available: available, blocked: blocked) }
            let rec = CompanySetup.recommendedSize(t, city: city)
            func price(_ size: Double) -> CompanySetup.Estimate? {
                CompanySetup.estimate(tradeID: t.id, cityID: city.id, size: size, countryCode: country.code, state: probe, data: data)
            }
            var size = rec
            var est = price(rec)
            if let full = est, full.minimumToOpen > available, t.minSize < rec - 0.001 {
                if let small = price(t.minSize) {
                    if small.minimumToOpen > available {
                        size = t.minSize; est = small
                    } else {
                        var lo = Int(saturating: (t.minSize * 20).rounded()), hi = Int(saturating: (rec * 20).rounded())
                        var best = small, bestSize = t.minSize
                        while hi - lo > 1 {
                            let mid = (lo + hi) / 2
                            if let m = price(Double(mid) / 20), m.minimumToOpen <= available { lo = mid; best = m; bestSize = Double(mid) / 20 } else { hi = mid }
                        }
                        size = bestSize; est = best
                    }
                }
            }
            var row = TradeAffordability(tradeID: t.id, cost: est?.total, minimum: est?.minimumToOpen, available: available, blocked: est == nil ? "Cannot be priced here" : nil)
            row.size = size; row.recommendedSize = rec
            return row
        }
        func rank(_ r: TradeAffordability) -> Int { r.blocked != nil ? 2 : (r.isFunded ? 0 : 1) }
        let order = Dictionary(data.catalog.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { (a, _) in a })
        return rows.sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            if $0.cost != $1.cost { return ($0.cost ?? 0) < ($1.cost ?? 0) }
            return (order[$0.tradeID] ?? 0) < (order[$1.tradeID] ?? 0)
        }
    }
}

public extension GameEngine {
    func tradeAffordability(cityID: String? = nil) -> [TradeAffordability] {
        readMemo.value(stateStamp, "tradeAffordability|\(cityID ?? "-")") { tradeAffordabilityFresh(cityID: cityID) }
    }
    func tradeAffordabilityFresh(cityID: String? = nil) -> [TradeAffordability] {
        TradeAffordability.rows(state: state, data: data, cityID: cityID ?? state.player.cityID)
    }
}
