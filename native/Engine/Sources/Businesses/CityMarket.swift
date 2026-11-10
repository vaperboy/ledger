import Foundation
import GameCore
import Countries

public struct CityMarketTables: Sendable {
    public struct TradeClass: Sendable, Equatable {
        public var need: Double
        public var lean: Double
    }
    public var base = 0.85
    public var positionExponent = 2.4
    public var demandFloor = 0.08, demandCeiling = 3.0
    public var rivalDensityFloor = 0.15, rivalDensityCeiling = 3.0
    public var rivalCapBoost = 0.12
    public var rivalStrengthBoost = 0.2
    public var awarenessCeilingDrop = 14.0
    public var trades: [String: TradeClass] = [:]

    public init(json j: JSONValue) {
        func num(_ k: String, _ d: Double) -> Double { j[k].isNull ? d : j[k].double }
        base = num("base", base); positionExponent = num("positionExponent", positionExponent)
        demandFloor = num("demandFloor", demandFloor); demandCeiling = num("demandCeiling", demandCeiling)
        rivalDensityFloor = num("rivalDensityFloor", rivalDensityFloor); rivalDensityCeiling = num("rivalDensityCeiling", rivalDensityCeiling)
        rivalCapBoost = num("rivalCapBoost", rivalCapBoost); rivalStrengthBoost = num("rivalStrengthBoost", rivalStrengthBoost)
        awarenessCeilingDrop = num("awarenessCeilingDrop", awarenessCeilingDrop)
        trades = j["trades"].object.mapValues { TradeClass(need: $0["need"].double, lean: $0["lean"].double) }
    }

    public static var bundledTradeIDs: Set<String> {
        guard let url = Bundle.module.url(forResource: "market_classes", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return Set(json["trades"].object.keys)
    }
}

public enum CityMarket {
    static func sizeTerm(_ pop: Double) -> Double { clamp(log10(max(1, pop) / 300) / 1.5, 0, 1) }

    public static func affordRatio(trade id: String, priceMultiplier pm: Double, country: Country, city: Country.City, tables: CityMarketTables) -> Double {
        guard let t = tables.trades[id] else { return 1 }
        let threshold = tables.base * t.need * pow(max(0.3, pm), tables.positionExponent)
        let here = country.shareAbove(threshold, in: city), nation = country.nationalShareAbove(threshold)
        return (here + 1e-6) / (nation + 1e-6)
    }

    public static func demandFactor(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let tables = w.balance.cityMarket
        guard let t = tables.trades[bd.id], let city = w.city(co) else { return 1 }
        let pm = w.balance.priceMultiplier(level: co.priceLevel)
        let ratio = affordRatio(trade: bd.id, priceMultiplier: pm, country: w.country(co), city: city, tables: tables)
        return clamp(pow(ratio, t.lean), tables.demandFloor, tables.demandCeiling)
    }

    public static func rivalDensity(trade id: String, country: Country, city: Country.City, tables: CityMarketTables) -> Double {
        guard let t = tables.trades[id] else { return 1 }
        let ratio = affordRatio(trade: id, priceMultiplier: 1, country: country, city: city, tables: tables)
        return clamp(pow(ratio, t.lean), tables.rivalDensityFloor, tables.rivalDensityCeiling)
    }

    public static func rivalStrengthBoost(trade id: String, city: Country.City?, tables: CityMarketTables) -> Double {
        guard let t = tables.trades[id], let city else { return 0 }
        return tables.rivalStrengthBoost * min(1, t.lean) * sizeTerm(city.population)
    }

    public static func rivalCapBoost(_ co: Company, _ w: World) -> Double {
        let tables = w.balance.cityMarket
        guard let t = tables.trades[co.type], let city = w.city(co) else { return 0 }
        return tables.rivalCapBoost * min(1, t.lean) * sizeTerm(city.population)
    }

    public static func awarenessCeiling(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard RivalGroups.localFamilies.contains(bd.family), bd.normalDemand > 0, let city = w.city(co) else { return 100 }
        return 100 - w.balance.cityMarket.awarenessCeilingDrop * sizeTerm(city.population)
    }

    public static func visitorShare(country: Country, city: Country.City?) -> Double {
        let t = country.pack["tourism"]["share"]
        return clamp((t.isNull ? 0.1 : t.double) * (city?.touristIndex ?? 1), 0, 0.9)
    }

    public enum DemandLevel: String, Sendable, CaseIterable {
        case high = "High", medium = "Medium", low = "Low"
    }
    public static let demandHighFrom = 1.25, demandLowBelow = 0.85

