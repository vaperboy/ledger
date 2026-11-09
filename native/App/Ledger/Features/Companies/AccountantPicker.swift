import SwiftUI
import GameCore
import Countries
import Simulation

// The accountant choice: one list of rows (name, fee, rating, current) used as a step in the new-company and holding flows. Rows take the colours of the app they sit in.

/// The accountants of a country as choice rows. `chosenID` is the one shown as selected.
struct AccountantChoiceList: View {
    var offers: [AccountantOffer]
    var currency: Currency
    var chosenID: Int?
    var onPick: (AccountantOffer) -> Void

    var body: some View {
        // The fee is the figure compared down the list, so it sits on the right; rating and error rate are the line under the name.
        VStack(spacing: Theme.Space.s) {
            ForEach(offers) { (o: AccountantOffer) in
                ShopChoiceRow(title: o.name, subtitle: subtitle(o), trailing: currency.tidyShort(o.monthlyFee) + "/mo", selected: o.id == chosenID,
                              identifier: "accountant-\(o.id)") { onPick(o) }
            }
        }
    }

    private func subtitle(_ o: AccountantOffer) -> String {
        let wrong: String = String(format: "%.0f", o.errorRate * 100)
        return "\u{2605} " + String(format: "%.1f", o.rating) + " \u{00B7} books wrong " + wrong + "% of the time"
    }
}

/// The accountant step of a flow that creates a company: the country's accountants, the standard one pre-selected until another is tapped, and
/// below them the offices other players run. `accountantID` stays nil while the standard one is wanted, so the engine's own default applies.
struct AccountantStep: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var countryCode: String
    var currency: Currency
    @Binding var accountantID: Int?
    var service: AccountantOfficeService = MockAccountantOfficeService()
    /// The player office chosen, if any; the engine accountant it is billed as is what `accountantID` holds.
    @State private var officeID: String?

    var body: some View {
        if let e = store.engine {
            let offers: [AccountantOffer] = e.accountantOffers(countryCode: countryCode)
            let chosen: Int? = officeID == nil ? (accountantID ?? offers.first { (o: AccountantOffer) -> Bool in o.isDefault }?.id) : nil
            let offices: [AccountantOffice] = service.offices(countryCode: countryCode, offers: offers)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Accountant").capsLabel()
                Text("Your company keeps its books with one. The fee is paid each month and you can change it later in Atlas.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                AccountantChoiceList(offers: offers, currency: currency, chosenID: chosen) { (o: AccountantOffer) -> Void in
                    officeID = nil
                    accountantID = o.isDefault ? nil : o.id
                }
                if !offices.isEmpty {
                    Text("Offices run by other players").capsLabel().padding(.top, Theme.Space.s)
                    VStack(spacing: Theme.Space.s) {
                        ForEach(offices) { (office: AccountantOffice) in
                            if let o = offers.first(where: { (x: AccountantOffer) -> Bool in x.id == office.offerID }) {
                                ShopChoiceRow(title: office.officeName, subtitle: "Run by \(office.ownerName), \(office.city) \u{00B7} \u{2605} " + String(format: "%.1f", o.rating),
                                              trailing: currency.tidyShort(o.monthlyFee) + "/mo", selected: officeID == office.id,
                                              identifier: "accountant-" + office.id) {
                                    officeID = office.id
                                    accountantID = o.isDefault ? nil : o.id
                                }
                            }
                        }
                    }
                }
            }
            .task(id: countryCode) { store.act { $0.prepareAccountants(countryCode: countryCode) } }
        }
    }
}
