import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A football club's own section: the season and table, the budget, sponsors, staff and transfers.
struct CompanyClub: View {
    enum Part: String, CaseIterable, Hashable { case season = "Season", budget = "Budget", people = "Staff", transfers = "Transfers", sponsors = "Sponsors", table = "Table" }
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var part: Part = .season
    @State private var candidates: [FootballModel.Coach] = []
    @State private var hiringKind = "coach"

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionTabs(items: Part.allCases, title: { $0.rawValue }, selection: $part).padding(.horizontal, -Theme.Space.margin)
            if let c = engine.clubSummary(companyID: company.id) {
                switch part {
                case .season: season(c, cur)
                case .budget: budget(c, cur)
                case .people: people(c, cur)
                case .transfers: transfers(c, cur)
                case .sponsors: sponsors(c, cur)
                case .table: table(c)
                }
            } else {
                Text("This club has no league data yet.").font(.caption).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func form(_ r: String) -> some View {
        Text(r).font(.system(size: 12, weight: .semibold)).foregroundStyle(r == "W" ? Theme.gain : r == "L" ? Theme.loss : Theme.ivoryMuted).frame(width: 16)
    }

    private func season(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        LedgerSection(title: "\(c.leagueName) · season \(c.season)", trailing: { Text(c.division == 1 ? "Top flight" : "Second tier").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                KeyFigures(items: [
                    .init(label: "Position", value: c.position > 0 ? "\(c.position) of \(c.clubs)" : "–"),
                    .init(label: "Points", value: "\(c.points)", sub: "from \(c.played) games"),
                    .init(label: "Squad", value: FootballModel.wordForStrength(c.squadStrength), sub: "strength \(Int(c.squadStrength.rounded()))"),
                    .init(label: "Club value", value: cur.short(c.clubValue)),
                    .init(label: "Titles", value: "\(c.titles)"),
                    .init(label: "Stadium full", value: c.fill > 0 ? "\(Int((c.fill * 100).rounded()))%" : "–"),
                ])
                FlatRow(label: "Recent form", value: c.form.isEmpty ? "Season not started" : "", sub: "").padding(.top, 8)
                if !c.form.isEmpty { HStack(spacing: 2) { ForEach(Array(c.form.suffix(8).enumerated()), id: \.offset) { _, r in form(r) } }.padding(.bottom, 6) }
                if c.debt > 0 { FlatRow(label: "Club debt", value: cur.short(c.debt), tint: Theme.loss, sub: "taken over when you bought the club") }
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

    private func budget(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection("Budget") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Player wages, share of revenue").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    SectionTabs(items: [0.55, 0.65, 0.8], title: { "\(Int($0 * 100))%" },
                                selection: Binding(get: { [0.55, 0.65, 0.8].min { abs($0 - c.wageShare) < abs($1 - c.wageShare) } ?? 0.65 }, set: { v in store.act { $0.setClubWageShare(companyID: company.id, share: v) } }))
                        .padding(.horizontal, -Theme.Space.margin)
                    Text("Ticket prices").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    SectionTabs(items: [-1, 0, 1], title: { ["Low", "Normal", "High"][$0 + 1] },
                                selection: Binding(get: { c.ticketLevel }, set: { v in store.act { $0.setClubTicketLevel(companyID: company.id, level: v) } }))
                        .padding(.horizontal, -Theme.Space.margin)
                    Text("A bigger wage budget buys a stronger squad but eats the profit. Cheaper tickets fill the stadium and build the fan base.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            LedgerSection("A normal week") {
                VStack(spacing: 0) {
                    FlatRow(label: "Television", value: cur.short(c.weekly["tv"] ?? 0), rule: false)
                    FlatRow(label: "Sponsors", value: cur.short(c.weekly["spons"] ?? 0))
                    FlatRow(label: "Merchandise", value: cur.short(c.weekly["merch"] ?? 0))
                    FlatRow(label: "Gate income, last home match", value: cur.short(c.weekly["match"] ?? 0))
                    FlatRow(label: "Player wages", value: cur.short(c.weekly["wages"] ?? 0), tint: Theme.ivoryMuted)
                    FlatRow(label: "Manager and assistant", value: cur.short(c.weekly["coaches"] ?? 0), tint: Theme.ivoryMuted)
                    FlatRow(label: "Stadium, travel, academy", value: cur.short(c.weekly["ops"] ?? 0), tint: Theme.ivoryMuted)
                    FlatRow(label: "Wages share of revenue", value: "\(Int((c.wageToRevenue * 100).rounded()))%", tint: c.wageToRevenue > 0.75 ? Theme.loss : Theme.ivory)
                    FlatRow(label: "Yearly revenue (about)", value: cur.short(c.yearlyRevenue))
                }
            }
        }
    }

    private func people(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection("Football staff") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("You do not pick players: the manager does. Every club needs a manager and an assistant. If the manager is sacked, the assistant steps in until you hire a new one.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6)
                    person(c.coach, kind: "coach", title: "Manager", cur)
                    person(c.assistant, kind: "asst", title: "Assistant manager", cur)
                }
            }
            if !candidates.isEmpty {
                LedgerSection("Candidates") {
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { n, cd in
                            if n > 0 { Hairline() }
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(cd.name).font(.system(size: 13.5))
                                    Text("Age \(cd.age) · \(cd.quality) · asks \(cur.short(cd.wage)) a week").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer()
                                Button("Hire") { store.act { $0.hireCoach(companyID: company.id, coach: cd, kind: hiringKind) }; candidates = []; Haptics.success() }.buttonStyle(QuietButtonStyle())
                            }.padding(.vertical, 8)
                        }
                        Button("Cancel") { candidates = [] }.font(.caption).foregroundStyle(Theme.ivoryFaint).buttonStyle(.plain).padding(.top, 6)
                    }
                }
            }
        }
    }

    private func person(_ p: FootballModel.Coach?, kind: String, title: String, _ cur: Currency) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5))
                    Text(p.map { "\($0.name)\($0.interim ? " (interim)" : "") · \($0.quality) · \(cur.short($0.wage)) a week" } ?? "Vacant").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                if p != nil { Button("Dismiss") { store.act { $0.dismissCoach(companyID: company.id, kind: kind) }; Haptics.warning() }.font(.system(size: 12)).foregroundStyle(Theme.loss).buttonStyle(.plain) }
                Button(p == nil ? "Find one" : "Replace") {
                    hiringKind = kind
                    candidates = store.act { $0.clubCandidates(companyID: company.id, kind: kind) } ?? []
                }.buttonStyle(QuietButtonStyle())
            }.padding(.vertical, 9)
        }
    }

    private func transfers(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        let w = engine.transferWindow(companyID: company.id)
        return LedgerSection("Transfers") {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: "Window", value: w.name.map { $0 == "summer" ? "Summer window open" : "Winter window open" } ?? "Closed · opens in \(w.weeksToOpen) wk", rule: false)
                FlatRow(label: "Bought / sold", value: cur.short(c.tradedIn) + " / " + cur.short(c.tradedOut))
                ForEach(0..<FootballModel.tiers.count, id: \.self) { i in
                    let t = FootballModel.tiers[i]
                    VStack(spacing: 0) {
                        Hairline()
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.name).font(.system(size: 13.5))
                                Text("\(cur.short(engine.signingFee(companyID: company.id, tier: i))) fee, written off over three years · about +\(String(format: "%.1f", t.strength)) strength").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer()
                            Button("Sign") {
                                switch store.act({ $0.signPlayer(companyID: company.id, tier: i) }) {
                                case .ok?: Haptics.success(); store.show("Signed.", tone: "good")
                                case .closed?: store.show("The transfer window is closed.", tone: "warn")
                                default: store.show("Not enough cash in the club.", tone: "warn")
                                }
                            }.buttonStyle(QuietButtonStyle()).disabled(w.name == nil)
                        }.padding(.vertical, 9)
                    }
                }
                Text("Clubs bid for your players while a window is open; you will find the offer in your inbox. Selling brings cash and weakens the team. Signings cost a fee up front and more wages.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
            }
        }
    }

    private func sponsors(_ c: FootballModel.Summary, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            ForEach(Array(FootballModel.slots.enumerated()), id: \.offset) { _, slot in
                LedgerSection(slot.title) {
                    VStack(spacing: 0) {
                        if let s = c.sponsors.first(where: { $0.slot == slot.key }) {
                            FlatRow(label: s.name, value: cur.short(s.weekly) + " / wk", sub: String(format: "%.1f years left", s.yearsLeft), rule: false)
                        } else if let offers = c.offers[slot.key], !offers.isEmpty {
                            ForEach(Array(offers.enumerated()), id: \.element.id) { n, o in
                                if n > 0 { Hairline() }
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(o.name).font(.system(size: 13.5))
                                        Text("\(cur.short(o.weekly)) a week · \(o.years) year\(o.years == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                    }
                                    Spacer()
                                    Button("Sign") { if store.act({ $0.signSponsor(companyID: company.id, slot: slot.key, offerID: o.id) }) == .ok { Haptics.success() } }.buttonStyle(QuietButtonStyle())
                                }.padding(.vertical, 8)
                            }
                        } else {
                            Text("No offers right now.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
            }
        }
    }

    private func table(_ c: FootballModel.Summary) -> some View {
        LedgerSection("Table") {
            VStack(spacing: 0) {
                ForEach(c.table) { r in
                    HStack {
                        Text("\(r.position)").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint).frame(width: 26, alignment: .leading)
                        Text(r.name + (r.isYours ? " (you)" : "")).font(.system(size: 13.5, weight: r.isYours ? .semibold : .regular)).foregroundStyle(r.isYours ? Theme.gold : Theme.ivory).lineLimit(1)
                        Spacer()
                        Text("\(r.played)").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint).frame(width: 30, alignment: .trailing)
                        Text("\(r.points)").font(.system(size: 13.5).monospacedDigit()).frame(width: 34, alignment: .trailing)
                    }.padding(.vertical, 6)
                    Hairline()
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
                    Text("A professional club. You own it and set the budget, sponsors and ticket prices; the manager picks the players. Many owners will not sell at any price, and clubs come with debt. Most clubs lose money or break even.")
                        .font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                    LedgerSection("League") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Country", selection: Binding(get: { code }, set: { country = $0 })) { ForEach(countries) { Text("\($0.flag) \($0.name)").tag($0.code) } }.pickerStyle(.menu)
                            if let info { Text("\(info.name) · \(info.clubs) clubs. Values are rough market estimates.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                        }
                    }
                    LedgerSection("Clubs") {
                        VStack(spacing: 0) {
                            ForEach(Array(e.clubsForSale(countryCode: code).enumerated()), id: \.element.id) { n, c in
                                if n > 0 { Hairline() }
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(c.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                        Text("About \(cur.short(c.value))\(c.isListed ? " · open to offers" : "")").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                    }
                                    Spacer()
                                    if c.owner == "you" { Chip(text: "Yours", tint: Theme.gold) }
                                    else { Button("Make an offer") { offerFor = c; answer = nil }.buttonStyle(QuietButtonStyle()) }
                                }.padding(.vertical, 9)
                            }
                        }
                    }
                    if let cost = e.foundingCost(countryCode: code) {
                        LedgerSection("Found a new club") {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                Text("Start a club in the second tier. It costs about \(cur.short(cost)) and must earn promotion to the top league (finish in the top three).").font(.caption).foregroundStyle(Theme.ivoryMuted)
                                Button("Found a club") { confirmFound = true }.buttonStyle(QuietButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Football clubs")
            .sheet(item: $offerFor) { c in offerSheet(c, cur) }
            .confirmationDialog("Found a new club?", isPresented: $confirmFound, titleVisibility: .visible) {
                Button("Found it") {
                    switch store.act({ $0.foundClub(countryCode: code) }) {
                    case .ok(let id)?: Haptics.success(); store.tab = .companies; store.openCompanyID = id
                    case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in your account.", tone: "warn")
                    default: store.show("Not possible.", tone: "warn")
                    }
                }
            } message: { Text("You pay about 40% of its starting value and fund the early seasons yourself.") }
        }
    }

    private func offerSheet(_ c: FootballModel.ClubInfo, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(c.name).font(.serifTitle(22))
            Text("Rough value \(cur.short(c.value)). A bad offer can end the talks for a year.").font(.caption).foregroundStyle(Theme.ivoryMuted)
            if let a = answer {
                Text(a.message).font(.bodyText).foregroundStyle(a.answer == .accept ? Theme.gain : a.answer == .counter ? Theme.ivory : Theme.loss)
                if let p = a.price, a.answer == .accept || a.answer == .counter {
                    Button((a.answer == .accept ? "Buy for " : "Accept ") + cur.short(p)) {
                        switch store.act({ $0.buyClub(clubID: c.id, price: p) }) {
                        case .ok(let id)?: Haptics.success(); offerFor = nil; store.tab = .companies; store.openCompanyID = id
                        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in your account.", tone: "warn")
                        default: store.show("The club is no longer for sale.", tone: "warn")
                        }
                    }.buttonStyle(GoldButtonStyle())
                }
            } else {
                ForEach([0.9, 1.2, 1.8, 3.0], id: \.self) { f in
                    Button { answer = store.act { $0.offerForClub(clubID: c.id, multiple: f) } } label: {
                        HStack { Text(cur.short((c.value * f / 100000).rounded() * 100000)).font(.system(size: 15, weight: .medium)); Spacer(); Text("\(Int(f * 100))% of value").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                            .padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Hairline()
                }
            }
            Button("Close") { offerFor = nil }.font(.caption).foregroundStyle(Theme.ivoryFaint).buttonStyle(.plain)
        }
        .padding(Theme.Space.margin)
        .presentationDetents([.medium])
        .ledgerBackground()
    }
}

