import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Ventures (Projects > Ventures): each kind is its own workflow. Startups you found (build, raise, run out of runway or exit), startups you
/// back (pick a pitch, size the cheque, help on the board, sell), private equity funds (commit, capital calls, sell on the secondary market),
/// stakes in groups from the big meeting, and software of your own built by a web-development company. A waiting big-meeting offer comes
/// first because it expires. Logic: `Startups`, `PrivateEquity`, `BigMeeting`, `GroupDeals`, `SoftwareProducts`.
struct VenturesContent: View {
    enum Part: String, CaseIterable, Hashable { case founded = "Your startups", backing = "Backing startups", funds = "Private equity", groups = "Stakes in groups", software = "Software" }
    @EnvironmentObject var store: GameStore
    @State private var part: Part = .founded
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                summary(e)
                if let o = e.bigMeetingOffer { BigMeetingCard(engine: e, offer: o) }
                SectionTabs(items: Part.allCases, title: { $0.rawValue }, selection: $part, badge: { badge(e, $0) }).padding(.horizontal, -Theme.Space.margin)
                switch part {
                case .founded: FoundedStartups(engine: e)
                case .backing: BackedStartups(engine: e)
                case .funds: PrivateEquityPart(engine: e)
                case .groups: GroupStakesPart(engine: e)
                case .software: SoftwarePart(engine: e)
                }
            }
        }
    }

    private func badge(_ e: GameEngine, _ p: Part) -> Int {
        switch p {
        case .founded: return e.foundedStartups.filter { $0.live }.reduce(0) { $0 + $1.offers.count }
        default: return 0
        }
    }

    private func summary(_ e: GameEngine) -> some View {
        let cur = e.homeCurrency
        let founded = e.foundedStartups.filter { $0.live }
        let stakes = e.startupStakes.filter { $0.live }
        let funds = e.privateEquityFunds.filter { $0.live }
        let groups = e.bigMeetingStakes.reduce(0) { $0 + $1.value } + e.groupStakes.reduce(0) { $0 + $1.value }
        return KeyFigures(items: [
            .init(label: "Your startups", value: founded.isEmpty ? "None" : cur.short(founded.reduce(0) { $0 + $1.valuation * $1.ownership / 100 }), sub: founded.isEmpty ? "" : "\(founded.count) running"),
            .init(label: "Startup stakes", value: stakes.isEmpty ? "None" : cur.short(stakes.reduce(0) { $0 + $1.value }), sub: stakes.isEmpty ? "" : "\(stakes.count) held"),
            .init(label: "Funds and groups", value: funds.isEmpty && groups == 0 ? "None" : cur.short(funds.reduce(0) { $0 + $1.nav } + groups)),
        ])
    }
}

// MARK: Big meeting

