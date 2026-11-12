import Foundation
import GameCore
import Countries
import Finance

public enum Vat {
    // Outside VAT until twelve months of sales reach the country's threshold; the books switch over by themselves.
    public static func isExempt(_ co: Company, _ w: World) -> Bool {
        let threshold = w.country(co).vatThreshold
        guard threshold > 0 else { return false }
        return co.monthlyHistory.suffix(12).reduce(0) { $0 + $1.revenue } < threshold
    }

    public static func rate(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        if isExempt(co, w) { return 0 }
        return w.country(co).vat.rate(for: bd.vatCategory)
    }

    static let exemptSupplyFamilies: Set<String> = ["fin"]

    public static func input(_ s: inout GameState, companyIndex i: Int, net: Double, data: GameData) {
        guard net > 0 else { return }
        let w = World(state: s, data: data)
        let co = s.companies[i], country = w.country(co)
        guard !country.usesSalesTax, country.vat.standard > 0 else { return }
        let vat = jsRound(net * country.vat.standard)
        guard vat > 0 else { return }
        Ledger.moveRaw(&s, .company(co.id), -vat)
        let exemptSupplier = data.catalog[co.type].map { exemptSupplyFamilies.contains($0.family) } ?? false
        if exemptSupplier || isExempt(s.companies[i], w) {
            var b = s.companies[i].books; b.add("oth", vat); s.companies[i].books = b
        } else {
            s.companies[i].vatBalance -= vat
        }
    }
}
