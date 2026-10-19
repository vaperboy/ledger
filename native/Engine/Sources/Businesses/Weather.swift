import Foundation
import GameCore

/// Weather: each country has a climate; every week's weather is drawn from the game seed, so the same game
/// always has the same weather. Weather changes how many customers come and, for outdoor work, how much can be
/// done. Original: features/world/weather_and_tourism.js. Climate tables are in `Resources/weather.json`.
public struct WeatherTables: Sendable {
    /// Per country: [average °C by month], [share of days with rain or snow by month]
    var climate: [String: (temperature: [Double], wetShare: [Double])]
    var temperatureSpread: [String: Double]
    /// Per trade: [sensitivity to pleasant weather, demand effect by weather kind, capacity effect by kind]
    var tradeSensitivity: [String: Sensitivity]
    var familySensitivity: [String: Sensitivity]

    struct Sensitivity: Sendable {
        var pleasantWeather: Double
        var demandByKind: [String: Double]
        var capacityByKind: [String: Double]
    }

    init(json j: JSONValue) {
        climate = j["CL"].object.mapValues { ($0[0].array.map { $0.double }, $0[1].array.map { $0.double }) }
        temperatureSpread = j["SD"].object.mapValues { $0.double }
        func sens(_ v: JSONValue) -> Sensitivity {
            Sensitivity(pleasantWeather: v[0].double,
                        demandByKind: v[1].object.mapValues { $0.double },
                        capacityByKind: v[2].object.mapValues { $0.double })
        }
        tradeSensitivity = j["SENS"].object.mapValues(sens)
        familySensitivity = j["FAM"].object.mapValues(sens)
    }
}

public struct WeekWeather: Equatable, Sendable {
    public var temperature: Double
    public var rainyDays: Int
    /// "sun", "mixed", "rain", "snow", "heat", "cold" or "storm"
    public var kind: String
    /// How pleasant, against what is normal for the month
    public var againstNormal: Double
    public var snowIsNormal: Bool
}

public enum Weather {
    /// The chance a week brings a storm, by country and month (0 = January). Original: `stormP`.
    static func stormChance(_ cc: String, month m: Int) -> Double {
        let winter = m >= 9 || m <= 1
        if ["NO", "UK", "NL", "DE", "FR", "SE", "LT", "PL", "CA", "DK", "FI", "IE"].contains(cc) { return winter ? 0.035 : 0.006 }
        if cc == "IT" { return m >= 9 && m <= 11 ? 0.025 : 0.006 }
        if cc == "SG" { return m >= 10 || m <= 1 ? 0.03 : 0.012 }
        if cc == "CH" { return winter ? 0.02 : 0.006 }
        if cc == "US" || cc == "MX" { return m >= 7 && m <= 9 ? 0.05 : 0.008 }
        if cc == "JP" || cc == "KR" { return m >= 6 && m <= 8 ? 0.06 : 0.006 }
        if cc == "AU" || cc == "BR" { return m >= 11 || m <= 2 ? 0.03 : 0.006 }
        if cc == "AE" { return m >= 2 && m <= 5 ? 0.03 : 0.004 }
        if cc == "ES" { return m >= 8 && m <= 10 ? 0.02 : 0.005 }
        return 0.01
    }

    static func pleasantness(_ t: Double, _ r: Double) -> Double {
        clamp(1 - abs(t - 22) / 16, -1, 1) * 0.6 + (1 - r / 3.5) * 0.4
    }

    /// The weather of a country in a week. Original: `draw(cc, w)`.
    public static func draw(country cc: String, week: Int, seed: Int, tables: WeatherTables) -> WeekWeather {
        let c = tables.climate[cc] ?? tables.climate["NO"]!
        let m = GameCalendar.month(week: week)
        func nz(_ r: inout HashedRandom) -> Double { (r.next() + r.next() + r.next() - 1.5) * 2 }
        var a = 0.0
        for k in 0..<6 {
            var r = HashedRandom("\(seed):wx:\(cc):\(week - k)")
            a += pow(0.6, Double(k)) * nz(&r)
        }
        a *= 0.8
        var R = HashedRandom("\(seed):wx2:\(cc):\(week)")
        let t = jsRound(c.temperature[m] + a * (tables.temperatureSpread[cc] ?? 3.2))
        let wet = clamp(c.wetShare[m] * (1 + 0.35 * nz(&R)), 0, 0.95)
        var rain = 0
        for _ in 0..<7 where R.next() < wet { rain += 1 }
        let storm = R.next() < stormChance(cc, month: m)
        let avg = c.temperature[m]
        let kind = storm ? "storm"
            : (rain >= 3 && t <= 0) ? "snow"
            : t >= max(22, avg + 5) ? "heat"
            : t <= min(-5, avg - 5.5) ? "cold"
            : rain >= 4 ? "rain" : rain >= 2 ? "mixed" : "sun"
        let n = pleasantness(t, Double(rain))
        return WeekWeather(temperature: t, rainyDays: rain, kind: kind,
                           againstNormal: n - pleasantness(avg, c.wetShare[m] * 7), snowIsNormal: avg <= -1)
    }

    /// What this week's weather does to a company: (demand factor, capacity factor). Original: `fx(co)`.
    public static func effect(for co: Company, trade: Trade, week: Int, seed: Int, tables: WeatherTables) -> (demand: Double, capacity: Double) {
        guard let s = tables.tradeSensitivity[co.type] ?? tables.familySensitivity[trade.family] else { return (1, 1) }
        let x = draw(country: co.countryCode, week: week, seed: seed, tables: tables)
        let u = (x.kind == "snow" && x.snowIsNormal) ? 0.3 : 1.0
        var d = clamp(1 + s.pleasantWeather * x.againstNormal, 0.6, 1.4)
        if let f = s.demandByKind[x.kind] { d *= 1 + (f - 1) * u }
        var c = 1.0
        if let f = s.capacityByKind[x.kind] { c *= 1 + (f - 1) * u }
        if trade.family == "project" && x.rainyDays > 3 { c *= 1 - 0.035 * Double(x.rainyDays - 3) }
        return (d, c)
    }
}