/// An offer of a stake in a large group, financed partly by an acquisition loan. Accept, counter once, or walk away.
private struct BigMeetingCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var o: BigMeeting.Offer
    @State private var pending: PendingAction?

    init(engine: GameEngine, offer: BigMeeting.Offer) { self.engine = engine; self.o = offer }

    var body: some View {
        let cur = engine.homeCurrency
        let f = engine.bigMeetingFinancing(price: o.price)
        let warn = engine.bigMeetingRatesWarning()
        LedgerSection(title: "Decision · big meeting", trailing: { Text("until \(GameCalendar.dateString(week: o.expiresWeek))").font(.system(size: 11)).foregroundStyle(Theme.caution) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("\(o.seller) of \(o.sellerCompany) offers \(o.pct)% of \(o.target).").font(.system(size: 14)).foregroundStyle(Theme.ivory)
                KeyFigures(items: [
                    .init(label: "Price", value: cur.short(o.price)),
                    .init(label: "Profit share", value: cur.short(o.yearlyProfitShare), sub: "a year"),
                    .init(label: "Your own money", value: cur.short(f.own), tint: Payments.liquid(engine.state) < f.own ? Theme.loss : Theme.ivory),
                    .init(label: "Loan", value: f.borrow > 0 ? cur.short(f.borrow) : "None", sub: f.borrow > 0 ? "10 years at bank rate + 2%" : ""),
                ], columns: 2)
                if warn { Text("If rates rise two points, the interest on the loan would cost more than the profit share brings.").font(.caption).foregroundStyle(Theme.caution) }
                HStack {
                    Button("Accept") {
                        pending = PendingAction(title: "Buy \(o.pct)% of \(o.target) for \(cur.short(o.price))?",
                                                message: "\(cur.display(f.own)) from your cash and savings" + (f.borrow > 0 ? ", \(cur.display(f.borrow)) as a 10-year acquisition loan in your name" : "") + ". You receive about \(cur.display(o.yearlyProfitShare)) a year as your share of the profit; the value can fall.",
                                                button: "Buy the stake") {
                            switch store.act({ $0.acceptBigMeetingOffer() }) {
                            case .ok?: Haptics.success(); store.show("You bought \(o.pct)% of \(o.target).", tone: "good")
                            case .needsOwnMoney(let v)?: Haptics.warning(); store.show("The bank wants \(cur.short(v)) of your own money first.", tone: "warn")
                            default: store.show("The offer has gone.", tone: "warn")
                            }
                        }
                    }.buttonStyle(SmallGoldButtonStyle())
                    if !o.countered {
                        Button("Counter −10%") {
                            pending = PendingAction(title: "Ask for 10% off?", message: "They may accept the lower price, or withdraw the offer for good.", button: "Counter") {
                                let r = store.act { $0.counterBigMeetingOffer() } ?? nil
                                store.show(r == true ? "They accepted the lower price." : r == false ? "They refused and withdrew the offer." : "The offer has gone.", tone: r == true ? "good" : "warn")
                            }
                        }.buttonStyle(SmallOutlineButtonStyle())
                    }
                    Button("Walk away") { store.act { $0.walkAwayFromBigMeeting() }; store.show("You walked away from the offer.", tone: "n") }.buttonStyle(SmallOutlineButtonStyle())
                }
            }
        }
        .confirmAction($pending)
    }
}

// MARK: Your startups

private struct FoundedStartups: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var founding = false
    @State private var showPast = false

    var body: some View {
        let all = engine.foundedStartups
        let live = all.filter { $0.live }
        let past = all.filter { !$0.live }
        let r = engine.founderRecord
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your record: \(r.exits) exit\(r.exits == 1 ? "" : "s") · \(r.fails) failure\(r.fails == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                Spacer()
                Button("Found a startup") { founding = true }.buttonStyle(SmallGoldButtonStyle())
            }
            if live.isEmpty {
                Text("You run no startup. Found one: you put in the seed money, hire builders, and raise rounds from investors as the product takes shape. Most fail; a few sell for many times what went in.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(live) { f in FoundedCard(engine: engine, startup: f) }
            if !past.isEmpty {
                Button(showPast ? "Hide past startups" : "Past startups (\(past.count))") { showPast.toggle() }.buttonStyle(SmallOutlineButtonStyle())
                if showPast {
                    ForEach(past) { f in
                        FlatRow(label: f.name, value: f.exited ? engine.homeCurrency.short(f.exitValue) : "Closed", sub: "\(f.sectorName) · \(f.stageName)", tint: f.exited ? Theme.gain : Theme.ivoryFaint)
                    }
                }
            }
        }
        .sheet(isPresented: $founding) { FoundStartupSheet() }
    }
}

