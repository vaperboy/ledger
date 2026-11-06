import SwiftUI
import GameCore
import Countries
import Simulation

// The accountant choice: one list of rows (name, fee, rating, current) used in Atlas for a company that exists, and as a step in the
// new-company, conversion and holding flows for one that does not yet. Rows take the colours of the app they sit in.

/// The accountants of a country as choice rows. `chosenID` is the one shown as selected.
struct AccountantChoiceList: View {
    var offers: [AccountantOffer]
    var currency: Currency
    var chosenID: Int?
    var onPick: (AccountantOffer) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(offers) { (o: AccountantOffer) in
                ShopChoiceRow(title: o.name, subtitle: subtitle(o), trailing: "\u{2605} " + String(format: "%.1f", o.rating), selected: o.id == chosenID,
                              identifier: "accountant-\(o.id)") { onPick(o) }
            }
        }
    }

    private func subtitle(_ o: AccountantOffer) -> String {
        let wrong: String = String(format: "%.0f", o.errorRate * 100)
        return currency.tidyShort(o.monthlyFee) + " a month \u{00B7} books wrong " + wrong + "% of the time"
    }
}

/// The accountant step of a flow that creates a company: the country's accountants, the standard one pre-selected until another is tapped.
/// `accountantID` stays nil while the standard one is wanted, so the engine's own default applies.
struct AccountantStep: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var countryCode: String
    var currency: Currency
    @Binding var accountantID: Int?

    var body: some View {
        if let e = store.engine {
            let offers: [AccountantOffer] = e.accountantOffers(countryCode: countryCode)
            let chosen: Int? = accountantID ?? offers.first { (o: AccountantOffer) -> Bool in o.isDefault }?.id
            VStack(alignment: .leading, spacing: 8) {
                Text("Accountant").capsLabel()
                Text("A limited company keeps its books with one. The fee is paid each month and you can change it later in Atlas.")
                    .font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
                AccountantChoiceList(offers: offers, currency: currency, chosenID: chosen) { (o: AccountantOffer) -> Void in
                    accountantID = o.isDefault ? nil : o.id
                }
            }
            .task(id: countryCode) { store.act { $0.prepareAccountants(countryCode: countryCode) } }
        }
    }
}