    public static func demandIndex(trade id: String, country: Country, city: Country.City, tables: CityMarketTables) -> Double {
        let lean = tables.trades[id]?.lean ?? 0
        let f = clamp(pow(affordRatio(trade: id, priceMultiplier: 1, country: country, city: city, tables: tables), lean), tables.demandFloor, tables.demandCeiling)
        return city.demand * f
    }

    public static func demandLevel(trade id: String, country: Country, city: Country.City, tables: CityMarketTables) -> DemandLevel {
        let i = demandIndex(trade: id, country: country, city: city, tables: tables)
        return i >= demandHighFrom ? .high : i < demandLowBelow ? .low : .medium
    }

    public enum Tier: String, Sendable, CaseIterable { case everyday, premium, luxury }

    public struct TradeDemand: Equatable, Sendable {
        public var tradeID: String
        public var name: String
        public var tier: Tier
        public var affordableShare: Double
        public var demandFactor: Double
        public var rivals: Int
    }

    public struct TierSummary: Equatable, Sendable {
        public var tier: Tier
        public var label: String
        public var potentialHouseholds: Double
        public var potentialShare: Double
        public var demandFactor: Double
        public var rivals: Double
        public var tradeIDs: [String]
    }

    public struct Profile: Equatable, Sendable {
        public var cityID: String
        public var cityName: String
        public var countryCode: String
        public var population: Double
        public var metroPopulation: Double
        public var households: Double
        public var medianMonthlyIncome: Double
        public var gini: Double
        public var bands: IncomeBands
        public var touristIndex: Double
        public var visitorShare: Double
        public var rentLevel: Double, wageLevel: Double, priceLevel: Double, demandLevel: Double
        public var tiers: [TierSummary]
        public var trades: [TradeDemand]
    }

    public static let householdSize = 2.3

    public static func expectedRivals(trade bd: Trade, country: Country, city: Country.City, tables: CityMarketTables) -> Double {
        max(1, jsRound(1 + city.population / 120 * rivalDensity(trade: bd.id, country: country, city: city, tables: tables) + 1))
    }

    public static func profile(cityID: String, countryCode: String? = nil, state: GameState? = nil, data: GameData) -> Profile? {
        guard let hit = data.countries.city(cityID, preferring: countryCode) else { return nil }
        let country = hit.country, city = hit.city, tables = data.balance.cityMarket
        let bands = country.incomeBands(in: city)
        var trades: [TradeDemand] = []
        for bd in data.catalog.all where RivalGroups.localFamilies.contains(bd.family) && bd.normalDemand > 0 {
            let cls = tables.trades[bd.id]
            let tier: Tier = cls == nil ? .everyday : (cls!.lean >= 0.7 ? .luxury : .premium)
            let share: Double
            if let c = cls { share = country.shareAbove(tables.base * c.need, in: city) } else { share = 1 }
            let key = bd.id + "|" + city.id
            let mk = state?.rest["mk"]?[key]
            let rivals = (mk == nil || mk!.isNull) ? expectedRivals(trade: bd, country: country, city: city, tables: tables) : mk!["n"].double
            trades.append(TradeDemand(tradeID: bd.id, name: bd.name, tier: tier, affordableShare: share,
                                      demandFactor: clamp(pow(affordRatio(trade: bd.id, priceMultiplier: 1, country: country, city: city, tables: tables), cls?.lean ?? 0),
                                                          tables.demandFloor, tables.demandCeiling),
                                      rivals: Int(saturating: jsRound(rivals))))
        }
        let households = city.population * 1000 / householdSize
        func summary(_ t: Tier, _ label: String, share: Double) -> TierSummary {
            let list = trades.filter { $0.tier == t }
            let n = Double(max(1, list.count))
            return TierSummary(tier: t, label: label, potentialHouseholds: households * share, potentialShare: share,
                               demandFactor: list.reduce(0) { $0 + $1.demandFactor } / n, rivals: Double(list.reduce(0) { $0 + $1.rivals }) / n,
                               tradeIDs: list.map { $0.tradeID })
        }
        return Profile(cityID: city.id, cityName: city.name, countryCode: country.code, population: city.population,
                       metroPopulation: city.metro, households: households,
                       medianMonthlyIncome: country.medianMonthlyWage * city.affluence, gini: city.inequality, bands: bands,
                       touristIndex: city.touristIndex, visitorShare: visitorShare(country: country, city: city),
                       rentLevel: city.rent, wageLevel: city.wage, priceLevel: city.price, demandLevel: city.demand,
                       tiers: [summary(.everyday, "Everyday", share: 1), summary(.premium, "Premium", share: bands.canAffordPremium),
                               summary(.luxury, "Luxury", share: bands.affluent)],
                       trades: trades.sorted { $0.name < $1.name })
    }
}
