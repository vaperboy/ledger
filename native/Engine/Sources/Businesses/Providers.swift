import Foundation
import GameCore
import Countries

/// Accountants, law firms and insurers, each with a star rating that reflects their quality and price.
/// Original: `genProviders`, `poolFor` (engine/suppliers/providers.js). A pool is created per country, once.
public enum Providers {
    static func rating(_ r: inout DeterministicRandom) -> Double { jsRound(clamp(3.9 + r.gauss() * 0.62, 2.6, 4.9) * 10) / 10 }
    static func quality(fromRating r: Double) -> Double { clamp((r - 2.6) / 2.3, 0, 1) }

    static func providerName(kind: String, country: Country, _ r: inout DeterministicRandom) -> String {
        let words = country.pack["providerNames"]
        let accWords = words[0].array.map { $0.string }
        let stems = country.lastNames
        let a = r.pick(stems)
        let b = r.pick(stems.filter { $0 != a })
        let lawWord = words[1].isNull ? "Law" : words[1].string
        let insWord = words[2].isNull ? "Insurance" : words[2].string
        let suffix = words[3].isNull ? " Ltd" : words[3].string
        switch kind {
        case "law": return "\(a) & \(b) \(lawWord)"
        case "ins": return "\(a) \(insWord)"
        default: return "\(a) \(accWords.isEmpty ? "Accounting" : r.pick(accWords))\(suffix)"
        }
    }

    static func generate(kind: String, count n: Int, country: Country, state s: inout GameState) -> [JSONValue] {
        var out: [(rating: Double, value: JSONValue)] = []
        for _ in 0..<n {
            let rt = rating(&s.random)
            let q = quality(fromRating: rt)
            let reviews = jsRound(12 + pow(s.random.range(0, 1), 2) * 1400)
            var p: [String: JSONValue] = ["id": .number(Double(s.makeID())), "name": .string(providerName(kind: kind, country: country, &s.random)),
                                          "rating": .number(rt), "reviews": .number(reviews), "q": .number(0.4 + q * 0.52)]
            switch kind {
            case "acc":
                p["tier"] = ""
                p["fee"] = .number(roundTo(1400 * (0.7 + q * 1.9) * s.random.range(0.85, 1.2), step: 100))
                p["err"] = .number(max(0.015, 0.14 - q * 0.12))
            case "law":
                p["fee"] = .number(roundTo(3500 * (0.7 + q * 2.4) * s.random.range(0.85, 1.2), step: 100))
            default:
                p["premM"] = .number(jsRound((0.82 + q * 0.35 + s.random.range(-0.06, 0.08)) * 100) / 100)
                p["payM"] = .number(jsRound((0.7 + q * 0.29) * 100) / 100)
                p["fee"] = 0
            }
            out.append((rt, .object(p)))
        }
        return out.sorted { $0.rating > $1.rating }.map { $0.value }
    }

    /// The providers available in a country, created on first use. Original: `poolFor(code)`.
    public static func pool(for code: String, state s: inout GameState, countries: CountryBook) -> (accountants: [JSONValue], lawyers: [JSONValue], insurers: [JSONValue]) {
        var poolc = s.rest["poolc"] ?? .object([:])
        if poolc[code].isNull, let country = countries[code] {
            var acc = generate(kind: "acc", count: 6, country: country, state: &s)
            var law = generate(kind: "law", count: 6, country: country, state: &s)
            let ins = generate(kind: "ins", count: 6, country: country, state: &s)
            let w = country.wageLevel == 0 ? 1 : country.wageLevel
            let currency = Currency(country: country, rates: ExchangeRates())
            func scaleFee(_ list: inout [JSONValue]) {
                for i in list.indices where list[i]["fee"].double != 0 {
                    list[i]["fee"] = .number(currency.roundedStep(list[i]["fee"].double * w, about: 100))
                }
            }
            scaleFee(&acc); scaleFee(&law)
            poolc = poolc.object.isEmpty ? .object([:]) : poolc
            poolc[code] = .object(["acc": .array(acc), "law": .array(law), "ins": .array(ins)])
            s.rest["poolc"] = poolc
        }
        let p = (s.rest["poolc"] ?? .object([:]))[code]
        return (p["acc"].array, p["law"].array, p["ins"].array)
    }
}
