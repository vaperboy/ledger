import SwiftUI
import GameCore
import Countries
import Simulation

struct AccountantChoiceList: View {
    var offers: [AccountantOffer]
    var currency: Currency
    var chosenID: Int?
    var onPick: (AccountantOffer) -> Void

    var body: some View {
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

struct AccountantStep: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var countryCode: String
    var currency: Currency
    @Binding var accountantID: Int?
    var service: AccountantOfficeService = AccountantOfficeBackend.make()
    @State private var officeID: String?
    @State private var offices: [AccountantOffice] = []

    var body: some View {
        if let e = store.engine {
            let offers: [AccountantOffer] = e.accountantOffers(countryCode: countryCode)
            let chosen: Int? = officeID == nil ? (accountantID ?? offers.first { (o: AccountantOffer) -> Bool in o.isDefault }?.id) : nil
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Accountant").capsLabel()
                Text("Your company keeps its books with one. The fee is paid each month and you can change it later in Atlas.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                AccountantChoiceList(offers: offers, currency: currency, chosenID: chosen) { (o: AccountantOffer) -> Void in
                    officeID = nil
                    accountantID = o.isDefault ? nil : o.id
                    AccountantHireIntent.clear()
                }
                if !offices.isEmpty {
                    Text("Offices run by other players").capsLabel().padding(.top, Theme.Space.s)
                    VStack(spacing: Theme.Space.s) {
                        ForEach(offices) { (office: AccountantOffice) in
                            if let o = offers.first(where: { (x: AccountantOffer) -> Bool in x.id == office.offerID }) {
                                ShopChoiceRow(title: office.officeName, subtitle: "Run by \(office.ownerName), \(office.city) \u{00B7} \u{2605} " + String(format: "%.1f", office.rating ?? o.rating),
                                              trailing: currency.tidyShort(o.monthlyFee) + "/mo", selected: officeID == office.id,
                                              identifier: "accountant-" + office.id) {
                                    officeID = office.id
                                    accountantID = o.isDefault ? nil : o.id
                                    AccountantHireIntent.choose(officeID: office.id, offerID: o.id, currency: office.currencyCode ?? currency.country.currencyCode,
                                                                knownCompanies: store.engine?.state.companies.map { (c: Company) -> Int in c.id } ?? [])
                                }
                            }
                        }
                    }
                }
            }
            .task(id: countryCode) {
                store.act { $0.prepareAccountants(countryCode: countryCode) }
                if let ready = store.engine { offices = await service.offices(countryCode: countryCode, offers: ready.accountantOffers(countryCode: countryCode)) }
            }
        }
    }
}
