import Foundation
import GameCore
import Countries

/// VAT / sales tax for a company. Originals: `vatExempt`, `vatRate` (engine/company/model.js).
public enum Vat {
    /// Below the country's turnover threshold, and not registered, a company charges no VAT.
    public static func isExempt(_ co: Company, _ w: World) -> Bool {
        let c = w.country(co)
        let threshold = c.vatThreshold
        if threshold <= 0 || Knobs.documentOK(co, "vat") { return false }
        let t12 = co.monthlyHistory.suffix(12).reduce(0) { $0 + $1.revenue }
        return t12 < threshold
    }

    /// Rate charged on this company's sales today.
    public static func rate(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        if isExempt(co, w) { return 0 }
        return w.country(co).vat.rate(for: bd.vatCategory)
    }
}
