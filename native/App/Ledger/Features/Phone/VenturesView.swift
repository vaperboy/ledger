import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Ventures (Projects > Ventures): the startups you found (build, raise, run out of runway), the stakes you already hold in startups, private equity
/// funds and groups (what they are worth), and software of your own built by a web-development company. Buying and selling stakes and selling
/// a company live in Group > Ownership. Logic: `Startups`, `PrivateEquity`, `GroupDeals`, `SoftwareProducts`.
struct VenturesContent: View {
    enum Part: String, CaseIterable, Hashable, Identifiable {
        var id: String { rawValue }
        case founded = "Your startups", backing = "Backing startups", funds = "Private equity", groups = "Stakes in groups", software = "Software" }
    @EnvironmentObject var store: GameStore
    /// The phone app lists pitches and stakes itself (`VenturesFeedApp`); it hides the "Backing startups" row and the summary here.
    var hidesBacking = false
    @State private var opened: Part?
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if !hidesBacking { VenturesSummary(engine: e) }
                venturesTable(e)
            }
            .navigationDestination(item: $opened) { (p: Part) in
                SettingsPage(title: p.rawValue, subtitle: "Ventures", tab: .phone) { partContent(p, e) }
            }
        }
    }

    @ViewBuilder private func partContent(_ p: Part, _ e: GameEngine) -> some View {
        switch p {
        case .founded: FoundedStartups(engine: e)
        case .backing: BackedStartups(engine: e)
        case .funds: PrivateEquityPart(engine: e)
        case .groups: GroupStakesPart(engine: e)
        case .software: SoftwarePart(engine: e)
        }
    }

    /// One row per kind of venture; each opens its own workflow as a page. A red count shows offers waiting on your startups.
    private func venturesTable(_ e: GameEngine) -> some View {
        let offers: Int = badge(e, .founded)
        let parts: [Part] = Part.allCases.filter { !(hidesBacking && $0 == .backing) }
        return LedgerSection("Start or manage") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.element) { (n: Int, p: Part) in
                    if n > 0 { Hairline() }
                    LedgerRow(title: p.rawValue, subtitle: note(p), value: value(e, p), valueTint: p == .founded && offers > 0 ? Theme.caution : nil,
                              badge: p == .founded ? offers : 0, identifier: "ventures-part-\(p.id)") { opened = p }
                }
            }
        }
    }

    private func note(_ p: Part) -> String {
        switch p {
        case .founded: return "Build, raise money, run out of runway or exit"
        case .backing: return "Your stakes and the teams you help"
        case .funds: return "Your funds and what they are worth"
        case .groups: return "Stakes from the big meeting"
        case .software: return "Products built by a web-development company"
        }
    }

    private func value(_ e: GameEngine, _ p: Part) -> String {
        switch p {
        case .founded:
            let n: Int = e.foundedStartups.filter { $0.live }.count
            let offers: Int = badge(e, .founded)
            return offers > 0 ? "\(n) running, \(offers) offer\(offers == 1 ? "" : "s")" : n == 0 ? "None" : "\(n) running"
        case .backing: let n: Int = e.startupStakes.filter { $0.live }.count; return n == 0 ? "None" : "\(n) held"
        case .funds: let n: Int = e.privateEquityFunds.filter { $0.live }.count; return n == 0 ? "None" : "\(n) held"
        case .groups: let n: Int = e.bigMeetingStakes.count + e.groupStakes.count; return n == 0 ? "None" : "\(n) held"
        case .software: return ""
        }
    }

    private func badge(_ e: GameEngine, _ p: Part) -> Int {
        switch p {
        case .founded: return e.foundedStartups.filter { $0.live }.reduce(0) { $0 + $1.offers.count }
        default: return 0
        }
    }

}

