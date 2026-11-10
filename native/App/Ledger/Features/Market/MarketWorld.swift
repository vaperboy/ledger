import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

struct MarketWorldPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void

    var body: some View {
        if let e = store.engine {
            let countries: [MarketUI.CountryLine] = store.memo("mk.countries") { MarketData.countries($0) } ?? []
            let mine: [MarketUI.CountryLine] = countries.filter { (c: MarketUI.CountryLine) -> Bool in c.yourCompanies > 0 || c.isHome }
            let rest: [MarketUI.CountryLine] = countries.filter { (c: MarketUI.CountryLine) -> Bool in c.yourCompanies == 0 && !c.isHome }
            let regions: [String] = Array(Set(rest.map { (c: MarketUI.CountryLine) -> String in c.region })).sorted()
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                hero(e, mine)
                WorldPricesCard()
                rankings(e)
                MarketLabel(title: "Where you are")
                countryList(mine)
                ForEach(regions, id: \.self) { (r: String) in
                    MarketLabel(title: r)
                    countryList(rest.filter { (c: MarketUI.CountryLine) -> Bool in c.region == r })
                }
            }
        }
    }

    private func hero(_ e: GameEngine, _ mine: [MarketUI.CountryLine]) -> some View {
        let sites: Int = mine.reduce(0) { (a: Int, c: MarketUI.CountryLine) -> Int in a + c.yourCompanies }
        let abroad: Int = mine.filter { (c: MarketUI.CountryLine) -> Bool in !c.isHome && c.yourCompanies > 0 }.count
        let value: String = abroad == 0 ? "Home only" : (abroad + 1).countText("country", plural: "countries")
        let context: String = sites == 0 ? "" : "\(sites.countText("company", plural: "companies")) \u{00B7} home \(e.homeCountry.name)"
        return MarketHero(label: "Where you are", value: value, context: context, identifier: "market-world-hero")
    }

    private func rankings(_ e: GameEngine) -> some View {
        let st: RichList.Standing? = store.memo("mk.rich") { (g: GameEngine) -> RichList.Standing in g.richListStanding }
        let rich: String = st?.rank.map { (r: Int) -> String in "#\(r)" } ?? "Not placed"
        return VStack(spacing: 0) {
            MarketLabel(title: "Rankings")
            LedgerRow(leading: .glyph(Glyph.richList), leadingTint: P.inkSoft, title: "Rankings",
                      value: rich, valueNote: "rich list", identifier: "world-rankings",
                      action: { open(.rankings) })
            Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m)
            LedgerRow(leading: .glyph(Glyph.reports), leadingTint: P.inkSoft, title: "Records", identifier: "world-records", action: { open(.records) })
            Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m)
            LedgerRow(leading: .glyph(Glyph.people), leadingTint: P.inkSoft, title: "People and reputation", identifier: "world-around", action: { open(.aroundYou) })
        }
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
                EmptyState(glyph: Glyph.world, title: "Unknown country").appScreen(title: "Country", subtitle: "Market \u{00B7} World")
            }
        }
    }

    private func hero(_ c: Country, _ here: [Company]) -> some View {
        let pop: String = c.populationMillions >= 10 ? String(format: "%.0f million", c.populationMillions) : String(format: "%.1f million", c.populationMillions)
        return MarketHero(label: "Your companies here", value: here.isEmpty ? "None yet" : "\(here.count)",
                          context: "\(pop) people \u{00B7} \(c.currencyCode)", identifier: "country-hero")
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
                              subtitle: "\(e.tradeName(co)) \u{00B7} \(e.cityName(co))", lineLimit: 1, identifier: "country-company-\(co.id)",
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
                              valueNote: "sales a year", lineLimit: 1, identifier: "country-group-\(g.id)", action: { next = .group(g.id) })
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
            PrimaryAction(title: "Open a company here", identifier: "country-open-company") { store.push(.newCompany) }
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
                .accessibilityIdentifier("country-open-company")
            } else {
                PrimaryAction(title: "Open a company here", blockedReason: can.isEmpty ? "No company of yours can start here yet" : nil,
                              identifier: "country-open-company") { if let co = can.first { abroadFor = co.id } }
            }
        }
    }
}

