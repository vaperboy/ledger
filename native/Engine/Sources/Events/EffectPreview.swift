import Foundation
import GameCore
import Countries

public enum EffectPreview {
    public static func lines(_ fx: JSONValue, currency: Currency) -> [String] {
        if fx.isNull { return [] }
        var out: [String] = []
        if !fx["gamble"].isNull {
            let g = fx["gamble"]
            out.append("A gamble: \(Int(saturating: (g["p"].double * 100).rounded()))% chance of the good outcome")
            out += lines(g["ok"], currency: currency).map { "If it works: " + $0 }
            out += lines(g["bad"], currency: currency).map { "If not: " + $0 }
        }
        func money(_ v: Double) -> String { currency.display(whole(v, currency)) }
        let cash = fx["cash"].double
        if cash < 0 { out.append("Costs \(money(-cash))") } else if cash > 0 { out.append("Brings in \(money(cash))") }
        if fx["loss"].double != 0 { out.append("Risk of a loss up to \(money(abs(fx["loss"].double)))") }
        if fx["fine"].double != 0 { out.append("Fine of \(money(fx["fine"].double))") }
        func sign(_ v: Double, _ what: String) { if v != 0 { out.append("\(v > 0 ? "+" : "−")\(Int(saturating: abs(v).rounded())) \(what)") } }
        if !fx["tied"].isNull { out.append("Ties up \(money(fx["tied"]["a"].double)) in stock or credit for \(fx["tied"]["w"].int) weeks") }
        if fx["raise"].double > 0 { out.append("Pay up \(Int(saturating: (fx["raise"].double * 100).rounded()))% for good") }
        if fx["close"].double > 0 { out.append("Closed for \(Int(saturating: fx["close"].double.rounded())) week(s)") }
        sign(fx["rep"].double, "reputation")
        sign(fx["aware"].double, "awareness")
        sign(fx["q"].double, "quality")
        func timed(_ key: String, _ what: String) {
            let v = fx[key]
            if v.isNull { return }
            let m = v[0].double, w = Int(saturating: v[1].double.rounded())
            out.append("\(what) \(m >= 1 ? "+" : "−")\(Int(saturating: (abs(m - 1) * 100).rounded()))% for \(w) week\(w == 1 ? "" : "s")")
        }
        timed("dem", "Demand"); timed("cap", "Capacity"); timed("price", "Prices"); timed("cogsUp", "Cost of sales")
        if fx["pr"].double != 0 { out.append("Price level \(fx["pr"].double > 0 ? "up" : "down")") }
        if fx["special"].double > 0 && fx["special"].double < 1 { out.append("Halves the chance of the full hit") }
        if fx["quit"].bool { out.append("An employee may leave") }
        if fx["brk"].bool { out.append("Equipment may break") }
        if fx["ill"].double != 0 { out.append("Disease risk in the pens rises for a few weeks") }
        if fx["fixeq"].double != 0 { out.append("Repairs your worst equipment") }
        if fx["premUp"].double != 0 { out.append("Insurance premiums +\(Int(saturating: (fx["premUp"].double * 100).rounded()))% for \(fx["premWeeks"].int) weeks") }
        if fx["cyberLvl"].double != 0 { out.append("IT security raised (monthly fee applies)") }
        if fx["cyberTrain"].bool { out.append("Staff security training") }
        if fx["cyberTarget"].bool { out.append("Attack odds x1.8 for 26 weeks") }
        if fx["delegate"].bool { out.append("Your manager chooses the answer") }
        if fx["warn"].bool { out.append("A warning on record: demand −7% for 6 weeks") }
        return out
    }

    static func whole(_ v: Double, _ cur: Currency) -> Double { abs(v) }
}