/// What the ventures are worth, as the screen's one figure: your share of your own startups, stakes in other founders' startups, funds and
/// group stakes. The line under it says how the stakes stand against what went in, and what the total is made of. No box.
struct VenturesSummary: View {
    var engine: GameEngine
    @Environment(\.outsidePalette) private var P
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    var body: some View {
        let e: GameEngine = engine
        let cur = e.homeCurrency
        let founded = e.foundedStartups.filter { $0.live }
        let stakes = e.startupStakes.filter { $0.live }
        let funds = e.privateEquityFunds.filter { $0.live }
        let groups: Double = e.bigMeetingStakes.reduce(0) { $0 + $1.value } + e.groupStakes.reduce(0) { $0 + $1.value }
        let own: Double = founded.reduce(0) { $0 + $1.valuation * $1.ownership / 100 }
        let held: Double = stakes.reduce(0) { $0 + $1.value }
        let invested: Double = stakes.reduce(0) { $0 + $1.invested }
        let fundValue: Double = funds.reduce(0) { $0 + $1.nav }
        let total: Double = own + held + fundValue + groups
        let gain: Double = held - invested
        var parts: [String] = []
        if !founded.isEmpty { parts.append(founded.count == 1 ? "1 startup of your own" : "\(founded.count) startups of your own") }
        if !stakes.isEmpty { parts.append(stakes.count == 1 ? "1 stake" : "\(stakes.count) stakes") }
        if !funds.isEmpty { parts.append(funds.count == 1 ? "1 fund" : "\(funds.count) funds") }
        if groups > 0 { parts.append("group stakes") }
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Ventures portfolio").capsLabel(P.inkFaint)
            Text(total > 0 ? cur.tidyShort(total) : "Nothing yet")
                .font(.system(size: heroSize, weight: .medium, design: .serif).monospacedDigit())
                .foregroundStyle(P.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
            if !stakes.isEmpty {
                Text((gain >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(gain)) + " on \(cur.tidyShort(invested)) put into startups")
                    .textStyle(.body, tint: P.change(gain), numeric: true)
            }
            Text(parts.isEmpty ? "Found a startup, back a founder or buy into a fund." : parts.joined(separator: " \u{00B7} "))
                .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Your startups

private struct FoundedStartups: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @Environment(Entitlements.self) private var ent
    @State private var founding = false
    @State private var showPast = false

    var body: some View {
        let all = engine.foundedStartups
        let live = all.filter { $0.live }
        let past = all.filter { !$0.live }
        let r = engine.founderRecord
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your record: \(r.exits) exit\(r.exits == 1 ? "" : "s") · \(r.fails) failure\(r.fails == 1 ? "" : "s")").textStyle(.caption, tint: Theme.inkFaint)
                Spacer()
                HStack(spacing: Theme.Space.s) {
                    ProMark(feature: .ventures)
                    Button("Found a startup") { ent.run(.ventures, "Found a startup") { founding = true } }.buttonStyle(SecondaryButtonStyle(size: .compact))
                }
            }
            if live.isEmpty {
                Text("You run no startup. Found one: you put in the seed money, hire builders, and raise rounds from investors as the product takes shape. Most fail; a few sell for many times what went in.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(live) { f in FoundedCard(engine: engine, startup: f) }
            if !past.isEmpty {
                Button(showPast ? "Hide past startups" : "Past startups (\(past.count))") { showPast.toggle() }.buttonStyle(SecondaryButtonStyle(size: .compact))
                if showPast {
                    ForEach(past) { f in
                        FlatRow(label: f.name, value: f.exited ? engine.homeCurrency.tidyShort(f.exitValue) : "Closed", sub: "\(f.sectorName) · \(f.stageName)", tint: f.exited ? Theme.gain : Theme.ivoryFaint)
                    }
                }
            }
        }
        .centerSheet(isPresented: $founding, title: "Found a startup", category: .medium, tone: .investment) { FoundStartupSheet() }
    }
}

private struct FoundedCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var f: Startups.Founded
    @State private var pending: PendingAction?
    @State private var launching = false

    init(engine: GameEngine, startup: Startups.Founded) { self.engine = engine; self.f = startup }

    var body: some View {
        let cur = engine.homeCurrency
        let monthlyBurn = f.burn * 52 / 12
        let interest = engine.startupInterest(startupID: f.id)
        let topUp = cur.scaledPrice(100000)
        CardSection(title: f.name, trailing: { Text("\(f.productName) · \(f.stageName)").textStyle(.caption, tint: Theme.inkFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                FigureCard(items: [
                    .init(label: "You own", value: "\(Int(f.ownership.rounded()))%", sub: "worth \(cur.tidyShort(f.valuation * f.ownership / 100))"),
                    .init(label: "Cash", value: cur.tidyShort(f.cash), tint: f.runwayWeeks < 8 ? Theme.loss : Theme.ink, sub: "\(f.runwayWeeks) weeks of runway"),
                    .init(label: "Burn", value: cur.tidyShort(monthlyBurn), sub: "a month"),
                ])
                if let p = f.product {
                    Text(productLine(p, cur)).textStyle(.caption)
                }
                Text("Investors: \(interest.word)").textStyle(.caption)
                if f.runwayWeeks < 8 { Text("Runway is short: raise a round or put money in, or it closes when the cash runs out.").textStyle(.caption, tint: Theme.warn) }
                ForEach(f.offers) { o in
                    let terms: CapTable.DealTerms? = engine.fundingOfferTerms(companyID: f.id, offerIndex: o.id)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("\(o.name) offers \(cur.tidyShort(o.amount)) for \(Int(o.pct.rounded()))%").textStyle(.headline, tint: Theme.accent)
                        Text("\(o.says) Values it at \(cur.tidyShort(o.preMoney)) before the money, \(terms.map { cur.tidyDisplay($0.pricePerShare) } ?? "") a share, \(terms.map { String($0.sharesIssued) } ?? "") new shares.").textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Accept") {
                                pending = PendingAction(title: "Take \(cur.tidyShort(o.amount)) for \(Int(o.pct.rounded()))%?",
                                                        message: DealText.describe(terms, cur, companyName: f.name),
                                                        button: "Close the round", destructive: true, tone: .investment, icon: "chart.pie") {
                                    let ok = store.act { $0.acceptStartupRound(startupID: f.id, index: o.id) } ?? false
                                    store.show(ok ? "Round closed: \(cur.tidyShort(o.amount)) in for \(Int(o.pct.rounded()))%." : "That offer is no longer on the table.", tone: ok ? "good" : "warn")
                                }
                            }.buttonStyle(SecondaryButtonStyle(size: .compact))
                            Button("Decline") { store.settle(store.act { $0.declineStartupRound(startupID: f.id, index: o.id) }, "Offer declined.", same: "That offer had already gone.") }.buttonStyle(SecondaryButtonStyle(size: .compact))
                        }
                    }.padding(.vertical, Theme.Space.xs)
                }
                WrapRow {
                    Group {
                        Button("Raise a round") {
                            switch store.act({ $0.pitchStartupRound(startupID: f.id) }) {
                            case .offers(let n)?: Haptics.success(); store.show("\(n) investor\(n == 1 ? "" : "s") made an offer.", tone: "good")
                            case .none?: store.show("No investor bit this time.", tone: "warn")
                            case .tooSoon(let w)?: store.show("Too soon to pitch again: \(w) week\(w == 1 ? "" : "s") to go.", tone: "n")
                            default: store.show("This startup is no longer running.", tone: "warn")
                            }
                        }.buttonStyle(SecondaryButtonStyle(size: .compact))
                        Button("Put in \(cur.tidyShort(topUp))") {
                            pending = PendingAction(title: "Put \(cur.tidyShort(topUp)) into \(f.name)?", message: "From your own cash. It buys about \(Int((topUp / max(1, f.burn)).rounded())) more weeks of runway; your share does not change.", button: "Put it in", amount: topUp, currency: cur, tone: .investment, icon: "plus.circle") {
                                let ok = store.act { $0.putMoneyIntoStartup(startupID: f.id, amount: topUp) } ?? false
                                store.show(ok ? "\(cur.tidyShort(topUp)) put in." : "Not enough cash.", tone: ok ? "good" : "warn")
                            }
                        }.buttonStyle(SecondaryButtonStyle(size: .compact))
                        if let p = f.product {
                            Button("− builder") {
                                store.settle(store.act { $0.changeBuilders(startupID: f.id, by: -1) }, "One builder let go (notice and severance paid by the company): slower work, lower wages.")
                            }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(f.developers == 0)
                            Button("+ builder") {
                                store.settle(store.act { $0.changeBuilders(startupID: f.id, by: 1) }, "A builder hired at market pay: faster work, higher payroll.")
                            }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(f.developers >= 10)
                            if p.phase == "ready" {
                                Button("Launch it") { launching = true }.buttonStyle(PrimaryButtonStyle(size: .compact))
                            }
                            if p.phase == "live" {
                                Button("Change the price") { launching = true }.buttonStyle(SecondaryButtonStyle(size: .compact))
                            }
                            Button("Open the company") { store.openCompany(f.companyID) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                            Button(p.selfHours > 0 ? "Stop working on it" : "Work on it yourself") {
                                let ok = store.act { $0.toggleOwnerHoursOnProduct(startupID: f.id) } ?? false
                                store.show(ok ? (p.selfHours > 0 ? "You stopped working on the product." : "You now put your free hours into the product.") : "You cannot build this product yourself.", tone: ok ? "good" : "warn")
                            }.buttonStyle(SecondaryButtonStyle(size: .compact))
                        }
                        Button("Shut down") {
                            pending = PendingAction(title: "Shut down \(f.name)?", message: "The team goes and the product stops. What cash is left comes back after costs; your stake is lost and it counts as a failure.", button: "Shut down", destructive: true, tone: .danger, icon: "power") {
                                let back = store.act { $0.shutDownStartup(startupID: f.id) } ?? nil
                                store.show(back.map { "Shut down. \(cur.tidyShort($0)) comes back to you." } ?? "It was already closed.", tone: "n")
                            }
                        }.buttonStyle(SecondaryButtonStyle(size: .compact, tint: Theme.loss))
                    }
                }
                if let p = f.product, p.ready {
                    let users = engine.companiesThatCanUseProduct(startupID: f.id)
                    if !users.isEmpty {
                        Text("Use it in your companies").capsLabel(Theme.inkFaint).padding(.top, Theme.Space.xs)
                        ForEach(users, id: \.company.id) { c in
                            let using = p.usedBy.contains(c.company.id)
                            HStack {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    Text(c.company.name).textStyle(.body)
                                    Text(c.effect.summary.tidyMoney).textStyle(.caption, tint: Theme.inkFaint)
                                }
                                Spacer()
                                Button(using ? "Stop" : "Use") {
                                    let ok = store.act { $0.toggleProductUse(startupID: f.id, companyID: c.company.id) } ?? false
                                    store.show(ok ? (using ? "\(c.company.name) stopped using it." : "\(c.company.name) now uses it.") : "Not possible right now.", tone: ok ? "good" : "warn")
                                }.buttonStyle(SecondaryButtonStyle(size: .compact))
                            }
                        }
                    }
                    if !users.isEmpty || !p.usedBy.isEmpty {
                        HStack(spacing: Theme.Space.m) {
                            Text("Your companies pay").textStyle(.caption)
                            Spacer(minLength: Theme.Space.s)
                            SegmentedPill(items: [0, 50, 100], title: { (pct: Int) -> String in "\(pct)%" },
                                          selection: Binding<Int>(get: { Int(p.internalPrice.rounded()) }, set: { (pct: Int) in
                                              store.act { $0.setProductInternalPrice(startupID: f.id, percent: Double(pct)) }
                                              store.show("Your own companies pay \(pct)% of the list price for \(f.productName.isEmpty ? "the product" : f.productName).", tone: "n")
                                          }))
                                .frame(maxWidth: 200)
                        }
                    }
                    let rivals = engine.rivalTargetsForProduct(startupID: f.id)
                    if !rivals.isEmpty {
                        Text("Sell it to rivals").capsLabel(Theme.inkFaint).padding(.top, Theme.Space.xs)
                        ForEach(rivals) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    Text(r.name).textStyle(.body)
                                    Text(r.alreadyCustomer ? "Already a customer" : r.waitWeeks > 0 ? "Asked recently: try again in \(r.waitWeeks.weeksText)" : "\(Int((r.odds * 100).rounded()))% chance they sign · relationship: \(Words.level(r.relationship, scale: .quality).lowercased())")
                                        .textStyle(.caption, tint: Theme.inkFaint)
                                }
                                Spacer()
                                if !r.alreadyCustomer {
                                    Button("Pitch") {
                                        switch store.act({ $0.pitchProductToRival(startupID: f.id, rivalID: r.id) }) {
                                        case .some(.some(true)): Haptics.success(); store.show("\(r.name) signed up for \(f.name).", tone: "good")
                                        case .some(.some(false)): store.show("\(r.name) said no this time. You can ask again in a few weeks.", tone: "warn")
                                        default: store.show("That pitch is not possible now.", tone: "warn")
                                        }
                                    }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(r.waitWeeks > 0)
                                }
                            }
                        }
                    }
                }
            }
        }
        .confirmAction($pending)
        .centerSheet(isPresented: $launching, title: f.product?.phase == "live" ? "Change the price" : "Launch", category: .medium, tone: .investment) { StartupLaunchSheet(engine: engine, f: f) }
    }

    private func productLine(_ p: Startups.Product, _ cur: Currency) -> String {
        let phase = p.phase == "live" ? "On sale" : p.phase == "ready" ? "Finished, waiting for your launch decision" : p.phase == "beta" ? "Being tested" : "Being built"
        var parts = ["\(phase) \(Int((p.progress * 100).rounded()))%", "\(f.developers) builder\(f.developers == 1 ? "" : "s") on the payroll"]
        if f.teamWanted > f.developers && p.phase != "live" { parts.append("you asked for \(f.teamWanted)") }
        if p.phase == "live" && f.price > 0 { parts.append("\(cur.tidyDisplay(f.price)) each") }
        if p.selfHours > 0 { parts.append("you help") }
        if p.customers > 0 { parts.append("\(Int(p.customers)) customers") }
        if p.revenueWeekly > 0 { parts.append("\(cur.tidyShort(p.revenueWeekly)) a week") }
        return parts.joined(separator: " · ")
    }
}

