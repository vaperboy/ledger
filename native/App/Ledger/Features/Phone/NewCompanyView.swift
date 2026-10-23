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
                Card {
                    LazyVStack(spacing: Theme.Space.m) {
                        if search.isEmpty {
                            NavigationLink { NewHoldingView() } label: {
                                ListRow(symbol: TradeSymbol.of(family: "hold"), tint: Theme.gold, title: "Holding company", subtitle: "Owns your other companies; dividends into it are taxed far lower", chevron: true).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            NavigationLink { FranchisesView() } label: {
                                ListRow(symbol: "storefront", tint: Theme.gold, title: "Join a franchise", subtitle: "A known brand, their rules and a fee", chevron: true).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if e.state.companies.contains(where: { $0.status == .open && $0.type != "hold" }) {
                                NavigationLink { ExpandAbroadView() } label: {
                                    ListRow(symbol: "globe", tint: Theme.gold, title: "Expand abroad", subtitle: "A subsidiary of one of your companies in another country", chevron: true).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            NavigationLink { ClubMarketView() } label: {
                                ListRow(symbol: TradeSymbol.of(family: "club"), tint: Theme.gold, title: "Football club", subtitle: "Buy a club in a top league, or found one", chevron: true).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        ForEach(list) { t in
                            let ban = CompanySetup.banReason(t.id, country: country) ?? (SpecialFamilies.isStartable(t) ? nil : "Coming in a later update")
                            NavigationLink {
                                TradeDetailView(tradeID: t.id)
                            } label: {
                                ListRow(symbol: TradeSymbol.of(family: t.family), tint: ban == nil ? Theme.gold : Theme.ivoryFaint,
                                        title: t.name, subtitle: ban ?? t.blurb, chevron: true)
                                    .opacity(ban == nil ? 1 : 0.6)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
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
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[tradeID] {
            let country = e.homeCountry
            let cur = e.homeCurrency
            let form: LegalForm = (limited || t.needsLimitedCompany) ? .limited : .soleTrader
            let city = cityID.isEmpty ? e.state.player.cityID : cityID
            let est = CompanySetup.estimate(tradeID: t.id, cityID: city, form: form, size: size, state: e.state, data: e.data)
            let ban = CompanySetup.banReason(t.id, country: country) ?? (SpecialFamilies.isStartable(t) ? nil : "This kind of business is coming in a later update.")
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            HStack(spacing: Theme.Space.m) {
                                IconBadge(symbol: TradeSymbol.of(family: t.family), tint: Theme.gold, size: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.heading)
                                    Text(t.category).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                }
                            }
                            Text(t.blurb).font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                            if let est { Text(cur.display(est.total)).font(.hero(34)); Text("to start, everything included").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                            if let ban { Chip(text: ban, tint: Theme.loss, symbol: "nosign") }
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
                            VStack(alignment: .leading, spacing: Theme.Space.m) {
                                SectionLabel("Start-up cost")
                                line("doc.text.fill", "Permits and documents", est.documents, cur)
                                line("wrench.and.screwdriver.fill", "Equipment", est.equipment, cur)
                                line("car.fill", "Vehicles (down payment)", est.vehicles, cur)
                                line("building.fill", "Premises (deposit and first rent)", est.premises, cur)
                                line("shippingbox.fill", "Opening stock", est.stock, cur)
                                line("person.2.fill", "First payroll", est.firstPayroll, cur)
                                line("signature", "Registration", est.registration, cur)
                                line("house.fill", "First property (deposit and costs)", est.property, cur)
                                line("shield.fill", "Working buffer", est.buffer, cur)
                                if est.abroad > 0 { line("globe", "Abroad", est.abroad, cur) }
                                Hairline()
                                HStack { SectionLabel("Total"); Spacer(); Text(cur.display(est.total)).font(.figure(18)) }
                                Text("You have \(cur.display(Payments.liquid(e.state))) available. Share capital for a limited company: \(cur.display(est.shareCapital)).").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            }
                        }
                        let liquid = Payments.liquid(e.state)
                        let afford = liquid >= est.total
                        if !afford { Text("You are \(cur.tidyShort(est.total - liquid)) short of the full start-up cost. You can still register, but opening will wait for money.").font(.caption).foregroundStyle(Theme.caution) }
                        Text("Other ways in: a franchise (known brand, their rules and a fee) or buying a rival that is already trading, from the rival's page under Market.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        Button("Start this business") {
                            pending = PendingAction(title: "Start \(t.name) in \(country.cities.first { $0.id == city }?.name ?? "town")?",
                                                    message: "About \(cur.display(est.total)) to start, of which \(cur.display(min(est.total * 1.15, liquid))) goes into the company from your cash now. You keep \(cur.display(max(0, liquid - est.total * 1.15))). \(form == .limited ? "A limited company protects your personal assets." : "As a sole trader you are personally liable for its debts.") Risk: it earns nothing until it is set up and open; most new businesses need months to break even.",
                                                    button: "Start it") {
                                let fund = min(est.total * 1.15, Payments.liquid(e.state))
                                let r = store.act { $0.startCompany(tradeID: t.id, cityID: city, form: form, size: size, fundWith: fund) }
                                switch r {
                                case .success(let id)?: Haptics.success(); store.show("Started. Set it up, then open for business.", tone: "good"); store.openCompany(id)
                                case .failure(.banned(let why))?: Haptics.failure(); store.show(why, tone: "bad")
                                case .failure(.notYetAvailable)?: store.show("Coming in a later update.", tone: "warn")
                                case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You can't afford the registration costs yet.", tone: "warn")
                                default: Haptics.warning(); store.show("Not possible here.", tone: "warn")
                                }
                            }
                        }
                        .buttonStyle(GoldButtonStyle()).disabled(ban != nil)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle(t.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmAction($pending)
            .onAppear { if !sizeSet { size = CompanySetup.recommendedSize(t, city: country.cities.first { $0.id == city } ?? country.cities[0]); sizeSet = true } }
        }
    }

    private func line(_ symbol: String, _ label: String, _ v: Double, _ cur: Currency) -> some View {
        Group { if v > 0 { ListRow(symbol: symbol, tint: Theme.ivoryMuted, title: label, trailing: cur.display(v)) } }
    }
}
