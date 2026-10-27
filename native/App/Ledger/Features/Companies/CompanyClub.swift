import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

typealias ClubOffer = (id: Int, name: String, weekly: Double, years: Int)

/// A football club's own section: the season and table, the budget, sponsors, staff and transfers.
struct CompanyClub: View {
    enum Part: String, CaseIterable, Hashable { case season = "Season", budget = "Budget", people = "Staff", transfers = "Transfers", sponsors = "Sponsors", table = "Table" }
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var part: Part?
    @State private var candidates: [FootballModel.Coach] = []
    @State private var hiringKind = "coach"
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            MoreHeader(glyph: Glyph.achievements, title: "Club", blurb: "The season and table, the budget, football staff, transfers and sponsors of your club.")
            if let c = engine.clubSummary(companyID: company.id) {
                season(c, cur)
                clubTable(c)
            } else {
                Text("This club has no league data yet.").font(.caption).foregroundStyle(Theme.ivoryFaint)
            }
        }
        .confirmAction($pending)
        .navigationDestination(item: $part) { (p: Part) in
            SettingsPage(title: p.rawValue, subtitle: company.name) { clubPage(p) }
        }
    }

    /// The season is the page; the club's other areas are rows of a table, each opening a page of its own.
    private func clubTable(_ c: FootballModel.Summary) -> some View {
        let pos: String = c.position > 0 ? "\(c.position) of \(c.clubs)" : "–"
        let cur: Currency = engine.currency(for: company)
        let window = engine.transferWindow(companyID: company.id)
        let windowText: String = window.name.map { $0 == "summer" ? "Summer window open" : "Winter window open" } ?? "Opens in \(window.weeksToOpen) wk"
        let sponsorIncome: Double = c.sponsors.reduce(0) { $0 + $1.weekly }
        return SettingsTable(heading: "The club") {
            SettingsTableRow(title: Part.budget.rawValue, note: "Player wages against revenue", value: "Wages \(Int((c.wageShare * 100).rounded()))%") { part = .budget }
            SettingsTableRow(title: Part.people.rawValue, note: "Coach and football staff", value: "Squad " + FootballModel.wordForStrength(c.squadStrength)) { part = .people }
            SettingsTableRow(title: Part.transfers.rawValue, note: "Bought " + cur.tidyShort(c.tradedIn) + ", sold " + cur.tidyShort(c.tradedOut), value: windowText, valueTint: window.name == nil ? Theme.ivoryMuted : Theme.gain) { part = .transfers }
            SettingsTableRow(title: Part.sponsors.rawValue, note: "\(c.sponsors.count) of \(FootballModel.slots.count) deals signed", value: sponsorIncome > 0 ? cur.tidyShort(sponsorIncome) + " a week" : "No income") { part = .sponsors }
            SettingsTableRow(title: Part.table.rawValue, note: "The league table", value: pos) { part = .table }
        }
    }

    @ViewBuilder private func clubPage(_ p: Part) -> some View {
        let cur = engine.currency(for: company)
        if let c = engine.clubSummary(companyID: company.id) {
            switch p {
            case .season: season(c, cur)
            case .budget: budget(c, cur)
            case .people: people(c, cur)
            case .transfers: transfers(c, cur)
            case .sponsors: sponsors(c, cur)
            case .table: table(c)
            }
        }
    }

    private func form(_ r: String) -> some View {
        Text(r).font(.system(size: 12, weight: .semibold)).foregroundStyle(r == "W" ? Theme.gain : r == "L" ? Theme.loss : Theme.ivoryMuted).frame(width: 16)
    }

    private func seasonItems(_ c: FootballModel.Summary, _ cur: Currency) -> [KeyFigures.Item] {
        let pos: String = c.position > 0 ? "\(c.position) of \(c.clubs)" : "–"
        let fill: String = c.fill > 0 ? "\(Int((c.fill * 100).rounded()))%" : "–"
        let strengthSub: String = "strength \(Int(c.squadStrength.rounded()))"
        return [
            .init(label: "Position", value: pos),
            .init(label: "Points", value: "\(c.points)", sub: "from \(c.played) games"),
            .init(label: "Squad", value: FootballModel.wordForStrength(c.squadStrength), sub: strengthSub),
            .init(label: "Club value", value: cur.tidyShort(c.clubValue)),
            .init(label: "Titles", value: "\(c.titles)"),
            .init(label: "Stadium full", value: fill),
        ]
    }

    private func wageBinding(_ c: FootballModel.Summary) -> Binding<Double> {
        let options: [Double] = [0.55, 0.65, 0.8]
        let nearest: Double = options.min { abs($0 - c.wageShare) < abs($1 - c.wageShare) } ?? 0.65
        return Binding<Double>(get: { nearest }, set: { (v: Double) in
            store.act { $0.setClubWageShare(companyID: company.id, share: v) }
            store.saved("player wages \(Int(v * 100))% of revenue")
        })
    }

    private func ticketBinding(_ c: FootballModel.Summary) -> Binding<Int> {
        Binding<Int>(get: { c.ticketLevel }, set: { (v: Int) in
            store.act { $0.setClubTicketLevel(companyID: company.id, level: v) }
            store.saved("ticket prices \(["low", "normal", "high"][min(2, max(0, v + 1))])")
        })
    }

    private func season(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        MoreBlock(title: "\(c.leagueName) · season \(c.season)", trailing: { Text(c.division == 1 ? "Top flight" : "Second tier").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                FigureStrip(items: seasonItems(c, cur))
                FlatRow(label: "Recent form", value: c.form.isEmpty ? "Season not started" : "", sub: "").padding(.top, 8)
                if !c.form.isEmpty { HStack(spacing: 2) { ForEach(Array(c.form.suffix(8).enumerated()), id: \.offset) { _, r in form(r) } }.padding(.bottom, 6) }
                if c.debt > 0 { FlatRow(label: "Club debt", value: cur.tidyShort(c.debt), sub: "taken over when you bought the club", tint: Theme.loss) }
                stadiumCard(c, cur).padding(.top, 10)
                if !c.seasons.isEmpty {
                    Text("Past seasons").capsLabel().padding(.top, Theme.Space.m)
                    ForEach(Array(c.seasons.enumerated()), id: \.offset) { n, s in
                        FlatRow(label: "Season \(s.season)", value: "Position \(s.rank)\(s.division == 2 ? " (second tier)" : "")", rule: n >= 0)
                    }
                }
                Text("Results move revenue: a home match brings gate income, a winning side fills the ground and builds the fan base, and a title lifts the club's name. Relegation cuts television money and sponsors.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 8)
            }
        }
    }

    private func stadiumCard(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        let fillText: String = c.fill > 0 ? "\(Int((c.fill * 100).rounded()))% full" : "No home match yet"
        let gate: String = cur.tidyShort(c.weekly["match"] ?? 0)
        return EntityCard {
            HStack(spacing: 10) {
                IconCircle(glyph: Glyph.gym, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Stadium").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(fillText).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(gate).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text("last home gate").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func budget(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            MoreBlock("Budget") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Player wages, share of revenue").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    SegmentedChoice(items: [0.55, 0.65, 0.8], title: { "\(Int($0 * 100))%" },
                                selection: wageBinding(c))
                    Text("Ticket prices").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    SegmentedChoice(items: [-1, 0, 1], title: { ["Low", "Normal", "High"][$0 + 1] },
                                selection: ticketBinding(c))
                    Text("A bigger wage budget buys a stronger squad but eats the profit. Cheaper tickets fill the stadium and build the fan base.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            MoreBlock("A normal week") {
                VStack(spacing: 0) {
                    FlatRow(label: "Television", value: cur.tidyShort(c.weekly["tv"] ?? 0), rule: false)
                    FlatRow(label: "Sponsors", value: cur.tidyShort(c.weekly["spons"] ?? 0))
                    FlatRow(label: "Merchandise", value: cur.tidyShort(c.weekly["merch"] ?? 0))
                    FlatRow(label: "Gate income, last home match", value: cur.tidyShort(c.weekly["match"] ?? 0))
                    FlatRow(label: "Player wages", value: cur.tidyShort(c.weekly["wages"] ?? 0), tint: Theme.ivoryMuted)
                    FlatRow(label: "Manager and assistant", value: cur.tidyShort(c.weekly["coaches"] ?? 0), tint: Theme.ivoryMuted)
                    FlatRow(label: "Stadium, travel, academy", value: cur.tidyShort(c.weekly["ops"] ?? 0), tint: Theme.ivoryMuted)
                    FlatRow(label: "Wages share of revenue", value: "\(Int((c.wageToRevenue * 100).rounded()))%", tint: c.wageToRevenue > 0.75 ? Theme.loss : Theme.ivory)
                    FlatRow(label: "Yearly revenue (about)", value: cur.tidyShort(c.yearlyRevenue))
                }
            }
        }
    }

    private func people(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            MoreBlock("Football staff", card: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("You do not pick players: the manager does. Every club needs a manager and an assistant. If the manager is sacked, the assistant steps in until you hire a new one.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    person(c.coach, kind: "coach", title: "Manager", cur)
                    person(c.assistant, kind: "asst", title: "Assistant manager", cur)
                }
            }
            if !candidates.isEmpty {
                MoreBlock("Candidates", card: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(candidates, id: \.id) { (cd: FootballModel.Coach) in candidateCard(cd, cur) }
                        HStack { Button("Cancel") { candidates = [] }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted)); Spacer() }
                    }
                }
            }
        }
    }

    private func candidateCard(_ cd: FootballModel.Coach, _ cur: Currency) -> some View {
        let line: String = "Age \(cd.age) · \(cd.quality) · asks \(cur.tidyShort(cd.wage)) a week"
        return EntityCard {
            HStack(spacing: 10) {
                IconCircle(glyph: Glyph.person, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cd.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(line).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Button("Hire…") { askHire(cd, cur) }.buttonStyle(TinyButtonStyle())
            }
        }
    }

    private func askHire(_ cd: FootballModel.Coach, _ cur: Currency) {
        let kind: String = hiringKind
        let post: String = kind == "coach" ? "manager" : "assistant manager"
        let message: String = "\(cur.tidyDisplay(cd.wage)) a week for a \(post) of quality \(cd.quality). Whoever holds the post now is replaced."
        pending = PendingAction(title: "Hire \(cd.name)?", message: message, button: "Hire") {
            if store.act({ $0.hireCoach(companyID: company.id, coach: cd, kind: kind) }) == true {
                candidates = []; Haptics.success(); store.show("\(cd.name) is the new \(post).", tone: "good")
            } else { Haptics.warning(); store.show("\(cd.name) could not be hired: the club is not able to take on a \(post) now.", tone: "warn") }
        }
    }

    private func person(_ p: FootballModel.Coach?, kind: String, title: String, _ cur: Currency) -> some View {
        let detail: String = p.map { "\($0.name)\($0.interim ? " (interim)" : "") · \($0.quality) · \(cur.tidyShort($0.wage)) a week" } ?? "Vacant"
        return EntityCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    IconCircle(glyph: Glyph.person, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text(detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Button(p == nil ? "Find one" : "Replace") {
                        hiringKind = kind
                        candidates = store.act { $0.clubCandidates(companyID: company.id, kind: kind) } ?? []
                        if candidates.isEmpty { store.show("Nobody suitable is available right now.", tone: "warn") }
                    }.buttonStyle(TinyButtonStyle())
                    if let p { Button("Dismiss…") { askDismiss(p, kind: kind) }.buttonStyle(TinyButtonStyle(tint: Theme.loss)) }
                    Spacer()
                }
            }
        }
    }

    private func askDismiss(_ p: FootballModel.Coach, kind: String) {
        let message: String = kind == "coach" ? "The assistant steps in until you hire a new manager. Results can suffer in between." : "The club has no assistant until you hire one."
        pending = PendingAction(title: "Dismiss \(p.name)?", message: message, button: "Dismiss", destructive: true) {
            if store.act({ $0.dismissCoach(companyID: company.id, kind: kind) }) == true { Haptics.warning(); store.show("\(p.name) has gone.", tone: "n") }
            else { store.show("\(p.name) is no longer in post.", tone: "warn") }
        }
    }

    private func transfers(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        let w = engine.transferWindow(companyID: company.id)
        let windowText: String = w.name.map { $0 == "summer" ? "Summer window open" : "Winter window open" } ?? "Closed · opens in \(w.weeksToOpen) wk"
        let windowItems: [KeyFigures.Item] = [
            .init(label: "Window", value: windowText, tint: w.name == nil ? Theme.ivoryMuted : Theme.gain),
            .init(label: "Bought", value: cur.tidyShort(c.tradedIn)),
            .init(label: "Sold", value: cur.tidyShort(c.tradedOut)),
        ]
        return MoreBlock("Transfers", card: false) {
            VStack(alignment: .leading, spacing: 10) {
                Card(padding: 14, radius: Theme.Radius.hero) { FigureStrip(items: windowItems) }
                ForEach(0..<FootballModel.tiers.count, id: \.self) { (i: Int) in tierCard(i, windowOpen: w.name != nil, cur) }
                Text("Clubs bid for your players while a window is open; you will find the offer in your inbox. Selling brings cash and weakens the team. Signings cost a fee up front and more wages.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func tierCard(_ i: Int, windowOpen: Bool, _ cur: Currency) -> some View {
        let t = FootballModel.tiers[i]
        let fee: Double = engine.signingFee(companyID: company.id, tier: i)
        let strength: String = String(format: "%.1f", t.strength)
        let line: String = "\(cur.tidyShort(fee)) fee, written off over three years · about +\(strength) strength"
        return EntityCard {
            HStack(spacing: 10) {
                IconCircle(glyph: Glyph.hire, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(line).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Button("Sign…") { askSign(i, t.name, fee, cur) }.buttonStyle(TinyButtonStyle()).disabled(!windowOpen)
            }
        }
    }

    private func askSign(_ i: Int, _ tierName: String, _ fee: Double, _ cur: Currency) {
        let message: String = "\(cur.tidyDisplay(fee)) fee now, written off over three years, and higher wages from then on. The club has \(cur.tidyShort(company.cash))."
        pending = PendingAction(title: "Sign a \(tierName.lowercased())?", message: message, button: "Sign") {
            switch store.act({ $0.signPlayer(companyID: company.id, tier: i) }) {
            case .ok?: Haptics.success(); store.show("Signed.", tone: "good")
            case .closed?: store.show("The transfer window is closed.", tone: "warn")
            default: store.show("The club needs \(cur.tidyShort(fee)) in cash.", tone: "warn")
            }
        }
    }

    private func sponsors(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            ForEach(Array(FootballModel.slots.enumerated()), id: \.offset) { (_: Int, slot: (key: String, title: String, share: Double)) in
                sponsorSlot(c, slot.key, slot.title, cur)
            }
        }
    }

    private func sponsorSlot(_ c: FootballModel.Summary, _ key: String, _ title: String, _ cur: Currency) -> some View {
        MoreBlock(title, card: false) {
            VStack(alignment: .leading, spacing: 10) {
                if let s = c.sponsors.first(where: { $0.slot == key }) {
                    let line: String = String(format: "%.1f years left", s.yearsLeft)
                    EntityCard {
                        HStack(spacing: 10) {
                            IconCircle(glyph: Glyph.richList, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                                Text(line).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer()
                            Text(cur.tidyShort(s.weekly) + " / wk").font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                        }
                    }
                } else if let offers = c.offers[key], !offers.isEmpty {
                    ForEach(Array(offers.enumerated()), id: \.offset) { (_: Int, o: ClubOffer) in offerCard(o, key, title, cur) }
                } else {
                    Card(padding: 12, radius: Theme.Radius.row) {
                        Text("No offers right now.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
        }
    }

    private func offerCard(_ o: ClubOffer, _ key: String, _ title: String, _ cur: Currency) -> some View {
        let plural: String = o.years == 1 ? "" : "s"
        let line: String = "\(cur.tidyShort(o.weekly)) a week · \(o.years) year\(plural)"
        return EntityCard {
            HStack(spacing: 10) {
                IconCircle(glyph: Glyph.richList, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(o.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(line).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Button("Sign…") {
                    let message: String = "\(cur.tidyDisplay(o.weekly)) a week for \(o.years) year\(plural) as your \(title.lowercased()). You cannot take another offer for this slot until it ends."
                    pending = PendingAction(title: "Sign \(o.name)?", message: message, button: "Sign") {
                        if store.act({ $0.signSponsor(companyID: company.id, slot: key, offerID: o.id) }) == .ok { Haptics.success(); store.show("\(o.name) signed.", tone: "good") }
                        else { store.show("That offer is no longer available.", tone: "warn") }
                    }
                }.buttonStyle(TinyButtonStyle())
            }
        }
    }

    private func table(_ c: FootballModel.Summary) -> some View {
        let cols: [TableColumn] = [TableColumn(title: "Club"), TableColumn(title: "P", width: 30), TableColumn(title: "Pts", width: 36)]
        return MoreBlock("Table", card: false) {
            SharpTable {
                TableHeader(columns: cols)
                ForEach(c.table) { (r: FootballModel.TableRow) in
                    let name: String = "\(r.position)  " + r.name + (r.isYours ? " (you)" : "")
                    TableRow(columns: cols, title: name, values: ["\(r.played)", "\(r.points)"], selected: r.isYours)
                }
            }
        }
    }
}

/// Buy a club in a country's top league, or found a new one in the second tier.
struct ClubMarketView: View {
    @EnvironmentObject var store: GameStore
    @State private var country = ""
    @State private var offerFor: FootballModel.ClubInfo?
    @State private var answer: FootballModel.Offer?
    @State private var confirmFound = false

    var body: some View {
        if let e = store.engine {
            let countries = e.leagueCountries()
            let code = country.isEmpty ? (countries.first(where: { $0.code == e.state.homeCountryCode })?.code ?? countries.first?.code ?? "") : country
            let info = e.leagueInfo(countryCode: code)
            let cur = e.homeCurrency
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    MoreHeader(glyph: Glyph.achievements, title: "A professional club",
                               blurb: "You own it and set the budget, sponsors and ticket prices; the manager picks the players. Many owners will not sell at any price, and clubs come with debt. Most clubs lose money or break even.")
                    MoreBlock("League") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Country", selection: Binding(get: { code }, set: { country = $0 })) { ForEach(countries) { Text("\($0.flag) \($0.name)").tag($0.code) } }.pickerStyle(.menu)
                            if let info { Text("\(info.name) · \(info.clubs) clubs. Values are rough market estimates.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                        }
                    }
                    MoreBlock("Clubs", card: false) {
                        VStack(spacing: 10) {
                            ForEach(e.clubsForSale(countryCode: code), id: \.id) { (c: FootballModel.ClubInfo) in clubCard(c, cur) }
                        }
                    }
                    if let cost = e.foundingCost(countryCode: code) {
                        MoreBlock("Found a new club") {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                Text("Start a club in the second tier. It costs about \(cur.tidyShort(cost)) and must earn promotion to the top league (finish in the top three).").font(.caption).foregroundStyle(Theme.ivoryMuted)
                                Button("Found a club") { confirmFound = true }.buttonStyle(TinyButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .appScreen(title: "Football clubs", subtitle: "Buy a club or found a new one.")
            .sheet(item: $offerFor) { c in offerSheet(c, cur) }
            .confirmationDialog("Found a new club?", isPresented: $confirmFound, titleVisibility: .visible) {
                Button("Found it") {
                    switch store.act({ $0.foundClub(countryCode: code) }) {
                    case .ok(let id)?: Haptics.success(); store.openCompany(id)
                    case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in your account.", tone: "warn")
                    default: store.show("Not possible.", tone: "warn")
                    }
                }
            } message: { Text("You pay about 40% of its starting value and fund the early seasons yourself.") }
        }
    }

    private func clubCard(_ c: FootballModel.ClubInfo, _ cur: Currency) -> some View {
        let line: String = "About \(cur.tidyShort(c.value))" + (c.isListed ? " · open to offers" : "")
        return EntityCard {
            HStack(spacing: 10) {
                IconCircle(glyph: Glyph.achievements, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(line).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                if c.owner == "you" { Chip(text: "Yours", tint: Theme.gold) }
                else { Button("Make an offer") { offerFor = c; answer = nil }.buttonStyle(TinyButtonStyle()) }
            }
        }
    }

    private func offerSheet(_ c: FootballModel.ClubInfo, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(c.name).font(.serifTitle(22))
            Text("Rough value \(cur.tidyShort(c.value)). A bad offer can end the talks for a year.").font(.caption).foregroundStyle(Theme.ivoryMuted)
            if let a = answer {
                Text(a.message.tidyMoney).font(.bodyText).foregroundStyle(a.answer == .accept ? Theme.gain : a.answer == .counter ? Theme.ivory : Theme.loss)
                if let p = a.price, a.answer == .accept || a.answer == .counter {
                    Button((a.answer == .accept ? "Buy for " : "Accept ") + cur.tidyShort(p)) {
                        switch store.act({ $0.buyClub(clubID: c.id, price: p) }) {
                        case .ok(let id)?: Haptics.success(); offerFor = nil; store.openCompany(id)
                        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in your account.", tone: "warn")
                        default: store.show("The club is no longer for sale.", tone: "warn")
                        }
                    }.buttonStyle(TinyButtonStyle())
                }
            } else {
                ForEach([0.9, 1.2, 1.8, 3.0], id: \.self) { f in
                    Button { answer = store.act { $0.offerForClub(clubID: c.id, multiple: f) } } label: {
                        EntityCard {
                            HStack {
                                Text(cur.tidyShort((c.value * f / 100000).rounded() * 100000)).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                                Spacer()
                                Text("\(Int(f * 100))% of value").font(.caption).foregroundStyle(Theme.ivoryFaint)
                                MoreChevron()
                            }.contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain)
                }
            }
            HStack { Button("Close") { offerFor = nil }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted)); Spacer() }
        }
        .padding(Theme.Space.margin)
        .presentationDetents([.medium])
        .ledgerBackground()
    }
}

