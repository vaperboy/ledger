import Foundation
import GameCore

public struct Balance: Sendable {
    public var demandDesignFactor: Double
    public var economySensitivity: [String: Double]
    public var defaultDemandLevel: Double
    public var fitSpread: Double
    public var demandLevelByTrade: [String: Double]
    public var priceLevelByTrade: [String: Double]
    public var customerFacingRoles: Set<String>
    public var targetMargins: [String: Double]
    public var priceMultipliers: [Double]
    public var priceNames: [String]
    public var priceRangeByTrade: [String: [Double]]
    public var tourismShareByTrade: [String: Double]
    public var eventRamp: [(week: Int, mult: Double)]
    public var firstYear: FirstYear
    public var tourismSeasonByCountry: [String: [Double]]
    public var weather: WeatherTables
    public var tradeCountryFit: (demand: [String: [String: Double]], price: [String: [String: Double]])
    public var salesWays: [String: [SalesWay]]
    public var cityMarket: CityMarketTables
    public var mastery: Mastery

    public struct Mastery: Sendable {
        public var organicScale = 1.0
        public var rivalMoat = 0.0
        public var chainReach = 0.03
        public var overlapScale = 1.0
        init(json j: JSONValue) {
            func n(_ k: String, _ d: Double) -> Double { j[k].isNull ? d : j[k].double }
            organicScale = n("organicScale", organicScale); rivalMoat = n("rivalMoat", rivalMoat); chainReach = n("chainReach", chainReach)
            overlapScale = n("overlapScale", overlapScale)
        }
    }

    public struct SalesWay: Sendable {
        public var kind: String
        public var name: String
        public var client: String
        public var options: [String: Double]
        public var peakMonths: [Int]
    }

    public init(json j: JSONValue, weatherJSON: JSONValue, waysJSON: JSONValue, marketJSON: JSONValue = .null) {
        cityMarket = CityMarketTables(json: marketJSON)
        mastery = Mastery(json: j["mastery"])
        weather = WeatherTables(json: weatherJSON)
        salesWays = waysJSON["W"].object.mapValues { list in
            list.array.map { w in
                SalesWay(kind: w[0].string, name: w[1].string, client: w[2].string,
                         options: w[3].object.compactMapValues { $0.isNumber ? $0.double : nil },
                         peakMonths: w[3]["m"].array.map { $0.int })
            }
        }
        let ramp = j["eventRamp"].array.map { (week: $0["week"].int, mult: $0["mult"].double) }.sorted { $0.week < $1.week }
        eventRamp = ramp
        firstYear = FirstYear(json: j["firstYear"])
        let d = j["demand"]
        demandDesignFactor = d["DK"].double
        economySensitivity = d["SENS"].object.mapValues { $0.double }
        defaultDemandLevel = d["K"].double
        fitSpread = d["fitSpread"].double
        demandLevelByTrade = d["demandLevelByTrade"].object.mapValues { $0.double }
        priceLevelByTrade = d["priceLevelByTrade"].object.mapValues { $0.double }
        customerFacingRoles = Set(d["customerFacingRoles"].array.map { $0.string })
        targetMargins = j["targetMargins"].object.mapValues { $0.double }
        priceMultipliers = j["priceLevels"]["multipliers"].array.map { $0.double }
        priceNames = j["priceLevels"]["names"].array.map { $0.string }
        priceRangeByTrade = j["priceLevels"]["ranges"].object.mapValues { $0.array.map { $0.double } }
        tourismShareByTrade = j["tourism"]["tradeShare"].object.mapValues { $0.double }
        func fit(_ v: JSONValue) -> [String: [String: Double]] { v.object.mapValues { $0.object.mapValues { $0.double } } }
        tradeCountryFit = (fit(j["tradeCountryFit"]["demand"]), fit(j["tradeCountryFit"]["price"]))
        tourismSeasonByCountry = j["tourism"]["seasonByCountry"].object.mapValues { $0.array.map { $0.double } }
    }

    public static func bundled() throws -> Balance {
        func load(_ n: String) throws -> JSONValue {
            guard let url = Bundle.module.url(forResource: n, withExtension: "json", subdirectory: "Resources") else { throw CocoaError(.fileNoSuchFile) }
            return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        }
        var json = try load("balance")
        for (id, k) in TradeTuning.bundled()["demandLevel"].object { json["demand"]["demandLevelByTrade"][id] = k }
        return Balance(json: json, weatherJSON: try load("weather"), waysJSON: try load("sales_ways"), marketJSON: try load("market_classes"))
    }

    public func eventRampMultiplier(week: Int) -> Double {
        eventRamp.last(where: { $0.week <= week })?.mult ?? 1
    }

    public func priceMultiplier(level: Double) -> Double {
        let L = clamp(level, -3, 3)
        let i = min(5, Int(saturating: (L + 3).rounded(.down)))
        let f = L + 3 - Double(i)
        return priceMultipliers[i] + (priceMultipliers[i + 1] - priceMultipliers[i]) * f
    }

    public func priceBounds(tradeID: String) -> (low: Double, high: Double) {
        let lo = priceMultipliers[0], hi = priceMultipliers[6]
        guard let r = priceRangeByTrade[tradeID], r.count == 2 else { return (lo, hi) }
        return (max(lo, r[0]), min(hi, r[1]))
    }

    public func priceLevel(multiplier: Double) -> Double {
        let pm = clamp(multiplier, priceMultipliers[0], priceMultipliers[6])
        var i = 0
        while i < 5 && pm > priceMultipliers[i + 1] { i += 1 }
        return jsRound((Double(i - 3) + (pm - priceMultipliers[i]) / (priceMultipliers[i + 1] - priceMultipliers[i])) * 1000) / 1000
    }
}
