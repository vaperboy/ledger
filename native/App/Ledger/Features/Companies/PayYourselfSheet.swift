import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// The tax rule for dividends in the player's country, in words, for the places that offer to pay one.
enum PayRules {
    /// "dividend tax of 37.84% withheld when it is paid, after any tax-free shield".
    static func dividendTaxText(_ engine: GameEngine) -> String {
        let c: Country = engine.context.homeCountry(engine.state)
        return "dividend tax of \(Currency.percent(c.dividendTax, decimals: 2)) at year end, after any tax-free shield"
    }
}

/// Salary against dividend against keeping the money in the company, for one amount: what reaches you and the tax each way adds.
struct PayYourselfSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var amount = 0.0

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let cur: Currency = e.currency(for: co)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Compared for one amount: a year of salary at this size, or one dividend of it. Tax is taken when the money is paid.")
                    .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                AmountField(title: "Amount to take out", currency: cur, amount: $amount)
                if let r = e.ownerPayOptions(companyID: companyID, amount: amount) {
                    ForEach(r.options) { (o: OwnerPayOption) in card(o, r, cur, co) }
                    Text("Company profit tax here is \(Currency.percent(r.corporateRate, decimals: 1)). Dividends carry \(PayRules.dividendTaxText(e)); a salary is taxed as income instead.")
                        .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(amount > 0 ? "Nothing can be paid out of this company right now." : "Enter an amount to compare.").popupText(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                if amount == 0 { amount = max(0, e.maximumDividend(companyID: companyID) / 2).rounded(.down) }
            }
        }
    }

    private func card(_ o: OwnerPayOption, _ r: OwnerPayComparison, _ cur: Currency, _ co: Company) -> some View {
        let toHolding: Bool = o.route == .dividend && co.holdingID != 0
        let keep: Double = o.companyCostAfterTax > 0 ? o.netInHand / o.companyCostAfterTax : 0
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(o.title).popupText(.rowValue)
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(cur.tidyShort(o.netInHand)).popupText(.figure).lineLimit(1).minimumScaleFactor(0.6)
                    Text("in your hand").popupText(.caption)
                }
            }
            if o.route != .retain {
                line("Leaves the company", cur.tidyShort(o.cashFromCompany))
                if o.employerContributions > 0 { line("Employer contributions", cur.tidyShort(o.employerContributions)) }
                if o.companyTaxChange != 0 { line("Company profit tax", (o.companyTaxChange < 0 ? "saves " : "adds ") + cur.tidyShort(abs(o.companyTaxChange))) }
                line(o.route == .salary ? "Your income tax" : "Your dividend tax", cur.tidyShort(o.personalTax))
                line("Tax added in total", cur.tidyShort(o.totalTax))
                if keep > 0 { line("You keep, per 1 it costs the company", Currency.percent(keep, decimals: 0)) }
            }
            Text(toHolding ? "This company belongs to a holding, so the dividend goes there and nothing is taxed on you until the holding pays you." : o.explanation)
                .popupText(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset))
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).popupText(.rowLabel)
            Spacer(minLength: Theme.Space.s)
            Text(value).popupText(.body).lineLimit(1)
        }
    }
}
