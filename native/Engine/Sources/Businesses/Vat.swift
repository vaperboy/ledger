import Foundation
import GameCore
import Countries
import Finance

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

    /// Trade families whose income (interest, premiums, fees on money) is an exempt supply.
    static let exemptSupplyFamilies: Set<String> = ["fin", "hold"]

    /// Input VAT on a purchase of `net` (repairs, lease instalments, fuel, premises upkeep): standard-rated supplies. A VAT-registered company
    /// reclaims it through its VAT account; one below the threshold cannot, and it becomes a cost. Insurance premiums and interest are exempt
    /// supplies and never come here. Sales-tax countries have no reclaimable input tax. The country data has no passenger-car restriction, so
    /// vehicles are treated as commercial (100%). The net amount itself is posted by the caller.
    public static func input(_ s: inout GameState, companyIndex i: Int, net: Double, data: GameData) {
        guard net > 0 else { return }
        let w = World(state: s, data: data)
        let co = s.companies[i], country = w.country(co)
        guard !country.usesSalesTax, country.vat.standard > 0 else { return }
        let vat = jsRound(net * country.vat.standard)
        guard vat > 0 else { return }
        Ledger.moveRaw(&s, .company(co.id), -vat)
        // A company whose supplies are all exempt (banking, insurance, funds, a holding living on interest) charges no VAT and so cannot
        // reclaim any: the input VAT is a cost for it however large its turnover.
        let exemptSupplier = data.catalog[co.type].map { exemptSupplyFamilies.contains($0.family) } ?? false
        if exemptSupplier || isExempt(s.companies[i], w) {
            var b = s.companies[i].books; b.add("oth", vat); s.companies[i].books = b
        } else {
            s.companies[i].vatBalance -= vat
        }
    }
}
