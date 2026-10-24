import Foundation
import GameCore
import Countries

/// Which trades sell to the better-off and how strongly (`Resources/market_classes.json`).
public struct CityMarketTables: Sendable {
    public struct TradeClass: Sendable, Equatable {
        /// Income (multiples of the reference median wage, at an average price position) a household needs to buy this regularly.
        public var need: Double
        /// Exponent of (share of households that can afford it in the city / in the country).
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

    /// Trades with a class: their demand differs on purpose from the original game's, so the parity tests skip them (docs/CITY_DATA.md).
    public static var bundledTradeIDs: Set<String> {
        guard let url = Bundle.module.url(forResource: "market_classes", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return Set(json["trades"].object.keys)
    }
}

/// The market of a place: who lives there, what they can afford, who else sells to them. Integrates with the existing models rather than
/// replacing them: `Country.City` carries the numbers (population, rent, wage, price, demand level and now the income level and spread
/// and the tourist draw), `DemandModel` multiplies in `demandFactor` for the trades that sell to the better-off, the rival markets
/// (`WorldWeek.competitors`, `Competition.rivalFactor`) take their size and strength from `rivalDensity`, `rivalCapBoost` and
/// `rivalStrengthBoost`, and `Marketing` limits how much of a big city one local name can reach (`awarenessCeiling`).
public enum CityMarket {
    /// 0 for a village, 1 for a city of about 6 million: how far a place is a big, crowded market.
    static func sizeTerm(_ pop: Double) -> Double { clamp(log10(max(1, pop) / 300) / 1.5, 0, 1) }

    /// Share of households that can afford a trade at a price position, in this city against the country as a whole. 1 where the trade is
    /// an everyday one.
    public static func affordRatio(trade id: String, priceMultiplier pm: Double, country: Country, city: Country.City, tables: CityMarketTables) -> Double {
        guard let t = tables.trades[id] else { return 1 }
        let threshold = tables.base * t.need * pow(max(0.3, pm), tables.positionExponent)
        let here = country.shareAbove(threshold, in: city), nation = country.nationalShareAbove(threshold)
        return (here + 1e-6) / (nation + 1e-6)
    }

    /// The weekly demand step: potential customers follow the share of local households that can afford what the company sells.
    /// Everyday trades: 1. Original game: no such step (new, docs/CITY_DATA.md).
    public static func demandFactor(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let tables = w.balance.cityMarket
        guard let t = tables.trades[bd.id], let city = w.city(co) else { return 1 }
        let pm = w.balance.priceMultiplier(level: co.priceLevel)
        let ratio = affordRatio(trade: bd.id, priceMultiplier: pm, country: w.country(co), city: city, tables: tables)
        return clamp(pow(ratio, t.lean), tables.demandFloor, tables.demandCeiling)
    }

    /// How many more (or fewer) rivals of this kind a place has than its size alone gives: rivals follow the customers who can pay.
    public static func rivalDensity(trade id: String, country: Country, city: Country.City, tables: CityMarketTables) -> Double {
        guard let t = tables.trades[id] else { return 1 }
        let ratio = affordRatio(trade: id, priceMultiplier: 1, country: country, city: city, tables: tables)
        return clamp(pow(ratio, t.lean), tables.rivalDensityFloor, tables.rivalDensityCeiling)
    }

    /// Rivals in a big city are stronger (bigger names, more marketing): added to the market's strength when it is created.
    public static func rivalStrengthBoost(trade id: String, city: Country.City?, tables: CityMarketTables) -> Double {
        guard let t = tables.trades[id], let city else { return 0 }
        return tables.rivalStrengthBoost * min(1, t.lean) * sizeTerm(city.population)
    }

    /// The most customers rivals can take from you grows with the size of the city for trades that sell to the better-off.
    public static func rivalCapBoost(_ co: Company, _ w: World) -> Double {
        let tables = w.balance.cityMarket
        guard let t = tables.trades[co.type], let city = w.city(co) else { return 0 }
        return tables.rivalCapBoost * min(1, t.lean) * sizeTerm(city.population)
    }

    /// The share of a city's people one local business can ever be known to. A shop in a village can be known to nearly everyone; in a
    /// metropolis, never to everyone. Businesses that sell nationally are not limited.
    public static func awarenessCeiling(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard RivalGroups.localFamilies.contains(bd.family), bd.normalDemand > 0, let city = w.city(co) else { return 100 }
        return 100 - w.balance.cityMarket.awarenessCeilingDrop * sizeTerm(city.population)
    }

    /// Visitors' share of customers is the country's, times the city's draw.
    public static func visitorShare(country: Country, city: Country.City?) -> Double {
        let t = country.pack["tourism"]["share"]
        return clamp((t.isNull ? 0.1 : t.double) * (city?.touristIndex ?? 1), 0, 0.9)
    }

    // MARK: Read model for screens

    public enum Tier: String, Sendable, CaseIterable { case everyday, premium, luxury }

    public struct TradeDemand: Equatable, Sendable {
        public var tradeID: String
        public var name: String
        public var tier: Tier
        /// Share of the city's households that can afford this trade at an average price position.
        public var affordableShare: Double
        /// Demand multiplier of an average-priced company here against the country as a whole (1 for everyday trades).
        public var demandFactor: Double
        /// Rivals selling the same thing in the city: the market's own count where the game has made it, else the expected count.
        public var rivals: Int
    }

    public struct TierSummary: Equatable, Sendable {
        public var tier: Tier
        public var label: String
        /// Households in the city that can afford this class of trade.
        public var potentialHouseholds: Double
        public var potentialShare: Double
        /// Average demand multiplier and rival count over the trades of the class.
        public var demandFactor: Double
        public var rivals: Double
        public var tradeIDs: [String]
    }

    public struct Profile: Equatable, Sendable {
        public var cityID: String
        public var cityName: String
        public var countryCode: String
        /// Thousands
        public var population: Double
        public var metroPopulation: Double
        public var households: Double
        /// Median household income per month, accounting units.
        public var medianMonthlyIncome: Double
        public var gini: Double
        public var bands: IncomeBands
        public var touristIndex: Double
        /// Visitors' share of customers in a trade that lives on visitors (hotels 1, cafes 0.7 ... of it).
        public var visitorShare: Double
        public var rentLevel: Double, wageLevel: Double, priceLevel: Double, demandLevel: Double
        public var tiers: [TierSummary]
        public var trades: [TradeDemand]
    }

    /// People per household used for the household count.
    public static let householdSize = 2.3

    /// Expected rivals in a city for a trade, as `WorldWeek.competitors` creates them (without the random part, which averages one).
    public static func expectedRivals(trade bd: Trade, country: Country, city: Country.City, tables: CityMarketTables) -> Double {
        max(1, jsRound(1 + city.population / 120 * rivalDensity(trade: bd.id, country: country, city: city, tables: tables) + 1))
    }

    /// The market of one city for a screen. Rival counts come from the running game's markets where they exist (`state`), else the expectation.
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
                                      rivals: Int(jsRound(rivals))))
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
