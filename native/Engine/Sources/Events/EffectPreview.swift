import Foundation
import GameCore
import Countries

/// Plain-language preview of what an answer will do, shown before the player commits. Reads the same `fx` data
/// that `EventEngine.apply` uses, so a preview can never promise something the answer does not do.
public enum EffectPreview {
    public static func lines(_ fx: JSONValue, currency: Currency) -> [String] {
        if fx.isNull { return [] }
        var out: [String] = []
        if !fx["gamble"].isNull {
            let g = fx["gamble"]
            out.append("A gamble: \(Int((g["p"].double * 100).rounded()))% chance of the good outcome")
            out += lines(g["ok"], currency: currency).map { "If it works: " + $0 }
            out += lines(g["bad"], currency: currency).map { "If not: " + $0 }
        }
        func money(_ v: Double) -> String { currency.format(whole(v, currency)) }
        let cash = fx["cash"].double
        if cash < 0 { out.append("Costs \(money(-cash))") } else if cash > 0 { out.append("Brings in \(money(cash))") }
        if fx["loss"].double != 0 { out.append("Risk of a loss up to \(money(abs(fx["loss"].double)))") }
        if fx["fine"].double != 0 { out.append("Fine of \(money(fx["fine"].double))") }
        func sign(_ v: Double, _ what: String) { if v != 0 { out.append("\(v > 0 ? "+" : "−")\(Int(abs(v).rounded())) \(what)") } }
        sign(fx["rep"].double, "reputation")
        sign(fx["aware"].double, "awareness")
        sign(fx["q"].double, "quality")
        func timed(_ key: String, _ what: String) {
            let v = fx[key]
            if v.isNull { return }
            let m = v[0].double, w = Int(v[1].double.rounded())
            out.append("\(what) \(m >= 1 ? "+" : "−")\(Int((abs(m - 1) * 100).rounded()))% for \(w) week\(w == 1 ? "" : "s")")
        }
        timed("dem", "Demand"); timed("cap", "Capacity"); timed("price", "Prices"); timed("cogsUp", "Cost of sales")
        if fx["pr"].double != 0 { out.append("Price level \(fx["pr"].double > 0 ? "up" : "down")") }
        if fx["quit"].bool { out.append("An employee may leave") }
        if fx["brk"].bool { out.append("Equipment may break") }
        if fx["fixeq"].double != 0 { out.append("Repairs your worst equipment") }
        if fx["warn"].bool { out.append("A warning on record: demand −7% for 6 weeks") }
        return out
    }

    // Whole thousands are written at the reference price level and scaled to the company's country (see EventEngine.apply).
    static func whole(_ v: Double, _ cur: Currency) -> Double {
        let a = abs(v)
        return a == a.rounded() && a.truncatingRemainder(dividingBy: 1000) == 0 ? cur.scaledPrice(a) : a
    }
}
