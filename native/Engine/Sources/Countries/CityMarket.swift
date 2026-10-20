import Foundation
import GameCore

/// Households of a city by income band (shares of all households, summing to 1).
public struct IncomeBands: Equatable, Sendable {
    /// Below 0.7 x the reference median wage: price-driven, buy the cheapest version of everything.
    public var budget: Double
    /// 0.7 to 1.5 x: the broad middle.
    public var middle: Double
    /// 1.5 to 4 x: can afford premium positioning.
    public var upper: Double
    /// Above 4 x: can afford luxury positioning.
    public var affluent: Double
    public var canAffordPremium: Double { upper + affluent }
}

/// How household incomes are spread in a place: a log-normal around the place's median, with the spread taken from the Gini
/// coefficient (for a log-normal, Gini = erf(sigma / 2)). Incomes are written in units of the reference economy's median wage, so
/// places in different countries compare directly. A band's threshold is scaled by the local price level (money buys less where
/// everything costs more), by `sqrt(price)`.
public enum IncomeModel {
    public static let budgetBelow = 0.7
    public static let premiumFrom = 1.5
    public static let luxuryFrom = 4.0

    /// Spread (sigma of the log income) for a Gini coefficient.
    public static func sigma(gini: Double) -> Double {
        let g = clamp(gini, 0.05, 0.9)
        var x = g * 1.2
        for _ in 0..<40 {   // Newton on erf(x) = g
            let f = erf(x) - g, d = 2 / Double.pi.squareRoot() * exp(-x * x)
            if d < 1e-12 { break }
            x -= f / d
        }
        return 2 * x
    }

    /// Share of households with an income above `threshold` (reference-median multiples), given the median and Gini.
    public static func shareAbove(_ threshold: Double, median: Double, gini: Double) -> Double {
        guard threshold > 0, median > 0 else { return threshold <= 0 ? 1 : 0 }
        let z = log(threshold / median) / sigma(gini: gini)
        return 0.5 * erfc(z / 2.0.squareRoot())
    }
}

extension Country {
    /// Median household income level of a city in reference-median multiples.
    public func medianIncome(in city: City) -> Double { wageLevel * city.affluence }

    /// Households of a city by income band.
    public func incomeBands(in city: City) -> IncomeBands {
        let m = medianIncome(in: city), g = city.inequality, k = city.price.squareRoot()
        let a = IncomeModel.shareAbove(IncomeModel.budgetBelow * k, median: m, gini: g)
        let b = IncomeModel.shareAbove(IncomeModel.premiumFrom * k, median: m, gini: g)
        let c = IncomeModel.shareAbove(IncomeModel.luxuryFrom * k, median: m, gini: g)
        return IncomeBands(budget: 1 - a, middle: a - b, upper: b - c, affluent: c)
    }

    /// Share of a city's households with an income above `threshold` (reference-median multiples, before local prices).
    public func shareAbove(_ threshold: Double, in city: City) -> Double {
        IncomeModel.shareAbove(threshold * city.price.squareRoot(), median: medianIncome(in: city), gini: city.inequality)
    }

    /// The same for the country as a whole: its median, Gini and price level.
    public func nationalShareAbove(_ threshold: Double) -> Double {
        IncomeModel.shareAbove(threshold * priceLevel.squareRoot(), median: wageLevel, gini: gini)
    }
}

/// Real-life place data kept apart from `countries.json` (`Resources/city_market.json`), merged into each country's data when the
/// book is loaded: extra fields of existing cities, extra (larger and smaller) cities, the country's Gini. Sources and dates are in
/// docs/CITY_DATA.md.
///
/// ```
/// { "countries": { "NO": { "gini": 0.27,
///     "cities": { "oslo": { "metro": 1550, "tour": 1.4 } },        // patch an existing city (any field, `pop` `rent` `wage` `dem` `price` too)
///     "add": [ { "id": "drammen", "name": "Drammen", "pop": 105, ... } ] } } }
/// ```
/// City fields: `metro` (metropolitan population, thousands), `inc` (median household income against the country's), `gini`,
/// `tour` (tourist intensity against the country's tourism share).
public enum CityMarketData {
    public static func bundled() -> JSONValue {
        guard let url = Bundle.module.url(forResource: "city_market", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }

    /// A country's data file entry with the overlay applied.
    public static func merge(_ pack: JSONValue, overlay: JSONValue) -> JSONValue {
        let o = overlay["countries"][pack["code"].string]
        if o.isNull { return pack }
        var p = pack
        if !o["gini"].isNull { p["gini"] = o["gini"] }
        var cities = p["cities"].array
        for (id, patch) in o["cities"].object {
            guard let i = cities.firstIndex(where: { $0["id"].string == id }) else { continue }
            for (k, v) in patch.object { cities[i][k] = v }
        }
        let have = Set(cities.map { $0["id"].string })
        for c in o["add"].array where !have.contains(c["id"].string) { cities.append(c) }
        p["cities"] = .array(cities)
        return p
    }
}

extension Country.City {
    /// Fill the place data of a city from its data entry; what the data does not say is derived (docs/CITY_DATA.md).
    static func withPlaceData(_ city: Country.City, entry x: JSONValue, countryGini: Double, wageLevel: Double) -> Country.City {
        var c = city
        let pop = max(1, c.population)
        c.metro = x["metro"].isNull ? pop * (1 + 0.35 * clamp(log10(pop / 100), 0, 2)) : x["metro"].double
        c.affluence = x["inc"].isNull ? clamp(c.wage / max(0.01, wageLevel), 0.55, 1.6) : x["inc"].double
        c.inequality = clamp(x["gini"].isNull ? countryGini + 0.04 * clamp(log10(pop / 200), -0.7, 1.6) : x["gini"].double, 0.2, 0.65)
        c.touristIndex = x["tour"].isNull ? 1 : x["tour"].double
        return c
    }
}
