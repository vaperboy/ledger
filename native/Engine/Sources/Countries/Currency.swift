import Foundation
import GameCore

public struct ExchangeRates: Equatable, Sendable {
    public var drift: [String: Double]

    public init(drift: [String: Double] = [:]) { self.drift = drift }

    public func rate(_ country: Country) -> Double { country.fx * (drift[country.code] ?? 1) }

    public mutating func monthlyDrift(book: CountryBook, homeCode: String, random: inout DeterministicRandom) {
        for c in book.countries {
            if c.code == homeCode { continue }
            let p = drift[c.code] ?? 1
            drift[c.code] = clamp(p * (1 + random.gauss() * 0.012 + (1 - p) * 0.06), 0.8, 1.25)
        }
    }
}

public struct Currency: Sendable {
    public let country: Country
    public let rate: Double

    public init(country: Country, rates: ExchangeRates) {
        self.country = country
        self.rate = rates.rate(country)
    }

    public static func nicePrice(_ v: Double) -> Double {
        let a = abs(v)
        if a < 0.5 { return v }
        let st: Double
        if a < 10 { st = 0.5 } else if a < 20 { st = 1 } else if a < 100 { st = 5 } else if a < 500 { st = 10 }
        else if a < 1000 { st = 50 } else if a < 5000 { st = 100 } else if a < 10000 { st = 500 }
        else if a < 50000 { st = 1000 } else if a < 100000 { st = 5000 }
        else {
            let e = pow(10, (log10(a)).rounded(.down) - 1)
            let r = a / e
            st = r < 25 ? e : (r < 50 ? 2.5 * e : 5 * e)
        }
        let r = jsRound(a / st) * st
        return v < 0 ? -r : r
    }

    public func tidy(_ v: Double) -> Double { Currency.nicePrice(v / rate) * rate }

    public func roundedStep(_ v: Double, about n: Double) -> Double {
        let st = localStep(about: n)
        if rate == 1 && st == n { return jsRound(v / n) * n }
        return jsRound(v / rate / st) * st * rate
    }

    public func stepSize(about n: Double) -> Double { localStep(about: n) * rate }

    private func localStep(about n: Double) -> Double {
        let s = n / rate
        let p = pow(10, log10(s).rounded(.down))
        let m = s / p
        return (m < 1.5 ? 1 : m < 3.5 ? 2 : m < 7.5 ? 5 : 10) * p
    }

    public func scaledPrice(_ v: Double) -> Double {
        if v == 0 { return v }
        let s: Double = v < 0 ? -1 : 1
        return s * tidy(abs(v) * country.costIndex)
    }

    public static func grouped(_ n: Double) -> String {
        let x = n.isFinite ? n : 0
        let digits = String(Int64(min(jsRound(abs(x)), 9.0e18)))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return String(out.reversed())
    }

    public func format(_ n: Double, plain: Bool = false) -> String {
        let v = n / rate
        let neg = jsRound(v) < 0 && abs(v) >= 0.5
        return (neg ? "\u{2212}" : "") + (plain ? "" : country.currencyCode + " ") + Currency.grouped(v)
    }

    public func display(_ n: Double) -> String {
        let v = n / rate
        let neg = jsRound(v) < 0 && abs(v) >= 0.5
        let sy = country.currencySymbol
        let behind = sy.count == 3 && sy.allSatisfy { $0.isUppercase && $0.isASCII } || sy == "kr" || sy == "zł"
        let digits = Currency.grouped(abs(v))
        if behind { return (neg ? "\u{2212}" : "") + digits + " " + sy }
        return (neg ? "\u{2212}" : "") + sy + digits.replacingOccurrences(of: "\u{00A0}", with: ",")
    }

    public func short(_ n: Double) -> String {
        let v = short0(n)
        let sy = country.currencySymbol
        let behind = sy.count == 3 && sy.allSatisfy { $0.isUppercase && $0.isASCII } || sy == "kr" || sy == "zł"
        if behind { return v + " " + sy }
        return v.hasPrefix("\u{2212}") ? "\u{2212}" + sy + v.dropFirst() : sy + v
    }

    func short0(_ n: Double) -> String {
        let x = (n.isFinite ? n : 0) / rate
        let a = abs(x)
        let s = x < 0 ? "\u{2212}" : ""
        func trim(_ d: Double, _ digits: Int) -> String {
            let f = String(format: "%.\(digits)f", d)
            guard f.contains(".") else { return f }
            var t = f
            while t.hasSuffix("0") { t.removeLast() }
            if t.hasSuffix(".") { t.removeLast() }
            return t
        }
        if a >= 1e9 { return s + trim(a / 1e9, 2) + " bn" }
        if a >= 1e6 { return s + trim(a / 1e6, a >= 1e7 ? 1 : 2) + " M" }
        if a >= 1e4 { return s + String(Int64(jsRound(a / 1e3))) + " k" }
        return s + Currency.grouped(a)
    }

    public static func percent(_ x: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", (x.isFinite ? x : 0) * 100) + "%"
    }
}

extension Country {
    public func tidy(_ v: Double, fxRate: Double) -> Double { Currency.nicePrice(v / fxRate) * fxRate }
}
