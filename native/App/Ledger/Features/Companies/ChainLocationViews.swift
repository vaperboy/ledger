import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The chain's head office: the brand and what it provides to every location, apart from any one store.
struct ChainHeadOffice: View {
    var engine: GameEngine
    var chainID: Int

    var body: some View {
        if let h = engine.chainHeadOffice(chainID: chainID) {
            MoreBlock(h.title) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    RateBar(label: "Value of the name", fraction: h.brandScore / 100)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        line("CEO", h.ceoName ?? "None yet")
                        line("Chain manager", h.chainManagerName ?? "None yet")
                        line("Locations", "\(h.locations) in \(h.cities) \(h.cities == 1 ? "city" : "cities")")
                    }
                    ForEach(h.services) { sv in
                        HStack(alignment: .top, spacing: Theme.Space.s) {
                            Image(systemName: sv.active ? "checkmark.circle.fill" : "circle").foregroundStyle(sv.active ? Theme.ink : Theme.inkFaint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sv.title).textStyle(.body, tint: Theme.ink, weight: .medium)
                                Text(sv.detail).textStyle(.caption, tint: Theme.inkFaint)
                            }
                        }
                    }
                }
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).textStyle(.caption, tint: Theme.inkFaint)
            Spacer()
            Text(value).textStyle(.caption, tint: Theme.ink)
        }
    }
}

/// The one way to grow a chain: pick a city, see the quote and the name, add the location.
struct ChainAddLocation: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var summary: Chains.Summary
    var currency: Currency
    @State private var newCity = ""
    @State private var pending: PendingAction?

    var body: some View {
        let cities = engine.state.company(summary.stores.first?.id ?? 0).flatMap { engine.data.countries[$0.countryCode] }?.cities ?? []
        let cityID = newCity.isEmpty ? (cities.first?.id ?? "") : newCity
        let quote = engine.locationQuote(chainID: summary.id, cityID: cityID)
        MoreBlock("Add a location") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Picker("City", selection: Binding(get: { cityID }, set: { newCity = $0 })) {
                    ForEach(cities) { c in
                        let n = summary.stores.filter { $0.cityName == c.name }.count
                        Text(c.name + (n > 0 ? " \u{00B7} \(n) \(n == 1 ? "location" : "locations")" : "")).tag(c.id)
                    }
                }.pickerStyle(.menu)
                if let q = quote {
                    Text(q.name).textStyle(.body, tint: Theme.ink, weight: .medium)
                    FigureStrip(items: [
                        .init(label: "Fit-out and equipment", value: currency.tidyShort(q.fitOut)),
                        .init(label: "Rent a month", value: currency.tidyShort(q.monthlyRent)),
                        .init(label: "Deposit", value: currency.tidyShort(q.deposit)),
                        .init(label: "Licences", value: currency.tidyShort(q.licences)),
                        .init(label: "Total now", value: currency.tidyShort(q.total)),
                        .init(label: "You have available", value: store.money(Payments.liquid(engine.state))),
                    ], columns: 2)
                    Text(q.managerFromChain ? "The chain team appoints its manager." : "Without a chain manager or CEO you appoint its manager yourself.")
                        .textStyle(.caption, tint: Theme.inkFaint)
                    QuietButton(title: "Add \(q.name)", fullWidth: true) {
                        pending = PendingAction(title: "Add \(q.name)?",
                                                message: "About \(currency.tidyShort(q.total)) now for the place, equipment, licences and first staff. It takes a few weeks to set up and earns nothing until it opens.",
                                                button: "Add the location", amount: q.total, currency: currency) { open(q) }
                    }
                } else {
                    Text("A location is not possible in that city.").textStyle(.caption, tint: Theme.inkFaint)
                }
            }
        }
        .confirmAction($pending)
    }

    private func open(_ q: ChainLocations.Quote) {
        switch store.act({ $0.openLocation(chainID: q.chainID, cityID: q.cityID) }) {
        case .success?: Haptics.success(); store.show("\(q.name) is being set up.", tone: "good")
        case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You don't have enough for a new location.", tone: "warn")
        default: Haptics.warning(); store.show("A new location is not possible here.", tone: "warn")
        }
    }
}