struct MarketRankingsPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @State private var part: Part = .rich

    enum Part: String, CaseIterable, Hashable { case rich = "Rich list", companies = "Companies", awards = "Awards" }

    var body: some View {
        Group {
            if let e = store.engine {
                let st: RichList.Standing = e.richListStanding
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    hero(e, st)
                    SegmentedPill(items: Part.allCases, title: { (p: Part) -> String in p.rawValue }, selection: $part,
                                  identifier: { (p: Part) -> String in "rankings-\(p.rawValue)" })
                    switch part {
                    case .rich: richList(st)
                    case .companies: CompanyRankingSection()
                    case .awards: awards(e)
                    }
                }
                .appScreen(title: "Rankings", subtitle: "Market \u{00B7} World")
            }
        }
    }

    private func movement(_ st: RichList.Standing) -> String {
        guard let r = st.rank, let p = st.previous, p != r else { return "" }
        return p > r ? "up \(p - r) since last month" : "down \(r - p) since last month"
    }

    private func hero(_ e: GameEngine, _ st: RichList.Standing) -> some View {
        let value: String = st.rank.map { (r: Int) -> String in "#\(r.formatted())" } ?? "Not placed"
        var parts: [String] = ["Net worth " + store.short(max(0, st.netWorth))]
        let move: String = movement(st)
        if !move.isEmpty { parts.append(move) }
        if let b = st.best { parts.append("best #\(b)") }
        let up: Bool = (st.previous ?? 0) > (st.rank ?? 0)
        return MarketHero(label: "Rich list of \(e.homeCountry.name)", value: value, context: parts.joined(separator: " \u{00B7} "),
                          contextTint: move.isEmpty ? nil : (up ? P.gain : P.loss), identifier: "rankings-hero")
    }

    @ViewBuilder private func richList(_ st: RichList.Standing) -> some View {
        let top: [RichList.Person] = st.top.sorted { (a: RichList.Person, b: RichList.Person) -> Bool in a.rank < b.rank }
        let shown: Set<Int> = Set(top.map { (p: RichList.Person) -> Int in p.rank })
        let near: [RichList.Person] = st.around.filter { (p: RichList.Person) -> Bool in !shown.contains(p.rank) }
        VStack(spacing: 0) {
            ForEach(Array(top.enumerated()), id: \.element.id) { (pair: (offset: Int, element: RichList.Person)) in
                if pair.offset > 0 { Hairline().padding(.leading, 44 + 32 + Theme.Space.m * 2) }
                personRow(pair.element)
            }
        }
        if !near.isEmpty {
            MarketLabel(title: (st.rank ?? 101) <= 100 ? "Around you" : "The way in")
            VStack(spacing: 0) {
                ForEach(Array(near.enumerated()), id: \.element.id) { (pair: (offset: Int, element: RichList.Person)) in
                    if pair.offset > 0 { Hairline().padding(.leading, 44 + 32 + Theme.Space.m * 2) }
                    personRow(pair.element)
                }
            }
        }
        if let r = st.rank, r > 100 {
            Text("Number 100 has \(store.short(st.hundredth)): \(store.short(max(0, st.hundredth - st.netWorth))) to go.").textStyle(.caption)
        } else if st.rank == nil {
            Text("Not placed: net worth below zero").textStyle(.caption)
        }
    }

    private func personRow(_ p: RichList.Person) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text(p.isYou && p.rank == 0 ? "\u{00B7}" : "\(p.rank)").textStyle(.figure, tint: p.isYou ? P.accent : P.inkSoft).frame(width: 44, alignment: .leading)
            PlayerAvatar(name: p.name, isYou: p.isYou, size: 32)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(p.name).textStyle(.headline, tint: p.isYou ? P.accent : nil).lineLimit(1)
                Text(p.isYou ? "You" : p.source.capitalized).textStyle(.caption).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Text(store.short(max(0, p.wealth))).textStyle(.headline, numeric: true)
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(p.isYou ? "rankings-you" : "rankings-person-\(p.rank)")
    }

    @ViewBuilder private func awards(_ e: GameEngine) -> some View {
        let years = Array(e.awardYears.reversed())
        MarketLabel(title: "Business awards", note: "\(Awards.wonCount(e.state)) won")
        if years.isEmpty {
            Text("First awards at the end of the year").textStyle(.caption)
        } else {
            ForEach(Array(years.prefix(4)), id: \.year) { y in
                MarketLabel(title: "\(y.year)")
                VStack(spacing: 0) {
                    ForEach(Array(y.results.enumerated()), id: \.offset) { i, r in
                        if i > 0 { Hairline().padding(.leading, 36 + Theme.Space.m) }
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            ThumbnailView(kind: .trophy, key: ArtLibrary.awardKey(r.kind), size: 36, shape: .square, glyph: Glyph.achievements)
                                .opacity(r.won ? 1 : 0.4)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(Awards.name(r.kind)).textStyle(.headline, tint: r.won ? P.accent : nil)
                                Text(r.won ? "\(r.company): \(r.why)" : "Won by \(r.other). You were in the running.").textStyle(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Theme.Space.s)
                            Text(r.won ? "Won" : "").textStyle(.caption, tint: P.gain)
                        }
                        .padding(.vertical, Theme.Space.m)
                    }
                }
            }
        }
    }
}
