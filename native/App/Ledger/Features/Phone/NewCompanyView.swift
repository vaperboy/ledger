import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// Choose a trade, see the whole start-up cost, then decide.
struct NewCompanyView: View {
    @EnvironmentObject var store: GameStore
    @State private var search = ""

    var body: some View {
        if let e = store.engine {
            let all = e.data.catalog.all
            let country = e.homeCountry
            let list = all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search) }
            ScrollView {
                LazyVStack(spacing: Theme.Space.s) {
                    ForEach(list) { t in
                        let ban = CompanySetup.banReason(t.id, country: country)
                        NavigationLink {
                            TradeDetailView(tradeID: t.id)
                        } label: {
                            Card(padding: Theme.Space.m) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).font(.system(.headline, design: .serif)).foregroundStyle(ban == nil ? Theme.ivory : Theme.ivoryFaint)
                                        Text(ban ?? t.blurb).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(2).multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.ivoryFaint)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Choose a trade")
            .searchable(text: $search)
        }
    }
}

struct TradeDetailView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var tradeID: String
    @State private var cityID = ""
    @State private var limited = false
    @State private var size = 1.0
    @State private var sizeSet = false

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[tradeID] {
            let country = e.homeCountry
            let cur = e.homeCurrency
            let form: LegalForm = (limited || t.needsLimitedCompany) ? .limited : .soleTrader
            let city = cityID.isEmpty ? e.state.player.cityID : cityID
            let est = CompanySetup.estimate(tradeID: t.id, cityID: city, form: form, size: size, state: e.state, data: e.data)
            let ban = CompanySetup.banReason(t.id, country: country)
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(t.name).font(.heading)
                            Text(t.blurb).font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                            if let ban { Text(ban).font(.caption).foregroundStyle(Theme.loss) }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            SectionLabel("Where and how")
                            Picker("City", selection: Binding(get: { city }, set: { cityID = $0 })) { ForEach(country.cities) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                            if t.needsLimitedCompany { Text("This trade needs a limited company.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                            else {
                                Picker("Legal form", selection: $limited) { Text("Sole trader").tag(false); Text("Limited company").tag(true) }.pickerStyle(.segmented)
                                Text(limited ? "Your personal assets are protected; profits are taxed in the company and again when paid out." : "Simple and cheap. You are personally liable for debts; profit is taxed as your income.")
                                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            }
                            if t.maxSize > t.minSize {
                                Stepper(value: $size, in: t.minSize...t.maxSize, step: 0.5) { Text("Size \(size, specifier: "%.1f")").font(.bodyText) }
                            }
                        }
                    }
                    if let est {
                        Card {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                SectionLabel("Start-up cost")
                                line("Permits and documents", est.documents, cur)
                                line("Equipment", est.equipment, cur)
                                line("Vehicles", est.vehicles, cur)
                                line("Premises (deposit and first rent)", est.premises, cur)
                                line("Opening stock", est.stock, cur)
                                line("First payroll", est.firstPayroll, cur)
                                line("Registration", est.registration, cur)
                                line("Working buffer", est.buffer, cur)
                                if est.abroad > 0 { line("Abroad", est.abroad, cur) }
                                Divider().overlay(Theme.hairline)
                                HStack { Text("Total").font(.bodyText.weight(.semibold)); Spacer(); Text(cur.format(est.total)).font(.figure(18)) }
                                Text("You have \(cur.format(Payments.liquid(e.state))) available. Share capital for a limited company: \(cur.format(est.shareCapital)).").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            }
                        }
                        Button("Start this business") {
                            let fund = min(est.total * 1.15, Payments.liquid(e.state))
                            let r = store.act { $0.startCompany(tradeID: t.id, cityID: city, form: form, size: size, fundWith: fund) }
                            switch r {
                            case .success?: Haptics.success(); store.show("Started.", tone: "good"); store.tab = .companies; dismiss()
                            case .failure(.banned(let why))?: Haptics.failure(); store.show(why, tone: "bad")
                            case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You can't afford the registration costs yet.", tone: "warn")
                            default: Haptics.warning(); store.show("Not possible here.", tone: "warn")
                            }
                        }
                        .buttonStyle(GoldButtonStyle()).disabled(ban != nil)
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle(t.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if !sizeSet { size = CompanySetup.recommendedSize(t, city: country.cities.first { $0.id == city } ?? country.cities[0]); sizeSet = true } }
        }
    }

    private func line(_ label: String, _ v: Double, _ cur: Currency) -> some View {
        Group { if v > 0 { ValueRow(label: label, value: cur.format(v)) } }
    }
}
