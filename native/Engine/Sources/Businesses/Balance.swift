import Foundation
import GameCore

/// Balance settings: every tuning number that decides how easy or hard the game is, in one place.
/// Loaded from `Resources/balance.json`. Change a number there (no code change needed) and the game follows.
public struct Balance: Sendable {
    /// Customers per week are scaled by this many "design" units. Original: `DK`.
    public var demandDesignFactor: Double
    /// How strongly each business family feels the economy (0 = not at all, 1 = fully). Original: `SENS`.
    public var economySensitivity: [String: Double]
    /// Default demand level for trades without their own value. Original: `R8.K`.
    public var defaultDemandLevel: Double
    /// Spread of a company's hidden "fit" with its concept. Original: `R8.FIT`.
    public var fitSpread: Double
    public var demandLevelByTrade: [String: Double]
    public var priceLevelByTrade: [String: Double]
    /// Roles whose staff bring in customers (their numbers count towards demand). Original: `R8.FACE`.
    public var customerFacingRoles: Set<String>
    public var targetMargins: [String: Double]
    /// Price multipliers for the seven price levels (-3 ... +3) and their names. Original: `PRICE_PM`.
    public var priceMultipliers: [Double]
    public var priceNames: [String]
    /// Share of customers who are tourists, by trade. Original: `TOUR_T`.
    public var tourismShareByTrade: [String: Double]
    /// Twelve monthly tourism multipliers by country. Original: `WX56.TS`.
    public var tourismSeasonByCountry: [String: [Double]]
    public var weather: WeatherTables
    /// How each trade sells besides the till: contracts, platforms, memberships, peak seasons ... Original: `R33.W`.
    public var salesWays: [String: [SalesWay]]

    /// One way a trade sells. `kind`: contract, offer, referral, platform, members, peak, emergency, upsell.
    public struct SalesWay: Sendable {
        public var kind: String
        public var name: String
        public var client: String
        /// Numbers such as lift, fee, peak months `m` and boost `b`, upsell share `u`
        public var options: [String: Double]
        public var peakMonths: [Int]
    }

    public init(json j: JSONValue, weatherJSON: JSONValue, waysJSON: JSONValue) {
        weather = WeatherTables(json: weatherJSON)
        salesWays = waysJSON["W"].object.mapValues { list in
            list.array.map { w in
                SalesWay(kind: w[0].string, name: w[1].string, client: w[2].string,
                         options: w[3].object.compactMapValues { $0.isNumber ? $0.double : nil },
                         peakMonths: w[3]["m"].array.map { $0.int })
            }
        }
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
        tourismShareByTrade = j["tourism"]["tradeShare"].object.mapValues { $0.double }
        tourismSeasonByCountry = j["tourism"]["seasonByCountry"].object.mapValues { $0.array.map { $0.double } }
    }

    public static func bundled() throws -> Balance {
        func load(_ n: String) throws -> JSONValue {
            guard let url = Bundle.module.url(forResource: n, withExtension: "json", subdirectory: "Resources") else { throw CocoaError(.fileNoSuchFile) }
            return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        }
        return Balance(json: try load("balance"), weatherJSON: try load("weather"), waysJSON: try load("sales_ways"))
    }

    /// Price multiplier for a (possibly fractional) price level -3 ... +3. Original: `pmOf` (price_moves_and_lawsuits.js).
    public func priceMultiplier(level: Double) -> Double {
        let L = clamp(level, -3, 3)
        let i = min(5, Int((L + 3).rounded(.down)))
        let f = L + 3 - Double(i)
        return priceMultipliers[i] + (priceMultipliers[i + 1] - priceMultipliers[i]) * f
    }

    /// The inverse of `priceMultiplier`. Original: `lvlOf`.
    public func priceLevel(multiplier: Double) -> Double {
        let pm = clamp(multiplier, priceMultipliers[0], priceMultipliers[6])
        var i = 0
        while i < 5 && pm > priceMultipliers[i + 1] { i += 1 }
        return jsRound((Double(i - 3) + (pm - priceMultipliers[i]) / (priceMultipliers[i + 1] - priceMultipliers[i])) * 1000) / 1000
    }
}