private struct FoundedCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var f: Startups.Founded
    @State private var pending: PendingAction?

    init(engine: GameEngine, startup: Startups.Founded) { self.engine = engine; self.f = startup }

    var body: some View {
        let cur = engine.homeCurrency
        let monthlyBurn = f.burn * 52 / 12
        let interest = engine.startupInterest(startupID: f.id)
        let topUp = cur.scaledPrice(100000)
        LedgerSection(title: f.name, trailing: { Text("\(f.productName) · \(f.stageName)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                KeyFigures(items: [
                    .init(label: "You own", value: "\(Int(f.ownership.rounded()))%", sub: "worth \(cur.short(f.valuation * f.ownership / 100))"),
                    .init(label: "Cash", value: cur.short(f.cash), tint: f.runwayWeeks < 8 ? Theme.loss : Theme.ivory, sub: "\(f.runwayWeeks) weeks of runway"),
                    .init(label: "Burn", value: cur.short(monthlyBurn), sub: "a month"),
                ])
                if let p = f.product {
                    Text(productLine(p, cur)).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                }
                Text("Investors: \(interest.word)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                if f.runwayWeeks < 8 { Text("Runway is short: raise a round or put money in, or it closes when the cash runs out.").font(.caption).foregroundStyle(Theme.caution) }
                ForEach(f.offers) { o in
                    let after = f.ownership * (1 - o.pct / 100)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(o.name) offers \(cur.short(o.amount)) for \(Int(o.pct.rounded()))%").font(.system(size: 13.5)).foregroundStyle(Theme.gold)
                        Text("\(o.says) Values it at \(cur.short(o.preMoney)) before the money.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Accept") {
                                pending = PendingAction(title: "Take \(cur.short(o.amount)) for \(Int(o.pct.rounded()))%?",
                                                        message: "The money goes into \(f.name). You go from \(Int(f.ownership.rounded()))% to about \(Int(after.rounded()))%; the investor gets a say and a share of any exit.",
                                                        button: "Close the round") {
                                    let ok = store.act { $0.acceptStartupRound(startupID: f.id, index: o.id) } ?? false
                                    store.show(ok ? "Round closed: \(cur.short(o.amount)) in for \(Int(o.pct.rounded()))%." : "That offer is no longer on the table.", tone: ok ? "good" : "warn")
                                }
                            }.buttonStyle(SmallGoldButtonStyle())
                            Button("Decline") { store.act { $0.declineStartupRound(startupID: f.id, index: o.id) }; store.show("Offer declined.", tone: "n") }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }.padding(.vertical, 4)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Button("Raise a round") {
                            switch store.act({ $0.pitchStartupRound(startupID: f.id) }) {
                            case .offers(let n)?: Haptics.success(); store.show("\(n) investor\(n == 1 ? "" : "s") made an offer.", tone: "good")
                            case .none?: store.show("No investor bit this time.", tone: "warn")
                            case .tooSoon(let w)?: store.show("Too soon to pitch again: \(w) week\(w == 1 ? "" : "s") to go.", tone: "n")
                            default: store.show("This startup is no longer running.", tone: "warn")
                            }
                        }.buttonStyle(SmallOutlineButtonStyle())
                        Button("Put in \(cur.short(topUp))") {
                            pending = PendingAction(title: "Put \(cur.short(topUp)) into \(f.name)?", message: "From your own cash. It buys about \(Int((topUp / max(1, f.burn)).rounded())) more weeks of runway; your share does not change.", button: "Put it in") {
                                let ok = store.act { $0.putMoneyIntoStartup(startupID: f.id, amount: topUp) } ?? false
                                store.show(ok ? "\(cur.short(topUp)) put in." : "Not enough cash.", tone: ok ? "good" : "warn")
                            }
                        }.buttonStyle(SmallOutlineButtonStyle())
                        if let p = f.product {
                            Button("− builder") {
                                store.act { $0.changeBuilders(startupID: f.id, by: -1) }
                                store.show(p.builders > 0 ? "One builder fewer: slower work, lower costs." : "No builders left to let go.", tone: "n")
                            }.buttonStyle(SmallOutlineButtonStyle()).disabled(p.builders == 0)
                            Button("+ builder") {
                                store.act { $0.changeBuilders(startupID: f.id, by: 1) }
                                store.show(p.builders < 10 ? "One more builder: faster work, higher monthly cost." : "Ten builders is the most.", tone: "n")
                            }.buttonStyle(SmallOutlineButtonStyle()).disabled(p.builders >= 10)
                            Button(p.selfHours > 0 ? "Stop working on it" : "Work on it yourself") {
                                let ok = store.act { $0.toggleOwnerHoursOnProduct(startupID: f.id) } ?? false
                                store.show(ok ? (p.selfHours > 0 ? "You stopped working on the product." : "You now put your free hours into the product.") : "You cannot build this product yourself.", tone: ok ? "good" : "warn")
                            }.buttonStyle(SmallOutlineButtonStyle())
                        }
                        Button("Shut down") {
                            pending = PendingAction(title: "Shut down \(f.name)?", message: "The team goes and the product stops. What cash is left comes back after costs; your stake is lost and it counts as a failure.", button: "Shut down", destructive: true) {
                                let back = store.act { $0.shutDownStartup(startupID: f.id) } ?? nil
                                store.show(back.map { "Shut down. \(cur.short($0)) comes back to you." } ?? "It was already closed.", tone: "n")
                            }
                        }.buttonStyle(SmallOutlineButtonStyle())
                    }
                }
                if let p = f.product, p.ready {
                    let users = engine.companiesThatCanUseProduct(startupID: f.id)
                    if !users.isEmpty {
                        Text("Use it in your companies").capsLabel(Theme.ivoryFaint).padding(.top, 4)
                        ForEach(users, id: \.company.id) { c in
                            let using = p.usedBy.contains(c.company.id)
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.company.name).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                                    Text(c.effect.summary).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer()
                                Button(using ? "Stop" : "Use") {
                                    let ok = store.act { $0.toggleProductUse(startupID: f.id, companyID: c.company.id) } ?? false
                                    store.show(ok ? (using ? "\(c.company.name) stopped using it." : "\(c.company.name) now uses it.") : "Not possible right now.", tone: ok ? "good" : "warn")
                                }.buttonStyle(SmallOutlineButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .confirmAction($pending)
    }

    private func productLine(_ p: Startups.Product, _ cur: Currency) -> String {
        let phase = p.phase == "live" ? "On sale" : p.phase == "beta" ? "Being tested" : "Being built"
        var parts = ["\(phase) \(Int((p.progress * 100).rounded()))%", "\(p.builders) builder\(p.builders == 1 ? "" : "s")"]
        if p.selfHours > 0 { parts.append("you help") }
        if p.customers > 0 { parts.append("\(Int(p.customers)) customers") }
        if p.revenueWeekly > 0 { parts.append("\(cur.short(p.revenueWeekly)) a week") }
        return parts.joined(separator: " · ")
    }
}

/// Found a startup: sector, product, how customers pay, who builds it, how much seed money; the plan (runway, time to a product) before deciding.
private struct FoundStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var sectorID = StartupProducts.sectors.first?.id ?? ""
    @State private var productID = ""
    @State private var modelID = ""
    @State private var who = "c2"
    @State private var seed = 1.0

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let sec = StartupProducts.sector(sectorID) {
                    let cur = e.homeCurrency
                    let product = sec.products.first { $0.id == productID } ?? sec.products[0]
                    let model = sec.models.first { $0.id == modelID } ?? sec.models[0]
                    let whoNow = who == "self" && !sec.canBuildYourself ? "c2" : who
                    let plan = e.startupPlan(sector: sec.id, who: whoNow, seedMultiple: seed)
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        LedgerSection("Sector") {
                            Picker("Sector", selection: $sectorID) { ForEach(StartupProducts.sectors) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                            Text("Capital need \(sec.capitalNeed) of 4 · built by \(sec.builders)" + (sec.canBuildYourself ? " · you can build it yourself" : "")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        LedgerSection("Product and how customers pay") {
                            Picker("Product", selection: Binding(get: { product.id }, set: { productID = $0 })) { ForEach(sec.products, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                            Picker("Model", selection: Binding(get: { model.id }, set: { modelID = $0 })) { ForEach(sec.models, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                        }
                        LedgerSection("Who builds it") {
                            Picker("Builders", selection: $who) {
                                if sec.canBuildYourself { Text("You").tag("self") }
                                Text("2 builders").tag("c2")
                                Text("4 builders").tag("c4")
                            }.pickerStyle(.segmented)
                            Picker("Seed money", selection: $seed) { Text("Lean").tag(1.0); Text("Double").tag(2.0); Text("Four times").tag(4.0) }.pickerStyle(.segmented)
                        }
                        if let p = plan {
                            KeyFigures(items: [
                                .init(label: "Seed money", value: cur.short(p.seed), tint: Payments.liquid(e.state) < p.seed ? Theme.loss : Theme.ivory, sub: "from your cash"),
                                .init(label: "Builders", value: p.builders == 0 ? "You" : "\(p.builders)", sub: p.builders == 0 ? "your free hours" : "\(cur.short(p.buildersMonthly)) a month"),
                                .init(label: "Runway", value: "\(p.runwayWeeks) wk"),
                                .init(label: "Test version", value: p.weeksToTest.map { "\($0) wk" } ?? "Never", tint: p.weeksToTest == nil ? Theme.loss : Theme.ivory),
                                .init(label: "On sale", value: p.weeksToSell.map { "\($0) wk" } ?? "Never", tint: p.weeksToSell == nil ? Theme.loss : Theme.ivory),
                                .init(label: "Investors", value: Funding.interestWord(p.interest).word),
                            ])
                            Text("Risk: most startups fail and the seed money is lost. Each round brings money in but makes your share smaller. If the runway ends before the product sells, raise a round or put money in.")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                            Button("Found it for \(cur.short(p.seed))") {
                                switch store.act({ $0.foundStartup(name: nil, sector: sec.id, product: product.id, model: model.id, who: whoNow, seedMultiple: seed) }) {
                                case .ok?: Haptics.success(); store.show("Founded. Build the product, then raise a round.", tone: "good"); dismiss()
                                case .notEnoughMoney(let need)?: Haptics.warning(); store.show("You need \(cur.short(need)) in cash.", tone: "warn")
                                default: store.show("That sector is not available.", tone: "warn")
                                }
                            }.buttonStyle(GoldButtonStyle())
                        }
                    }
                    .padding(Theme.Space.margin)
                }
            }
            .ledgerBackground()
            .navigationTitle("Found a startup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: sectorID) { _, _ in productID = ""; modelID = "" }
        }
    }
}

// MARK: Backing startups

private struct BackedStartups: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.homeCurrency
        let pitches = engine.startupPitchesOnOffer
        let stakes = engine.startupStakes
        let minimum = cur.scaledPrice(Startups.minimumInvestment)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection(title: "Your stakes", trailing: { if !stakes.isEmpty { Text("\(stakes.filter { $0.live }.count) live").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) } }) {
                VStack(alignment: .leading, spacing: 0) {
                    if stakes.isEmpty { Text("You hold no stake in someone else's startup.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(Array(stakes.enumerated()), id: \.element.id) { n, st in
                        if n > 0 { Hairline() }
                        stakeRow(st, cur)
                    }
                }
            }
            LedgerSection(title: "Pitches", trailing: { Text("new ones every four weeks").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    if pitches.isEmpty { Text("No founder is pitching right now.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(Array(pitches.enumerated()), id: \.element.id) { n, p in
                        if n > 0 { Hairline() }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(p.name).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                                Spacer()
                                Text(p.sector).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Text(p.blurb).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                            Text("Raising \(cur.short(p.raise)) at \(cur.short(p.preMoney)) before the money · team \(p.team), market \(p.market), traction \(p.traction)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            HStack {
                                ForEach(cheques(p, minimum), id: \.self) { amt in
                                    Button(cur.short(amt)) { confirmInvest(p, amt, cur) }.buttonStyle(SmallOutlineButtonStyle())
                                }
                            }
                        }.padding(.vertical, 8)
                    }
                    Text("The smallest cheque is \(cur.short(minimum)). Twenty percent or more brings a board seat, where you can help the team.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 4)
                }
            }
        }
        .confirmAction($pending)
    }

    private func cheques(_ p: Startups.Pitch, _ minimum: Double) -> [Double] {
        var out: [Double] = []
        for f in [0.1, 0.25, 0.5, 1.0] {
            let a = (p.raise * f / 10000).rounded() * 10000
            if a >= minimum, !out.contains(a) { out.append(a) }
        }
        return out
    }

    private func confirmInvest(_ p: Startups.Pitch, _ amt: Double, _ cur: Currency) {
        let pct = p.postMoney > 0 ? amt / p.postMoney * 100 : 0
        pending = PendingAction(title: "Invest \(cur.short(amt)) in \(p.name)?",
                                message: "You get about \(String(format: "%.1f", pct))% of it" + (pct >= 20 ? " and a board seat" : "") + ". The money is locked until a sale or exit; later rounds make your share smaller, and most young companies fail.",
                                button: "Invest") {
            switch store.act({ $0.investInStartup(pitchID: p.id, amount: amt) }) {
            case .ok?: Haptics.success(); store.show("You invested \(cur.short(amt)) in \(p.name).", tone: "good")
            case .tooSmall?: store.show("They want a bigger cheque.", tone: "warn")
            case .notEnoughMoney?: Haptics.warning(); store.show("Not enough cash.", tone: "warn")
            default: store.show("The round has closed.", tone: "warn")
            }
        }
    }

    private func stakeRow(_ st: Startups.Stake, _ cur: Currency) -> some View {
        let gain = st.value - st.invested
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(st.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text("\(st.sector) · \(st.live ? st.stageName : st.failed ? "Failed" : "Sold") · \(String(format: "%.1f", st.ownership))%" + (st.boardSeat ? " · board seat" : "")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(cur.short(st.value)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text((gain >= 0 ? "+" : "−") + cur.short(abs(gain)) + " on \(cur.short(st.invested))").font(.system(size: 11)).foregroundStyle(Theme.change(gain))
                }
            }
            if st.live {
                HStack {
                    if st.boardSeat {
                        Button("Help the team") {
                            let ok = store.act { $0.helpStartupOnBoard(stakeID: st.id) } ?? false
                            store.show(ok ? "You spent time with the team." : "You helped recently.", tone: ok ? "good" : "n")
                        }.buttonStyle(SmallOutlineButtonStyle())
                    }
                    ForEach([0.5, 1.0], id: \.self) { f in
                        Button(f == 1 ? "Sell all" : "Sell half") {
                            pending = PendingAction(title: f == 1 ? "Sell your stake in \(st.name)?" : "Sell half your stake in \(st.name)?",
                                                    message: "A buyer of private shares pays below the paper value of about \(cur.short(st.value * f)). A gain is taxed.", button: "Sell") {
                                let v = store.act { $0.sellStartupStake(stakeID: st.id, fraction: f) } ?? 0
                                store.show(v > 0 ? "Sold for \(cur.short(v))." : "No buyer.", tone: v > 0 ? "good" : "warn")
                            }
                        }.buttonStyle(SmallOutlineButtonStyle())
                    }
                }
            }
        }.padding(.vertical, 8)
    }
}

// MARK: Private equity

private struct PrivateEquityPart: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.homeCurrency
        let funds = engine.privateEquityFunds
        let offers = engine.privateEquityOffersOnTable
        let worth = engine.netWorth.total
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection("Your funds") {
                VStack(alignment: .leading, spacing: 0) {
                    if funds.isEmpty { Text("You have not committed to a fund.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(Array(funds.enumerated()), id: \.element.id) { n, f in
                        if n > 0 { Hairline() }
                        fundRow(f, cur)
                    }
                }
            }
            LedgerSection(title: "Raising money this year", trailing: { Text("a new set each year").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    if offers.isEmpty { Text("No fund is raising money right now.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(Array(offers.enumerated()), id: \.element.id) { n, o in
                        if n > 0 { Hairline() }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(o.name).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                                Spacer()
                                Text(PrivateEquity.styles[o.style]?.name ?? o.style).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Text(o.description).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                            Text("Manager's record: \(o.trackRecord) · minimum \(cur.short(o.minimum))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            HStack {
                                ForEach([1.0, 2.0, 4.0], id: \.self) { m in
                                    let amt = o.minimum * m
                                    Button("Commit \(cur.short(amt))") { confirmCommit(o, amt, cur) }.buttonStyle(SmallOutlineButtonStyle()).opacity(worth >= amt * 1.5 ? 1 : 0.45)
                                }
                            }
                        }.padding(.vertical, 8)
                    }
                    Text("A fund takes investors worth at least 1.5 times the commitment (you: \(cur.short(worth))). It calls the money over four years, charges 2% a year and a fifth of the profit above 8% a year, pays back from year four and winds up after ten. Missing a capital call costs half your stake.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
            }
        }
        .confirmAction($pending)
        .onAppear(perform: refreshOffers)
    }

    /// The funds raising money are drawn once per calendar year when you look, as in the original.
    private func refreshOffers() {
        guard let e = store.engine else { return }
        let y = GameCalendar.year(week: e.state.week)
        if e.state.rest["pe56"]?["y"].int != y { store.act { _ = $0.privateEquityOffers() } }
    }

    private func confirmCommit(_ o: PrivateEquity.Offer, _ amt: Double, _ cur: Currency) {
        pending = PendingAction(title: "Commit \(cur.short(amt)) to \(o.name)?",
                                message: "Nothing is paid today: the fund calls the money over the next four years and you must have it ready each time. Fees about \(cur.short(amt * 0.02)) a year while it invests. Money comes back from year four; the value can fall, venture funds most.",
                                button: "Commit") {
            switch store.act({ $0.commitToFund(offerID: o.id, amount: amt) }) {
            case .ok?: Haptics.success(); store.show("Committed \(cur.short(amt)) to \(o.name).", tone: "good")
            case .tooSmall?: store.show("Below the fund's minimum.", tone: "warn")
            case .notRichEnough?: Haptics.warning(); store.show("The fund only takes investors worth at least 1.5 times the commitment.", tone: "warn")
            default: store.show("The fund has closed.", tone: "warn")
            }
        }
    }

    private func fundRow(_ f: PrivateEquity.Fund, _ cur: Currency) -> some View {
        let year = (engine.state.week - f.startWeek) / 52 + 1
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text("\(PrivateEquity.styles[f.style]?.name ?? f.style) · " + (f.live ? "year \(year) of 10" : f.sold ? "sold" : "wound up")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Text(String(format: "%.2f×", f.live ? f.multiple : f.finalMultiple)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.change((f.live ? f.multiple : f.finalMultiple) - 1))
            }
            if f.live {
                KeyFigures(items: [
                    .init(label: "Committed", value: cur.short(f.committed), sub: f.toBeCalled > 0 ? "\(cur.short(f.toBeCalled)) still to call" : "all called"),
                    .init(label: "Value now", value: cur.short(f.nav)),
                    .init(label: "Paid back", value: cur.short(f.distributed)),
                ])
                let price = engine.secondaryPrice(fundID: f.id)
                Button("Sell on the secondary market · \(cur.short(price))") {
                    pending = PendingAction(title: "Sell your stake in \(f.name)?",
                                            message: "A buyer pays \(cur.display(price)), \(Int((engine.secondaryDiscount(fundID: f.id) * 100).rounded()))% below its value, and takes over the capital calls still to come.",
                                            button: "Sell") {
                        let v = store.act { $0.sellFundStake(fundID: f.id) } ?? nil
                        store.show(v.map { "Stake sold for \(cur.short($0))." } ?? "No buyer for the stake.", tone: v == nil ? "warn" : "good")
                    }
                }.buttonStyle(SmallOutlineButtonStyle())
            }
        }.padding(.vertical, 8)
    }
}

// MARK: Stakes in groups

private struct GroupStakesPart: View {
    var engine: GameEngine

    var body: some View {
        let cur = engine.homeCurrency
        let big = engine.bigMeetingStakes
        let groups = engine.groupStakes
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection("From the big meeting") {
                VStack(alignment: .leading, spacing: 0) {
                    if big.isEmpty { Text("No stake yet. Owners of large groups offer stakes at the big meeting from time to time; the offer shows above when it comes.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
                    ForEach(Array(big.enumerated()), id: \.element.id) { n, s in
                        FlatRow(label: s.name, value: cur.short(s.value), sub: "\(Int(s.pct))% · \(cur.short(s.yearlyProfitShare)) a year profit share", rule: n > 0)
                    }
                }
            }
            LedgerSection("In rival groups") {
                VStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty { Text("You hold no shares in a rival group. Offers to buy in come to the Inbox.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(Array(groups.enumerated()), id: \.element.id) { n, s in
                        let gain = s.value - s.cost
                        FlatRow(label: s.name, value: cur.short(s.value), sub: "\(Int((s.ownership * 100).rounded()))% since \(GameCalendar.dateString(week: s.sinceWeek)) · " + (gain >= 0 ? "+" : "−") + cur.short(abs(gain)) + " on cost", tint: Theme.ivory, rule: n > 0)
                    }
                }
            }
        }
    }
}

// MARK: Software of your own

/// A web-development company can build a software product: coders, your own hours, how customers pay, what your own companies pay.
private struct SoftwarePart: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var type = SoftwareProducts.types.first?.id ?? ""
    @State private var model = "sub"
    @State private var pending: PendingAction?

    var body: some View {
        let builders = engine.state.companies.filter { SoftwareProducts.canBuild($0) || (engine.softwareProduct(companyID: $0.id) != nil && $0.status.isLive) }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if builders.isEmpty {
                LedgerSection("Software of your own") {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("A web-development company of yours can build software, sell it to customers and let your own companies use it instead of a bought licence. You have no open web-development company.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                        Button("Start a company") { store.showNewCompany = true; store.tab = .company }.buttonStyle(SmallOutlineButtonStyle())
                    }
                }
            }
            ForEach(builders) { co in
                if let p = engine.softwareProduct(companyID: co.id) { product(co, p) } else { start(co) }
            }
        }
        .confirmAction($pending)
    }

    private func start(_ co: Company) -> some View {
        let cur = engine.currency(for: co)
        let coder = cur.scaledPrice(65000) / 12
        return LedgerSection(title: co.name, trailing: { Text("no product yet").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Picker("Kind", selection: $type) { ForEach(SoftwareProducts.types, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Picker("Customers pay", selection: $model) { ForEach(SoftwareProducts.models, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Text("List price \(cur.short(SoftwareProducts.listPrice(model, scale: cur.scaledPrice)))\(model == "once" ? " once" : " a year") · one coder at about \(cur.short(coder)) a month, paid by \(co.name). A test version comes at half way; your companies can try it from the equipment shop.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                Button("Start building") {
                    let name = SoftwareProducts.types.first { $0.id == type }?.name ?? type
                    pending = PendingAction(title: "Build \(name) software in \(co.name)?", message: "It starts with one coder at about \(cur.short(coder)) a month from the company's cash, until you change the team. Nothing sells until it is published.", button: "Start") {
                        let ok = store.act { $0.startSoftware(companyID: co.id, type: type, model: model) } ?? false
                        store.show(ok ? "\(co.name) has started building it." : "\(co.name) cannot start a product now (it must be open).", tone: ok ? "good" : "warn")
                    }
                }.buttonStyle(SmallGoldButtonStyle())
            }
        }
    }

    private func product(_ co: Company, _ p: SoftwareProducts.Product) -> some View {
        let cur = engine.currency(for: co)
        let coder = cur.scaledPrice(65000) / 12
        let phase = p.phase == .live ? "On sale" : p.phase == .beta ? "Test version" : "Being built"
        return LedgerSection(title: p.name, trailing: { Text(co.name).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                KeyFigures(items: [
                    .init(label: "Stage", value: phase, sub: p.phase == .live ? "" : "\(Int((p.progress * 100).rounded()))% done"),
                    .init(label: "Customers", value: "\(p.customers)"),
                    .init(label: "Sales", value: cur.short(p.weeklyRevenue), sub: "last week"),
                    .init(label: "Team", value: "\(p.coders) coder\(p.coders == 1 ? "" : "s")", sub: "\(cur.short(Double(p.coders) * coder)) a month"),
                    .init(label: "Price", value: cur.short(p.price), sub: p.modelName),
                    .init(label: "Your companies pay", value: "\(p.internalPercent)%", sub: "of list price"),
                ])
                HStack {
                    Button("− coder") { store.act { $0.setSoftwareCoders(companyID: co.id, coders: p.coders - 1) }; store.show("Team: \(max(0, p.coders - 1)) coders.", tone: "n") }.buttonStyle(SmallOutlineButtonStyle()).disabled(p.coders == 0)
                    Button("+ coder") { store.act { $0.setSoftwareCoders(companyID: co.id, coders: p.coders + 1) }; store.show("Team: \(min(10, p.coders + 1)) coders, about \(cur.short(coder)) a month more.", tone: "n") }.buttonStyle(SmallOutlineButtonStyle()).disabled(p.coders >= 10)
                    Button(p.selfHours > 0 ? "Stop coding" : "Code yourself") {
                        store.act { $0.setSoftwareSelfCoding(companyID: co.id, on: p.selfHours == 0) }
                        store.show(p.selfHours > 0 ? "You stopped coding on it." : "You code 20 hours a week on it.", tone: "n")
                    }.buttonStyle(SmallOutlineButtonStyle())
                }
                HStack {
                    Text("Customers pay").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    Spacer()
                    Menu(p.modelName) {
                        ForEach(SoftwareProducts.models, id: \.id) { m in
                            Button(m.name) { store.act { $0.setSoftwareModel(companyID: co.id, model: m.id) }; store.show("Customers now pay: \(m.name.lowercased()).", tone: "n") }
                        }
                    }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                }
                HStack {
                    Text("Your companies pay").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    Spacer()
                    ForEach([0, 50, 100], id: \.self) { pct in
                        Button("\(pct)%") { store.act { $0.setSoftwareInternalPercent(companyID: co.id, percent: pct) } }
                            .buttonStyle(SmallOutlineButtonStyle()).opacity(p.internalPercent == pct ? 1 : 0.5)
                    }
                }
            }
        }
    }
}
