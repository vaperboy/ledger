import Foundation
import GameCore

public struct IncomeBands: Equatable, Sendable {
    public var budget: Double
    public var middle: Double
    public var upper: Double
    public var affluent: Double
    public var canAffordPremium: Double { upper + affluent }
}

public enum IncomeModel {
    public static let budgetBelow = 0.7
    public static let premiumFrom = 1.5
    public static let luxuryFrom = 4.0

    public static func sigma(gini: Double) -> Double {
        let g = clamp(gini, 0.05, 0.9)
        var x = g * 1.2
        for _ in 0..<40 {
            let f = erf(x) - g, d = 2 / Double.pi.squareRoot() * exp(-x * x)
            if d < 1e-12 { break }
            x -= f / d
        }
        return 2 * x
    }

    public static func shareAbove(_ threshold: Double, median: Double, gini: Double) -> Double {
        guard threshold > 0, median > 0 else { return threshold <= 0 ? 1 : 0 }
        let z = log(threshold / median) / sigma(gini: gini)
        return 0.5 * erfc(z / 2.0.squareRoot())
    }
}

extension Country {
    public func medianIncome(in city: City) -> Double { wageLevel * city.affluence }

    public func incomeBands(in city: City) -> IncomeBands {
        let m = medianIncome(in: city), g = city.inequality, k = city.price.squareRoot()
        let a = IncomeModel.shareAbove(IncomeModel.budgetBelow * k, median: m, gini: g)
        let b = IncomeModel.shareAbove(IncomeModel.premiumFrom * k, median: m, gini: g)
        let c = IncomeModel.shareAbove(IncomeModel.luxuryFrom * k, median: m, gini: g)
        return IncomeBands(budget: 1 - a, middle: a - b, upper: b - c, affluent: c)
    }

    public func shareAbove(_ threshold: Double, in city: City) -> Double {
        IncomeModel.shareAbove(threshold * city.price.squareRoot(), median: medianIncome(in: city), gini: city.inequality)
    }

    public func nationalShareAbove(_ threshold: Double) -> Double {
        IncomeModel.shareAbove(threshold * priceLevel.squareRoot(), median: wageLevel, gini: gini)
    }
}

public enum CityMarketData {
    public static func bundled() -> JSONValue {
        guard let url = Bundle.module.url(forResource: "city_market", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }

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
        for c in o["add"].array where !have.contains(c["id"].string) { var e = c; e["extra"] = .bool(true); cities.append(e) }
        p["cities"] = .array(cities)
        return p
    }
}

extension Country.City {
    static func withPlaceData(_ city: Country.City, entry x: JSONValue, countryGini: Double, wageLevel: Double) -> Country.City {
        var c = city
        let pop = max(1, c.population)
        c.metro = max(pop, x["metro"].isNull ? pop * (1 + 0.35 * clamp(log10(pop / 100), 0, 2)) : x["metro"].double)
        c.affluence = x["inc"].isNull ? clamp(c.wage / max(0.01, wageLevel), 0.55, 1.6) : x["inc"].double
        c.inequality = clamp(x["gini"].isNull ? countryGini + 0.04 * clamp(log10(pop / 200), -0.7, 1.6) : x["gini"].double, 0.2, 0.65)
        c.touristIndex = x["tour"].isNull ? 1 : x["tour"].double
        c.isExtra = x["extra"].bool
        return c
    }
}
