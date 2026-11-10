import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct WorldCountriesPage: View {
    @EnvironmentObject var store: GameStore
    @Binding var tab: WorldTab
    var open: (MarketRoute) -> Void

    var body: some View {
        if let e = store.engine {
            let countries: [MarketUI.CountryLine] = store.memo("mk.countries") { MarketData.countries($0) } ?? []
            let mine: [MarketUI.CountryLine] = countries.filter { (c: MarketUI.CountryLine) -> Bool in c.yourCompanies > 0 || c.isHome }
            let rest: [MarketUI.CountryLine] = countries.filter { (c: MarketUI.CountryLine) -> Bool in c.yourCompanies == 0 && !c.isHome }
            let regions: [String] = Array(Set(rest.map { (c: MarketUI.CountryLine) -> String in c.region })).sorted()
            CivicPage(spacing: Theme.Space.m) {
                CivicHeader(title: "World", subtitle: "Every country, its cities and where to open a company")
                WorldTabBar(tab: $tab)
                hero(e, mine)
                MarketLabel(title: "Where you are")
                countryList(mine)
                ForEach(regions, id: \.self) { (r: String) in
                    MarketLabel(title: r)
                    countryList(rest.filter { (c: MarketUI.CountryLine) -> Bool in c.region == r })
                }
            }
            .outsideScreen(.civic)
            .accessibilityIdentifier("world-countries")
        }
    }

    private func hero(_ e: GameEngine, _ mine: [MarketUI.CountryLine]) -> some View {
        let sites: Int = mine.reduce(0) { (a: Int, c: MarketUI.CountryLine) -> Int in a + c.yourCompanies }
        let abroad: Int = mine.filter { (c: MarketUI.CountryLine) -> Bool in !c.isHome && c.yourCompanies > 0 }.count
        let value: String = abroad == 0 ? "Home only" : (abroad + 1).countText("country", plural: "countries")
        let context: String = sites == 0 ? "" : "\(sites.countText("company", plural: "companies")) \u{00B7} home \(e.homeCountry.name)"
        return MarketHero(label: "Where you are", value: value, context: context, identifier: "world-countries-hero")
    }

    private func countryList(_ list: [MarketUI.CountryLine]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.CountryLine)) in
                if pair.offset > 0 { Hairline() }
                countryRow(pair.element)
            }
        }
    }

    private func countryRow(_ c: MarketUI.CountryLine) -> some View {
        let pop: String = c.population >= 10 ? String(format: "%.0f m", c.population) : String(format: "%.1f m", c.population)
        let tax: String = "tax " + Currency.percent(c.corporateTax, decimals: 0)
        let value: String = c.yourCompanies > 0 ? c.yourCompanies.countText("company", plural: "companies") : (c.isHome ? "Home" : "")
        let note: String = MarketWords.level(c.demand) + " demand" + (c.rivalGroups > 0 ? " \u{00B7} \(c.rivalGroups.countText("group"))" : "")
        return LedgerRow(title: c.flag + "  " + c.name + (c.isHome && c.yourCompanies > 0 ? " \u{00B7} home" : ""),
                         subtitle: "\(pop) people \u{00B7} \(c.currency) \u{00B7} \(tax)", value: value, valueNote: note, lineLimit: 1,
                         identifier: "world-country-\(c.id)", action: { open(.country(c.id)) })
    }
}

struct WorldPeoplePage: View {
    @Binding var tab: WorldTab

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CivicHeader(title: "World", subtitle: "Who you know and how you are seen")
                WorldTabBar(tab: $tab)
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, 6)
            WorldAroundView()
        }
        .outsideScreen(.civic)
        .accessibilityIdentifier("world-people")
    }
}

enum MarketWords {
    static func level(_ v: Double) -> String { v >= 1.15 ? "Strong" : (v >= 0.85 ? "Average" : "Weak") }
    static func cost(_ v: Double) -> String { v >= 1.15 ? "High" : (v >= 0.85 ? "Average" : "Low") }
}

