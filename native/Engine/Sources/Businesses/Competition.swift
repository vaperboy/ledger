import Foundation
import GameCore
import Countries

/// Competitors and your own other outlets. Originals: `rivalMult`, `disMult`, `ownShare`, `reachOf`.
public enum Competition {
    /// How rivals in the same city and trade take customers from you, given your price against theirs.
    /// Original: `rivalMult` (price_moves_and_lawsuits.js).
    public static func rivalFactor(_ co: Company, _ w: World) -> Double {
        guard let m = w.market(for: co) else { return 1 }
        let pi = m["pi"].double == 0 ? 1 : m["pi"].double
        let r0 = Pricing.priceIndex(co, w) / pi
        let dv = r0 - 1
        let ratio = 1 + dv * min(1, abs(dv) / 0.06)
        var mult = 1 - min(0.3, 0.035 * m["n"].double) * (0.7 + 0.5 * m["str"].double)
        mult *= ratio > 1 ? exp(-0.9 * (ratio - 1)) : exp(0.35 * (1 - ratio))
        mult *= cheapRivalFactor(co, m, w)
        let v = clamp(mult, 0.2, 1.25)
        let push = m["str16"].double
        return push != 0 ? clamp(v * (1 - push * 0.3), 0.2, 1.25) : v
    }

    /// A cheap rival that entered with a loophole hits expensive operations hardest. Original: `disMult`.
    static func cheapRivalFactor(_ co: Company, _ m: JSONValue, _ w: World) -> Double {
        let dis = m["dis"]
        if dis.isNull { return 1 }
        let pl = w.country(co).priceLevel
        let expo = clamp(0.45 + 0.6 * ((pl == 0 ? 1 : pl) - 0.5) + (co.priceLevel > 0 ? 0.08 * co.priceLevel : 0), 0.35, 1.3)
        let shield = clamp((co.quality - 60) / 120, 0, 0.3) + clamp((co.reputation - 60) / 200, 0, 0.12)
        return 1 - clamp(dis["depth"].double * expo * (1 - shield), 0, 0.45)
    }

    // MARK: Own outlets

    static func isFootTraffic(_ kind: String) -> Bool { ["shop", "kitchen", "hotel", "gym", "clinic"].contains(kind) }

    /// How much two of your outlets in the same city fish in the same pond. Original: `cityOverlap`, `ownOverlap`.
    static func overlap(_ a: Company, _ b: Company, _ w: World) -> Double {
        let pop = w.city(a)?.population ?? 100
        var ov = clamp(0.25 * (300 / (pop == 0 ? 100 : pop)).squareRoot(), 0.12, 0.8)
        let tiers = w.catalog.tables.raw["PL_TIERS"].array.map { $0[0].string }
        func tier(_ c: Company) -> Int {
            let n = c.value("prem")["lname"]
            return n.isNull ? -1 : (tiers.firstIndex(of: n.string) ?? -1)
        }
        let prem = a.value("prem")
        if !prem.isNull, isFootTraffic(prem["kind"].string) {
            let x = tier(a), y = tier(b)
            if x >= 3 && y >= 3 { ov *= 1.6 }
            else if (x >= 0 && x <= 1) || (y >= 0 && y <= 1) { ov *= 0.6 }
        }
        return min(0.9, ov)
    }

    /// Your share of the local customers when you run several outlets of the same trade in a city. Original: `ownShare`.
    public static func ownOutletShare(_ co: Company, _ w: World) -> Double {
        var t = 0.0
        for c in w.state.companies where c.id != co.id && c.status == .open && c.type == co.type && c.cityID == co.cityID && c.countryCode == co.countryCode {
            t += overlap(co, c, w)
        }
        return 1 / (1 + t)
    }

    /// Number of outlets of this trade you own (including franchise units). Original: `chainOutlets`.
    public static func chainOutlets(_ co: Company, _ w: World) -> Int {
        var n = 0
        for c in w.state.companies where c.type == co.type && c.status.isLive {
            n += 1
            let fr = c.value("fr")
            if fr["on"].bool {
                n += fr["units"].array.count
                for m in fr["masters"].array where Double(w.week) >= m["ready"].double { n += m["n"].int }
            }
        }
        // A franchisee belongs to a brand with many units. Original: `chainOutlets`, `co.franchise.brandId`.
        let brandID = co.value("franchise")["brandId"]
        if !brandID.isNull, let b = FranchiseBrands.brand(brandID.string, w) { n = max(n, b.units + 1) }
        return max(1, n)
    }

    /// Chain reach multiplier on demand: many outlets build a known brand. Original: `reachOf(co).mult`.
    public static func chainReachFactor(_ co: Company, _ w: World) -> Double {
        1 + 0.03 * log2(Double(chainOutlets(co, w)))
    }
}
