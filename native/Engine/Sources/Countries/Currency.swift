import Foundation
import GameCore

/// Exchange rates between the accounting unit and each country's currency.
///
/// A country's `fx` is its starting rate. Every month the rate of every country other than the player's home
/// country drifts slowly around that start (`drift`, 0.8 ... 1.25 of the start); the home currency is the player's yardstick.
/// No country is exempt: the original game left the Norwegian krone fixed, which made one country special.
/// The drift is part of the save (`fxd` in the original).
public struct ExchangeRates: Equatable, Sendable {
    public var drift: [String: Double]

    public init(drift: [String: Double] = [:]) { self.drift = drift }

    /// Accounting units per one unit of the country's currency right now. Original: `fxr(c)`.
    public func rate(_ country: Country) -> Double { country.fx * (drift[country.code] ?? 1) }

    /// Monthly drift step. Original: `fxMonthCore`. Uses the shared random stream, so call order matters.
    public mutating func monthlyDrift(book: CountryBook, homeCode: String, random: inout DeterministicRandom) {
        for c in book.countries {
            if c.code == homeCode { continue }
            let p = drift[c.code] ?? 1
            drift[c.code] = clamp(p * (1 + random.gauss() * 0.012 + (1 - p) * 0.06), 0.8, 1.25)
        }
    }
}

/// Rounding and formatting of money, always relative to one country's currency.
/// Amounts passed in and out are in accounting units unless a name says "local".
public struct Currency: Sendable {
    public let country: Country
    public let rate: Double   // accounting units per local unit

    public init(country: Country, rates: ExchangeRates) {
        self.country = country
        self.rate = rates.rate(country)
    }

    // MARK: Rounding (originals: nicePrice, rl, rnl, rlc)

    /// Round to a price people would really see: two significant figures, tidy steps above that. Original: `nicePrice`.
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

    /// Round an accounting amount to a tidy local price. Original: `rl(v)`.
    public func tidy(_ v: Double) -> Double { Currency.nicePrice(v / rate) * rate }

    /// Round to a tidy step in local money about `n` accounting units in size (exactly `n` in the reference
    /// country). Wages, prices and offers use it so every country sees round local numbers. Original: `rnl(v, n)`.
    public func roundedStep(_ v: Double, about n: Double) -> Double {
        let st = localStep(about: n)
        if rate == 1 && st == n { return jsRound(v / n) * n }
        return jsRound(v / rate / st) * st * rate
    }

    /// The step `roundedStep` rounds to, in accounting units. Lets a caller round a figure UP or DOWN to a tidy amount.
    public func stepSize(about n: Double) -> Double { localStep(about: n) * rate }

    private func localStep(about n: Double) -> Double {
        let s = n / rate
        let p = pow(10, log10(s).rounded(.down))
        let m = s / p
        return (m < 1.5 ? 1 : m < 3.5 ? 2 : m < 7.5 ? 5 : 10) * p
    }

    /// Scale a reference-economy price to this country's price level and round it tidily. Original: `KC(v, country)`.
    public func scaledPrice(_ v: Double) -> Double {
        if v == 0 { return v }
        let s: Double = v < 0 ? -1 : 1
        return s * tidy(abs(v) * country.costIndex)
    }

    // MARK: Formatting (originals: npad, money, mshort)

    /// Whole number with a non-breaking space between thousands: "1 234 567". Original: `npad`.
    public static func grouped(_ n: Double) -> String {
        let x = n.isFinite ? n : 0
        let digits = String(Int64(min(jsRound(abs(x)), 9.0e18)))   // Int64(Double) traps beyond about 9.22e18
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return String(out.reversed())
    }

    /// Full amount: "GBP 1 234" (with currency code) or just the number when `plain`. Negative uses a true minus sign. Original: `money`.
    public func format(_ n: Double, plain: Bool = false) -> String {
        let v = n / rate
        let neg = jsRound(v) < 0 && abs(v) >= 0.5
        return (neg ? "\u{2212}" : "") + (plain ? "" : country.currencyCode + " ") + Currency.grouped(v)
    }

    /// Full amount for screens: the currency symbol, then the number ("£3,482,600", "1 234 kr"). Not part of the original.
    public func display(_ n: Double) -> String {
        let v = n / rate
        let neg = jsRound(v) < 0 && abs(v) >= 0.5
        let sy = country.currencySymbol
        let behind = sy.count == 3 && sy.allSatisfy { $0.isUppercase && $0.isASCII } || sy == "kr" || sy == "zł"
        let digits = Currency.grouped(abs(v))
        if behind { return (neg ? "\u{2212}" : "") + digits + " " + sy }
        return (neg ? "\u{2212}" : "") + sy + digits.replacingOccurrences(of: "\u{00A0}", with: ",")
    }

    /// Compact amount: "£12.5 k", "£3.4 M". Original: `mshort`.
    public func short(_ n: Double) -> String {
        let v = short0(n)
        let sy = country.currencySymbol
        // kr, zł and three-letter codes go after the number; $, €, £ and the others in front.
        let behind = sy.count == 3 && sy.allSatisfy { $0.isUppercase && $0.isASCII } || sy == "kr" || sy == "zł"
        if behind { return v + " " + sy }
        return v.hasPrefix("\u{2212}") ? "\u{2212}" + sy + v.dropFirst() : sy + v
    }

    func short0(_ n: Double) -> String {
        let x = (n.isFinite ? n : 0) / rate
        let a = abs(x)
        let s = x < 0 ? "\u{2212}" : ""
        func trim(_ d: Double, _ digits: Int) -> String {
            // JavaScript: +(d).toFixed(digits) prints without trailing zeros
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

    /// Percent with sign-safe handling of non-finite values. Original: `pc(x, d)`.
    public static func percent(_ x: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", (x.isFinite ? x : 0) * 100) + "%"
    }
}

extension Country {
    /// Round for a country other than the current one. Original: `rlc(v, country)`.
    public func tidy(_ v: Double, fxRate: Double) -> Double { Currency.nicePrice(v / fxRate) * fxRate }
}