struct CountryPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var countryCode: String
    @State private var abroadFor: Int?
    @State private var next: MarketRoute?

    var body: some View {
        Group {
            if let e = store.engine, let c = e.data.countries[countryCode] {
                let here: [Company] = e.state.companies.filter { (co: Company) -> Bool in co.status.isLive && co.countryCode == countryCode }
                let groups: [RivalGroups.Group] = RivalGroups.groups(e.state, country: countryCode)
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    hero(c, here)
                    figures(c)
                    yours(e, here)
                    competition(e, groups)
                    cities(e, c, here)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    openAction(e, c).padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s).background(P.ground.opacity(0.96))
                }
                .appScreen(title: c.flag + " " + c.name, subtitle: c.region)
                .navigationDestination(item: $abroadFor) { (id: Int) in AbroadOptionsView(companyID: id, country: countryCode) }
                .navigationDestination(item: $next) { (r: MarketRoute) in MarketDestination(route: r) }
            } else {
                EmptyState(glyph: Glyph.world, title: "Unknown country").appScreen(title: "Country", subtitle: "World \u{00B7} Countries")
            }
        }
    }

    private func hero(_ c: Country, _ here: [Company]) -> some View {
        let pop: String = c.populationMillions >= 10 ? String(format: "%.0f million", c.populationMillions) : String(format: "%.1f million", c.populationMillions)
        return MarketHero(label: "Your companies here", value: here.isEmpty ? "None yet" : "\(here.count)",
                          context: "\(pop) people \u{00B7} \(c.currencyCode)", identifier: "world-country-hero")
    }

    private func figures(_ c: Country) -> some View {
        FigureRow(items: [
            KeyFigures.Item(label: "Demand", value: MarketWords.level(c.marketStrength)),
            KeyFigures.Item(label: "Wages", value: MarketWords.cost(c.wageLevel)),
            KeyFigures.Item(label: "Rents", value: MarketWords.cost(c.rentLevel)),
            KeyFigures.Item(label: "Company tax", value: Currency.percent(c.corporateTax, decimals: 0)),
            KeyFigures.Item(label: "Dividend tax", value: Currency.percent(c.dividendTax, decimals: 0)),
            KeyFigures.Item(label: "Employer costs", value: Currency.percent(c.employerSocial, decimals: 0)),
        ], columns: 3, combineCells: true)
        .padding(.top, Theme.Space.l)
    }

    @ViewBuilder private func yours(_ e: GameEngine, _ here: [Company]) -> some View {
        if !here.isEmpty {
            MarketLabel(title: "Yours here")
            VStack(spacing: 0) {
                ForEach(Array(here.enumerated()), id: \.element.id) { (pair: (offset: Int, element: Company)) in
                    if pair.offset > 0 { Hairline() }
                    let co: Company = pair.element
                    LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: co.type, glyph: Glyph.home)), title: co.name,
                              subtitle: "\(e.tradeName(co)) \u{00B7} \(e.cityName(co))", lineLimit: 1, identifier: "world-country-company-\(co.id)",
                              action: co.status == .open && co.type != "hold" ? { next = .company(co.id) } : nil)
                }
            }
        }
    }

    @ViewBuilder private func competition(_ e: GameEngine, _ groups: [RivalGroups.Group]) -> some View {
        MarketLabel(title: "Rival groups here", note: groups.isEmpty ? "" : "\(groups.count)")
        if groups.isEmpty {
            Text("None").textStyle(.caption)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(groups.prefix(6).enumerated()), id: \.element.id) { (pair: (offset: Int, element: RivalGroups.Group)) in
                    if pair.offset > 0 { Hairline() }
                    let g: RivalGroups.Group = pair.element
                    LedgerRow(leading: .thumb(ThumbSpec(kind: .logo, key: "group|\(g.id)", glyph: Glyph.group, initials: g.name, shape: .square)),
                              title: g.name, subtitle: "\(g.branches) sites \u{00B7} \(g.strategyName)", value: e.homeCurrency.tidyShort(g.revenue),
                              valueNote: "sales a year", lineLimit: 1, identifier: "world-country-group-\(g.id)", action: { next = .group(g.id) })
                }
            }
        }
    }

    @ViewBuilder private func cities(_ e: GameEngine, _ c: Country, _ here: [Company]) -> some View {
        let trade: String? = here.first { (co: Company) -> Bool in co.status == .open && co.type != "hold" }?.type
            ?? MarketData.companies(e).first?.type
        let list: [MarketCity] = MarketData.cities(e, country: c.code, tradeID: trade)
        MarketLabel(title: "Cities")
        VStack(spacing: 0) {
            ForEach(Array(list.prefix(12).enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketCity)) in
                if pair.offset > 0 { Hairline() }
                let city: MarketCity = pair.element
                let rivals: String = city.rivals.map { (n: Int) -> String in " \u{00B7} " + n.countText("rival") } ?? ""
                LedgerRow(title: city.name,
                          subtitle: "\(Int(saturating: city.population.rounded()).formatted())k \u{00B7} \(MarketWords.level(city.tradeDemand ?? city.demand)) demand \u{00B7} \(MarketWords.cost(city.rentLevel)) rent" + rivals,
                          value: city.yourCompanies > 0 ? city.yourCompanies.countText("company", plural: "companies") : "", lineLimit: 1)
            }
        }
    }

    @ViewBuilder private func openAction(_ e: GameEngine, _ c: Country) -> some View {
        if c.code == e.state.homeCountryCode {
            PrimaryAction(title: "Open a company here", identifier: "world-country-open-company") { store.push(.newCompany) }
        } else {
            let can: [Company] = MarketData.expanders(e, country: c.code)
            if can.count > 1 {
                Menu {
                    ForEach(can) { (co: Company) in
                        Button("\(co.name) \u{00B7} \(e.tradeName(co))") { Haptics.tap(); abroadFor = co.id }
                    }
                } label: {
                    Text("Open a company here").frame(maxWidth: .infinity)
                }
                .menuStyle(.button)
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("world-country-open-company")
            } else {
                PrimaryAction(title: "Open a company here", blockedReason: can.isEmpty ? "No company of yours can start here yet" : nil,
                              identifier: "world-country-open-company") { if let co = can.first { abroadFor = co.id } }
            }
        }
    }
}

