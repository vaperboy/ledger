import Foundation
import GameCore
import Countries

/// Prices: what one sale costs the customer, and how customers react to price changes.
/// Originals: `ticketEff`, `ticketMult`, `priceMult`, `priceDem` (engine/company/model.js and the later
/// price features).
public enum Pricing {
    static let noWorkFamilies: Set<String> = ["rent", "fin", "energy", "club", "hold"]

    // MARK: Price level

    /// Current price index of a company: its price level times any running discount. Original: `priceMult`.
    public static func priceIndex(_ co: Company, _ w: World) -> Double {
        w.balance.priceMultiplier(level: co.priceLevel) * (1 - discount(co, w.week))
    }

    /// Discount of a running campaign, as a share. Original: `campPct`.
    public static func discount(_ co: Company, _ week: Int) -> Double {
        let c = co.value("camp16")
        if c.isNull { return 0 }
        return Double(week) < c["end"].double ? c["pct"].double / 100 : 0
    }

    /// Star rating 1.5 - 4.9 shown to customers. Original: `ratingOf`.
    public static func rating(_ co: Company) -> Double {
        jsRound(clamp(1.8 + (co.quality * 0.6 + co.reputation * 0.4) / 100 * 3.1, 1.5, 4.9) * 10) / 10
    }

    /// How much a luxury brand needs a name to sell. Original: `brandPull`.
    public static func brandPull(_ co: Company) -> Double { clamp((co.reputation + co.awareness) / 170, 0, 1) }

    // MARK: Ticket (price of one sale)

    /// Original: `locF`. Local wages, rents and prices change what a haircut costs in a city.
    static func localFactor(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard let c = w.city(co), c.price != 0, bd.normalDemand != 0, !noWorkFamilies.contains(bd.family) else { return 1 }
        let (ws, rs) = costShares(bd, w.catalog.tables)
        let f = (ws * (c.wage == 0 ? 1 : c.wage) + rs * (c.rent == 0 ? 1 : c.rent) + (1 - ws - rs) * c.price) / c.price
        return 1 + (f - 1) * 0.85
    }

    /// Share of revenue that goes to wages and to rent, for a normal business of this trade. Original: `shares(bd)`.
    static func costShares(_ bd: Trade, _ t: TradeTables) -> (Double, Double) {
        let R0 = max(1, bd.normalDemand * bd.ticket)
        var W = 0.0
        for s in bd.standardStaff { W += s.count * (t.roles[s.role]?.baseMonthlyWage ?? 0) * 12 / 52 * 1.166 * 1.2 }
        var Rn = 0.0
        if let k = bd.premisesKind, let p = t.premises[k] { Rn = bd.premisesM2 * p.rentPerM2Year / 52 }
        var ws = W / R0, rs = Rn / R0
        let total = ws + rs
        if total > 0.85 { ws *= 0.85 / total; rs *= 0.85 / total }
        return (ws, rs)
    }

    /// Smaller contractors take more, smaller jobs. Original: `R8.jobScale`.
    public static func jobScale(_ co: Company) -> Double {
        clamp(0.5 * pow(clamp(co.size, 0.3, 1.5), 0.9), 0.15, 0.8)
    }

    /// All the factors on the base ticket. Original: `ticketMult` + steps.
    public static func ticketMultiplier(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let city = w.city(co)
        var m = Knobs.effect(co, bd, "t", w) * priceIndex(co, w) * (city?.price ?? 1) * w.inflationIndex
        // Holding prices while inflation runs (the "hold my prices" decision) divides by the growth you skipped.
        let ig = co.num("ig", 1)
        if ig != 1 { m /= ig }
        m *= localFactor(co, bd, w)
        if bd.family == "project" {
            m *= bd.hasTrait("dev") ? 1 : jobScale(co)
        } else {
            m *= w.balance.priceLevelByTrade[bd.id] ?? 1
        }
        m *= wineCountryFactor(co)
        return m
    }

    /// Famous wine countries sell dearer. Original: `FIT57.price`.
    static func wineCountryFactor(_ co: Company) -> Double {
        guard co.type == "vineyard" else { return 1 }
        let t: [String: Double] = ["FR": 1.15, "IT": 1.15, "ES": 1.05, "UK": 1.05]
        return t[co.countryCode] ?? 1
    }

    /// What one sale costs a customer today, in accounting units. Original: `ticketEff`.
    public static func ticket(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let raw = bd.ticket * bd.ticketMultiplier * ticketMultiplier(co, bd, w) * (1 + (co.reputation - 50) / 500)
        let fx = w.rates.rate(w.country(co))
        return Currency.nicePrice(raw / fx) * fx
    }

    // MARK: Customer reaction

    /// How much demand changes with the price: cheaper pulls customers, dearer loses them, and recent price
    /// changes are noticed. Original: `priceDem`.
    public static func demandEffect(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let base = w.balance.priceMultiplier(level: co.priceLevel)
        let cp = discount(co, w.week)
        let eff = base * (1 - cp), effL = base * (1 - cp * 0.6)
        let sat = clamp((rating(co) - 3.8) / 0.9, 0, 1)
        let e0 = bd.elasticity
        let ela = e0 * (1 - 0.3 * sat)
        // A few percent off the market price hardly registers; bigger gaps count in full.
        let dev = effL - 1
        let pe = 1 + dev * min(1, abs(dev) / 0.06)
        var d: Double
        if pe <= 1 {
            d = pow(pe, -ela)
        } else {
            let lvl = w.balance.priceLevel(multiplier: pe)
            let luxuryExponent = lvl <= 1 ? 0 : (lvl - 1) * 1.5
            d = pow(pe, -ela * 0.7) * pow(0.45 + 0.55 * brandPull(co), luxuryExponent)
        }
        // A change people notice: compared with what they are used to paying.
        let ref = co.value("pref16").isNull ? base : co.num("pref16")
        let x = eff / ref - 1
        if x > 0.03 {
            let mpi = w.market(for: co)?["pi"].double ?? 1
            let tol = clamp(0.2 + 0.45 * sat + (eff <= mpi ? 0.35 : 0), 0, 0.9)
            d *= exp(-(x - 0.03) * e0 * 1.3 * (1 - tol))
        } else if x < -0.03 && cp == 0 {
            d *= 1 + min(0.5, (-x - 0.03) * e0 * 0.9 * clamp(co.awareness / 60, 0.25, 1))
        }
        if cp != 0 { d *= 1 + cp * 0.8 * discountFatigue(co, w.week) }
        return d
    }

    /// Customers get used to sales: the more weeks on discount lately, the less a new one pulls. Original: `fat`.
    static func discountFatigue(_ co: Company, _ week: Int) -> Double {
        let start = co.value("camp16").isNull ? Double(week) : co.value("camp16")["w0"].double
        let recent = co.value("cw16").array.filter { Double(week) - $0.double < 13 && $0.double < start }.count
        return clamp(1 - Double(recent) / 13 * 1.4, 0.25, 1)
    }

    /// Prices do not have a fixed effect: cheaper does not always bring more people. Original: `elast`.
    static func elasticityDrift(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let pd = demandEffect(co, bd, w)
        if abs(pd - 1) < 1e-6 { return 1 }
        var m2 = clamp(0.8 + 0.3 * SeededNoise.wave(seed: w.state.seed, key: "el\(co.id)", week: w.week)
                       + 0.4 * (SeededNoise.smooth(seed: w.state.seed, key: "el\(co.id)", week: w.week, span: 6) - 0.5), 0.2, 1.4)
        if co.priceLevel > 0 && co.quality > 68 { m2 *= 0.6 }
        return pow(pd, m2 - 1)
    }
}