/// Found a startup: sector, product, how customers pay, who builds it, how much seed money; the plan (runway, time to a product) before deciding.
private struct FoundStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    @State private var sectorID = StartupProducts.sectors.first?.id ?? ""
    @State private var productID = ""
    @State private var modelID = ""
    @State private var who = "c2"
    @State private var seed = 1.0
    @State private var pending: PendingAction?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let e = store.engine, let sec = StartupProducts.sector(sectorID) {
                    let cur = e.homeCurrency
                    let product = sec.products.first { $0.id == productID } ?? sec.products[0]
                    let model = sec.models.first { $0.id == modelID } ?? sec.models[0]
                    let whoNow = who == "self" && !sec.canBuildYourself ? "c2" : who
                    let plan = e.startupPlan(sector: sec.id, who: whoNow, seedMultiple: seed)
                    VStack(alignment: .leading, spacing: PopupSpace.card) {
                        CardSection("Sector") {
                            Picker("Sector", selection: $sectorID) { ForEach(StartupProducts.sectors) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                            Text("Capital need \(sec.capitalNeed) of 4 · built by \(sec.builders)" + (sec.canBuildYourself ? " · you can build it yourself" : "")).popupText(.caption)
                        }
                        CardSection("Product and how customers pay") {
                            Picker("Product", selection: Binding(get: { product.id }, set: { productID = $0 })) { ForEach(sec.products, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                            Picker("Model", selection: Binding(get: { model.id }, set: { modelID = $0 })) { ForEach(sec.models, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                        }
                        CardSection("Who builds it") {
                            let builderChoices: [String] = sec.canBuildYourself ? ["self", "c2", "c4"] : ["c2", "c4"]
                            SegmentedPill(items: builderChoices, title: { $0 == "self" ? "You" : $0 == "c2" ? "2 builders" : "4 builders" }, selection: Binding(get: { whoNow }, set: { who = $0 }))
                            SegmentedPill(items: [1.0, 2.0, 4.0], title: { $0 == 1.0 ? "Lean" : $0 == 2.0 ? "Double" : "Four times" }, selection: $seed)
                        }
                        if let p = plan {
                            FigureCard(items: [
                                .init(label: "Seed money", value: cur.tidyShort(p.seed), tint: Payments.liquid(e.state) < p.seed ? P.loss : P.ink, sub: "from your cash"),
                                .init(label: "Builders", value: p.builders == 0 ? "You" : "\(p.builders)", sub: p.builders == 0 ? "your free hours" : "\(cur.tidyShort(p.buildersMonthly)) a month"),
                                .init(label: "Runway", value: "\(p.runwayWeeks) wk"),
                                .init(label: "Test version", value: p.weeksToTest.map { "\($0) wk" } ?? "Never", tint: p.weeksToTest == nil ? P.loss : P.ink),
                                .init(label: "On sale", value: p.weeksToSell.map { "\($0) wk" } ?? "Never", tint: p.weeksToSell == nil ? P.loss : P.ink),
                                .init(label: "Investors", value: Funding.interestWord(p.interest).word),
                            ])
                            Text("Risk: most startups fail and the seed money is lost. Each round brings money in but makes your share smaller. If the runway ends before the product sells, raise a round or put money in.")
                                .popupText(.caption)
                            Button("Found it for \(cur.tidyShort(p.seed))") {
                                pending = PendingAction(title: "Found a \(sec.name) startup?",
                                                        message: "\(cur.tidyDisplay(p.seed)) of seed money leaves your cash now. Most startups fail and the seed money is lost.",
                                                        button: "Found it for \(cur.tidyShort(p.seed))", amount: p.seed, currency: cur, tone: .investment, icon: "lightbulb") {
                                    switch store.act({ $0.foundStartup(name: nil, sector: sec.id, product: product.id, model: model.id, who: whoNow, seedMultiple: seed) }) {
                                    case .ok?: Haptics.success(); store.show("Founded. Build the product, then raise a round.", tone: "good"); dismiss()
                                    case .notEnoughMoney(let need)?: Haptics.warning(); store.show("You need \(cur.tidyShort(need)) in cash.", tone: "warn")
                                    default: store.show("That sector is not available.", tone: "warn")
                                    }
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        }
                    }
                }
            }
        }
        .confirmAction($pending)
        .onChange(of: sectorID) { _, _ in productID = ""; modelID = "" }
    }
}

// MARK: Backing startups

private struct BackedStartups: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.homeCurrency
        let stakes = engine.startupStakes
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            CardSection(title: "Your stakes", trailing: { if !stakes.isEmpty { Text("\(stakes.filter { $0.live }.count) live").textStyle(.caption, tint: Theme.inkFaint) } }) {
                VStack(alignment: .leading, spacing: 0) {
                    if stakes.isEmpty { Text("You hold no stake in someone else's startup.").textStyle(.caption, tint: Theme.inkFaint) }
                    ForEach(Array(stakes.enumerated()), id: \.element.id) { n, st in
                        if n > 0 { CardLine() }
                        stakeRow(st, cur)
                    }
                }
            }
        }
        .confirmAction($pending)
    }

    private func stakeRow(_ st: Startups.Stake, _ cur: Currency) -> some View {
        let gain = st.value - st.invested
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(st.name).textStyle(.headline)
                    Text("\(st.sector) · \(st.live ? st.stageName : st.failed ? "Failed" : "Sold") · \(String(format: "%.1f", st.ownership))%" + (st.boardSeat ? " · board seat" : "")).textStyle(.caption, tint: Theme.inkFaint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(cur.tidyShort(st.value)).textStyle(.headline, numeric: true)
                    Text((gain >= 0 ? "+" : "−") + cur.tidyShort(abs(gain)) + " on \(cur.tidyShort(st.invested))").textStyle(.caption, tint: Theme.change(gain))
                }
            }
            if st.live {
                HStack {
                    if st.boardSeat {
                        Button("Help the team") {
                            let ok = store.act { $0.helpStartupOnBoard(stakeID: st.id) } ?? false
                            store.show(ok ? "You spent time with the team." : "You helped recently.", tone: ok ? "good" : "n")
                        }.buttonStyle(SecondaryButtonStyle(size: .compact))
                    }
                }
            }
        }.padding(.vertical, Theme.Space.s)
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
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            CardSection("Your funds") {
                VStack(alignment: .leading, spacing: 0) {
                    if funds.isEmpty { Text("You have not committed to a fund.").textStyle(.caption, tint: Theme.inkFaint) }
                    ForEach(Array(funds.enumerated()), id: \.element.id) { n, f in
                        if n > 0 { CardLine() }
                        fundRow(f, cur)
                    }
                }
            }
        }
        .confirmAction($pending)
    }

    private func fundRow(_ f: PrivateEquity.Fund, _ cur: Currency) -> some View {
        let year = (engine.state.week - f.startWeek) / 52 + 1
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(f.name).textStyle(.headline)
                    Text("\(PrivateEquity.styles[f.style]?.name ?? f.style) · " + (f.live ? "year \(year) of 10" : f.sold ? "sold" : "wound up")).textStyle(.caption, tint: Theme.inkFaint)
                }
                Spacer()
                Text(String(format: "%.2f×", f.live ? f.multiple : f.finalMultiple)).textStyle(.headline, tint: Theme.change((f.live ? f.multiple : f.finalMultiple) - 1), numeric: true)
            }
            if f.live {
                FigureCard(items: [
                    .init(label: "Committed", value: cur.tidyShort(f.committed), sub: f.toBeCalled > 0 ? "\(cur.tidyShort(f.toBeCalled)) still to call" : "all called"),
                    .init(label: "Value now", value: cur.tidyShort(f.nav)),
                    .init(label: "Paid back", value: cur.tidyShort(f.distributed)),
                ])
            }
        }.padding(.vertical, Theme.Space.s)
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
            CardSection("From the big meeting") {
                VStack(alignment: .leading, spacing: 0) {
                    if big.isEmpty { Text("No stake held.").textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true) }
                    ForEach(Array(big.enumerated()), id: \.element.id) { n, s in
                        FlatRow(label: s.name, value: cur.tidyShort(s.value), sub: "\(Int(s.pct))% · \(cur.tidyShort(s.yearlyProfitShare)) a year profit share", rule: n > 0)
                    }
                }
            }
            CardSection("In rival groups") {
                VStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty { Text("You hold no shares in a rival group.").textStyle(.caption, tint: Theme.inkFaint) }
                    ForEach(Array(groups.enumerated()), id: \.element.id) { n, s in
                        let gain = s.value - s.cost
                        FlatRow(label: s.name, value: cur.tidyShort(s.value), sub: "\(Int((s.ownership * 100).rounded()))% since \(GameCalendar.dateString(week: s.sinceWeek)) · " + (gain >= 0 ? "+" : "−") + cur.tidyShort(abs(gain)) + " on cost", tint: Theme.ivory, rule: n > 0)
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
                CardSection("Software of your own") {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Button("Start a company") { store.open(.newCompany, on: .company) }.buttonStyle(SecondaryButtonStyle(size: .compact))
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
        return CardSection(title: co.name, trailing: { Text("no product yet").textStyle(.caption, tint: Theme.inkFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Picker("Kind", selection: $type) { ForEach(SoftwareProducts.types, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Picker("Customers pay", selection: $model) { ForEach(SoftwareProducts.models, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Text("List price \(cur.tidyShort(SoftwareProducts.listPrice(model, scale: cur.scaledPrice)))\(model == "once" ? " once" : " a year") · one coder at about \(cur.tidyShort(coder)) a month, paid by \(co.name). A test version comes at half way; your companies can try it from the equipment shop.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                Button("Start building") {
                    let name = SoftwareProducts.types.first { $0.id == type }?.name ?? type
                    pending = PendingAction(title: "Build \(name) software in \(co.name)?", message: "It starts with one coder at about \(cur.tidyShort(coder)) a month from the company's cash, until you change the team. Nothing sells until it is published.", button: "Start", amount: coder, currency: cur, tone: .investment, icon: "chevron.left.forwardslash.chevron.right") {
                        let ok = store.act { $0.startSoftware(companyID: co.id, type: type, model: model) } ?? false
                        store.show(ok ? "\(co.name) has started building it." : "\(co.name) cannot start a product now (it must be open).", tone: ok ? "good" : "warn")
                    }
                }.buttonStyle(SecondaryButtonStyle(size: .compact))
            }
        }
    }

    private func product(_ co: Company, _ p: SoftwareProducts.Product) -> some View {
        let cur = engine.currency(for: co)
        let coder = cur.scaledPrice(65000) / 12
        let phase = p.phase == .live ? "On sale" : p.phase == .beta ? "Test version" : "Being built"
        return CardSection(title: p.name, trailing: { Text(co.name).textStyle(.caption, tint: Theme.inkFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                FigureCard(items: [
                    .init(label: "Stage", value: phase, sub: p.phase == .live ? "" : "\(Int((p.progress * 100).rounded()))% done"),
                    .init(label: "Customers", value: "\(p.customers)"),
                    .init(label: "Sales", value: cur.tidyShort(p.weeklyRevenue), sub: "last week"),
                    .init(label: "Team", value: "\(p.coders) coder\(p.coders == 1 ? "" : "s")", sub: "\(cur.tidyShort(Double(p.coders) * coder)) a month"),
                    .init(label: "Price", value: cur.tidyShort(p.price), sub: p.modelName),
                    .init(label: "Your companies pay", value: "\(p.internalPercent)%", sub: "of list price"),
                ])
                WrapRow(spacing: Theme.Space.s) {
                    Button("− coder") { store.settle(store.act { $0.setSoftwareCoders(companyID: co.id, coders: p.coders - 1) }, "Team: \(max(0, p.coders - 1)) coders.") }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(p.coders == 0)
                    Button("+ coder") { store.settle(store.act { $0.setSoftwareCoders(companyID: co.id, coders: p.coders + 1) }, "Team: \(min(10, p.coders + 1)) coders, about \(cur.tidyShort(coder)) a month more.") }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(p.coders >= 10)
                    Button(p.selfHours > 0 ? "Stop coding" : "Code yourself") {
                        store.act { $0.setSoftwareSelfCoding(companyID: co.id, on: p.selfHours == 0) }
                        store.show(p.selfHours > 0 ? "You stopped coding on it." : "You code 20 hours a week on it.", tone: "n")
                    }.buttonStyle(SecondaryButtonStyle(size: .compact))
                }
                if engine.canRaiseFunding(companyID: co.id) {
                    let wait = engine.weeksUntilNextPitch(companyID: co.id)
                    let ask = engine.suggestedFundingAmount(companyID: co.id)
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text("Raise money for \(co.name)").textStyle(.body)
                            Text(wait > 0 ? "Pitch again in \(wait.weeksText)." : "Investors: \(engine.investorInterest(companyID: co.id).word). Asks for about \(cur.tidyShort(ask)) for new shares.")
                                .textStyle(.caption, tint: wait > 0 ? Theme.warn : Theme.inkFaint)
                        }
                        Spacer(minLength: 8)
                        Button("Pitch") {
                            switch store.act({ $0.pitchToInvestors(companyID: co.id, amount: ask) }) {
                            case .offers(let n)?: Haptics.success(); store.show("\(n) investor\(n == 1 ? "" : "s") made an offer: see the company's Finances.", tone: "good")
                            case .none?: store.show("No investor bit this time.", tone: "warn")
                            case .tooSoon(let w)?: store.show("Too soon to pitch again: \(w.weeksText) to go.", tone: "n")
                            default: store.show("Only a limited company can raise money from investors.", tone: "warn")
                            }
                        }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(wait > 0)
                    }
                }
                HStack {
                    Text("Customers pay").textStyle(.caption)
                    Spacer()
                    Menu(p.modelName) {
                        ForEach(SoftwareProducts.models, id: \.id) { m in
                            Button(m.name) { store.settle(store.act { $0.setSoftwareModel(companyID: co.id, model: m.id) }, "Customers now pay: \(m.name.lowercased()).", same: "Customers already pay that way.") }
                        }
                    }.textStyle(.body, tint: Theme.accent, weight: .medium)
                }
                HStack(spacing: Theme.Space.m) {
                    Text("Your companies pay").textStyle(.caption)
                    Spacer(minLength: Theme.Space.s)
                    SegmentedPill(items: [0, 50, 100], title: { (pct: Int) -> String in "\(pct)%" },
                                  selection: Binding<Int>(get: { p.internalPercent }, set: { (pct: Int) in
                                      store.act { $0.setSoftwareInternalPercent(companyID: co.id, percent: pct) }
                                      store.saved("\(pct)% of the product's capacity goes to your own companies.")
                                  }))
                        .frame(maxWidth: 200)
                }
            }
        }
    }
}


/// The launch decision (and, after launch, the price): the price per customer, a weekly marketing budget, and what to expect. Read from
/// `startupLaunchPreview`; nothing is decided until "Launch". Hiring and firing are in the company's own team screens.
private struct StartupLaunchSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var engine: GameEngine
    var f: Startups.Founded
    @State private var priceStep = 0
    @State private var campaign = 0

    private var launched: Bool { f.product?.phase == "live" }

    var body: some View {
        let cur = engine.homeCurrency
        let steps: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3]
        let base: Double = f.price
        let factor: Double = steps[min(max(0, priceStep), steps.count - 1)]
        let price: Double = base * factor
        let budgets: [Double] = [0, cur.scaledPrice(1000), cur.scaledPrice(3000), cur.scaledPrice(8000)]
        let weekly: Double = budgets[min(max(0, campaign), budgets.count - 1)]
        let funnel: StartupModel.Funnel? = engine.startupLaunchPreview(startupID: f.id, price: price)
        VStack(spacing: 0) {
            Group {
                VStack(alignment: .leading, spacing: PopupSpace.card) {
                    CardSection("Price per customer") {
                        SegmentedPill(items: Array(steps.indices), title: { "\(Int((steps[$0] * 100).rounded()))%" }, selection: $priceStep)
                        Text("\(cur.tidyDisplay(price)) for each customer. 100% is the usual price in this sector; cheaper brings more customers, dearer fewer.").popupText(.caption)
                    }
                    if !launched {
                        CardSection("Marketing each week") {
                            SegmentedPill(items: Array(budgets.indices), title: { $0 == 0 ? "None" : cur.tidyShort(budgets[$0]) }, selection: $campaign)
                            Text("Paid by the company from its own cash, on the ordinary online channel. More awareness brings more customers; it is a real cost.").popupText(.caption)
                        }
                    }
                    if let funnel {
                        FigureCard(items: [
                            .init(label: "New customers", value: String(Int(funnel.newCustomersWeekly.rounded())), sub: "a week, without luck"),
                            .init(label: "Can look after", value: String(Int(funnel.capacity)), sub: "customers with today's team"),
                            .init(label: "Revenue", value: cur.tidyShort(funnel.weeklyRevenueAt), sub: "a week once they join"),
                            .init(label: "Company cash", value: cur.tidyShort(f.cash), sub: "\(f.runwayWeeks) weeks of runway"),
                        ])
                    }
                    Text("Customers beyond what the team can look after leave faster. A support person serves far more customers than a builder; hire one in the company's Team screen.").popupText(.caption)
                    Button(launched ? "Set this price" : "Launch at \(cur.tidyDisplay(price))") { decide(price, weekly) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                }
            }
        }
        .onAppear { priceStep = 2 }
    }

    private func decide(_ price: Double, _ weekly: Double) {
        if launched {
            let ok = store.act { $0.setStartupPrice(startupID: f.id, price: price) } ?? false
            store.show(ok ? "New price set. Customers answer over the coming weeks." : "That price could not be set.", tone: ok ? "good" : "warn")
            if ok { dismiss() }
            return
        }
        switch store.act({ $0.launchStartup(startupID: f.id, price: price, marketingChannel: weekly > 0 ? "google" : nil, marketingWeekly: weekly) }) {
        case .ok?: Haptics.success(); store.show("\(f.name) is launched. Sales start next week.", tone: "good"); dismiss()
        case .notReady?: store.show("The product is not finished yet.", tone: "warn")
        default: store.show("That price does not work.", tone: "warn")
        }
    }
}