struct WorldAroundView: View {
    @EnvironmentObject var store: GameStore
    private func report(_ r: WorldAround.ActionResult?) {
        switch r {
        case .ok(let msg)?: Haptics.success(); store.show(msg, tone: "good")
        case .refused(let why)?: Haptics.warning(); store.show(why, tone: "warn")
        case nil: store.show("No game is open.", tone: "warn")
        }
    }

    var body: some View {
        if var e = store.engine {
            let img = e.worldImage()
            let people = e.peopleYouKnow()
            let favours = e.favours().filter { $0.status == .open }
            let infl = e.mapInfluence()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    CardSection("Seen as") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(img.label).textStyle(.headline, tint: Theme.accent, weight: .semibold)
                            Text(img.text.tidyMoney).textStyle(.body, tint: Theme.inkSoft)
                            Text("Opens: " + img.opens).textStyle(.caption, tint: Theme.inkFaint)
                            Text("Risks: " + img.risks).textStyle(.caption, tint: Theme.inkFaint)
                            CardLine()
                            ForEach(img.groups) { g in
                                HStack { Text(g.name).textStyle(.body); Spacer(); Text(g.word).textStyle(.body, tint: Theme.inkSoft) }
                            }
                        }
                    }
                    CardSection("People you know") {
                        if people.isEmpty {
                            Text("You know nobody in business yet. Open a company and people will find you.").textStyle(.body, tint: Theme.inkSoft)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(people.enumerated()), id: \.element.id) { i, c in
                                    if i > 0 { CardLine() }
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.name).textStyle(.body)
                                            Text(c.role.rawValue + " · " + c.organisation).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 8)
                                        if c.relationship >= 64 {
                                            Button("Ask a favour") {
                                                report(store.act { $0.askForFavour(contactID: c.id) })
                                            }.buttonStyle(QuietButtonStyle(tint: Theme.gold)).accessibilityLabel("Ask \(c.name) for a favour")
                                        }
                                        Text(c.word).textStyle(.caption)
                                    }.padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    if !favours.isEmpty {
                        CardSection("Favours and promises") {
                            VStack(spacing: 0) {
                                ForEach(Array(favours.enumerated()), id: \.element.id) { i, f in
                                    if i > 0 { CardLine() }
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.name).textStyle(.body)
                                            Text((f.kind == .owed ? "Owes you: " : f.kind == .promise ? "You promised: " : "You owe them: ") + f.text).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 8)
                                        if f.kind != .owe {
                                            Button(f.kind == .owed ? "Call in" : "Keep it") {
                                                let calling = f.kind == .owed
                                                report(store.act { calling ? $0.callInFavour(favourID: f.id) : $0.keepPromise(favourID: f.id) })
                                            }.buttonStyle(QuietButtonStyle(tint: Theme.gold)).accessibilityLabel((f.kind == .owed ? "Call in the favour from " : "Keep your promise to ") + f.name)
                                        }
                                    }.padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    CardSection("What you own") {
                        VStack(spacing: 0) {
                            ForEach(Array(e.mapOwnership().enumerated()), id: \.element.id) { i, n in
                                if i > 0 { CardLine() }
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.name).textStyle(.body)
                                        Text(n.trade + (n.ownership < 100 ? " · you own \(Int(saturating: n.ownership.rounded()))%" : "")).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                    }
                                    Spacer()
                                    Text(store.short(n.value)).textStyle(.body, tint: Theme.inkSoft, numeric: true)
                                }.padding(.leading, CGFloat((n.depth - 1) * 18)).padding(.vertical, 8)
                            }
                        }
                    }
                    CardSection("Where you are") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(e.mapPresence()) { p in
                                Text(p.flag + " " + p.name).textStyle(.body, weight: .semibold)
                                ForEach(p.cities.filter { $0.companies > 0 }) { c in
                                    HStack { Text(c.name).textStyle(.body); Spacer()
                                        Text("\(c.companies) · " + c.trades.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.ivoryFaint) }
                                }
                            }
                        }
                    }
                    CardSection("Circles of influence") {
                        VStack(alignment: .leading, spacing: 6) {
                            circle("Inside", infl.inner)
                            circle("Allies", infl.allies)
                            circle("Rivals and the wary", infl.others)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func circle(_ title: String, _ names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).textStyle(.body)
            Spacer()
            Text(names.isEmpty ? "None yet" : names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : ""))
                .textStyle(.caption).multilineTextAlignment(.trailing)
        }
    }
}
