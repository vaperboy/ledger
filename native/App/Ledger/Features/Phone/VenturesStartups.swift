import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Your startups: one row per live startup (stake, cash and the next thing it needs); a row opens its actions in place. Past startups
/// are listed under a toggle. Founding runs in `FoundStartupSheet`.
struct VenturesStartupsSection: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    var engine: GameEngine
    @Binding var open: String?
    @Binding var sheet: VentureSheet?
    @Binding var pending: PendingAction?
    @State private var showPast = false

    var body: some View {
        let all: [Startups.Founded] = engine.foundedStartups
        let live: [Startups.Founded] = all.filter { (f: Startups.Founded) -> Bool in f.live }
        let past: [Startups.Founded] = all.filter { (f: Startups.Founded) -> Bool in !f.live }
        let r = engine.founderRecord
        return LedgerSection(title: "Your startups", trailing: { Text("\(r.exits) exit\(r.exits == 1 ? "" : "s") \u{00B7} \(r.fails) failure\(r.fails == 1 ? "" : "s")").textStyle(.caption, tint: Theme.inkFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                if live.isEmpty {
                    EmptyState(glyph: Glyph.ventures, title: "You run no startup",
                               message: "You put in the seed money, hire builders and raise rounds as the product takes shape. Most fail; a few sell for many times what went in.",
                               actionTitle: "Found a startup", action: { ent.run(.ventures, "Found a startup") { sheet = .found } }, centered: false)
                        .padding(.vertical, Theme.Space.s)
                }
                ForEach(Array(live.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 { Hairline() }
                    row(item.element)
                }
                if !past.isEmpty {
                    Button(showPast ? "Hide past startups" : "Past startups (\(past.count))") { showPast.toggle() }
                        .buttonStyle(TertiaryButtonStyle(size: .compact)).padding(.top, Theme.Space.s)
                    if showPast {
                        ForEach(past) { (f: Startups.Founded) in
                            LedgerRow(title: f.name, subtitle: "\(f.sectorName) \u{00B7} \(f.stageName)",
                                      value: f.exited ? engine.homeCurrency.tidyShort(f.exitValue) : "",
                                      pill: f.exited ? "Sold" : "Closed", pillTone: f.exited ? .good : .neutral)
                        }
                    }
                }
            }
        }
    }

    private func row(_ f: Startups.Founded) -> some View {
        let cur: Currency = engine.homeCurrency
        let key: String = "s\(f.id)"
        let isOpen: Bool = open == key
        let status: (String, AcctPill.Tone) = statusPill(f)
        return VStack(alignment: .leading, spacing: 0) {
            LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: f.sectorName, glyph: Glyph.ventures, initials: f.name, shape: .square)),
                      title: f.name,
                      subtitle: "\(f.productName.isEmpty ? f.sectorName : f.productName) \u{00B7} \(f.stageName) \u{00B7} \(Int(saturating: f.ownership.rounded()))% yours",
                      value: cur.tidyShort(f.valuation * f.ownership / 100),
                      valueNote: "cash \(cur.tidyShort(f.cash))",
                      pill: status.0, pillTone: status.1,
                      chevron: false, identifier: "ventures-startup-\(f.id)") { open = isOpen ? nil : key }
            if isOpen {
                StartupPanel(engine: engine, f: f, sheet: $sheet, pending: $pending)
                    .padding(.bottom, Theme.Space.m)
            }
        }
    }

    /// The one word that says what the startup needs next.
    private func statusPill(_ f: Startups.Founded) -> (String, AcctPill.Tone) {
        if !f.offers.isEmpty { return (f.offers.count == 1 ? "1 offer" : "\(f.offers.count) offers", .good) }
        if f.runwayWeeks < 8 { return ("\(f.runwayWeeks) wk runway", .bad) }
        if f.product?.phase == "ready" { return ("Ready to launch", .good) }
        if f.product?.phase == "live" { return ("On sale", .good) }
        return ("\(f.runwayWeeks) wk runway", .neutral)
    }
}

/// The open row of a startup: figures, offers to answer, the main action first, then team, product, use in your companies and shutting down.
private struct StartupPanel: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var f: Startups.Founded
    @Binding var sheet: VentureSheet?
    @Binding var pending: PendingAction?

    var body: some View {
        let cur: Currency = engine.homeCurrency
        let monthlyBurn: Double = f.burn * 52 / 12
        let interest = engine.startupInterest(startupID: f.id)
        let topUp: Double = cur.scaledPrice(100000)
        let short: Bool = f.runwayWeeks < 8
        let ready: Bool = f.product?.phase == "ready"
        let primary: String = ready ? "launch" : short ? "topup" : "raise"
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            FigureCard(items: [
                .init(label: "You own", value: "\(Int(saturating: f.ownership.rounded()))%", sub: "worth \(cur.tidyShort(f.valuation * f.ownership / 100))"),
                .init(label: "Cash", value: cur.tidyShort(f.cash), tint: short ? Theme.loss : Theme.ink, sub: "\(f.runwayWeeks) weeks of runway"),
                .init(label: "Burn", value: cur.tidyShort(monthlyBurn), sub: "a month"),
            ])
            if let p = f.product { Text(productLine(p, cur)).textStyle(.caption, tint: Theme.inkFaint) }
            Text("Investors: \(interest.word)").textStyle(.caption, tint: Theme.inkFaint)
            if short { Text("Runway is short: raise a round or put money in, or it closes when the cash runs out.").textStyle(.caption, tint: Theme.warn) }
            ForEach(f.offers) { (o: Funding.FundOffer) in offerView(o, cur) }
            WrapRow {
                Group {
                    if ready { action("launch", "Launch it", primary) { sheet = .launch(f.id) } }
                    action("topup", "Put in \(cur.tidyShort(topUp))", primary) { askTopUp(topUp, cur) }
                    action("raise", "Raise a round", primary) { raise() }
                    if let p = f.product, p.phase == "live" { action("price", "Change the price", primary) { sheet = .launch(f.id) } }
                }
            }
            if let p = f.product { team(p) }
            if let p = f.product, p.ready { useInCompanies(p) }
            Button("Shut down") { askShutDown(cur) }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }
        .padding(.top, Theme.Space.xs)
    }

    @ViewBuilder private func action(_ id: String, _ title: String, _ primary: String, _ run: @escaping () -> Void) -> some View {
        if id == primary {
            Button(title, action: run).buttonStyle(PrimaryButtonStyle(size: .compact))
        } else {
            Button(title, action: run).buttonStyle(SecondaryButtonStyle(size: .compact))
        }
    }

    // MARK: Offers and rounds

    private func offerView(_ o: Funding.FundOffer, _ cur: Currency) -> some View {
        let terms: CapTable.DealTerms? = engine.fundingOfferTerms(companyID: f.id, offerIndex: o.id)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("\(o.name) offers \(cur.tidyShort(o.amount)) for \(Int(saturating: o.pct.rounded()))%").textStyle(.headline, tint: Theme.accent)
            Text("\(o.says) Values it at \(cur.tidyShort(o.preMoney)) before the money, \(terms.map { cur.tidyDisplay($0.pricePerShare) } ?? "") a share, \(terms.map { String($0.sharesIssued) } ?? "") new shares.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Accept") {
                    pending = PendingAction(title: "Take \(cur.tidyShort(o.amount)) for \(Int(saturating: o.pct.rounded()))%?",
                                            message: DealText.describe(terms, cur, companyName: f.name),
                                            button: "Close the round", destructive: true, tone: .investment, icon: "chart.pie") {
                        let ok = store.act { $0.acceptStartupRound(startupID: f.id, index: o.id) } ?? false
                        store.show(ok ? "Round closed: \(cur.tidyShort(o.amount)) in for \(Int(saturating: o.pct.rounded()))%." : "That offer is no longer on the table.", tone: ok ? "good" : "warn")
                    }
                }.buttonStyle(PrimaryButtonStyle(size: .compact))
                Button("Decline") { store.settle(store.act { $0.declineStartupRound(startupID: f.id, index: o.id) }, "Offer declined.", same: "That offer had already gone.") }
                    .buttonStyle(SecondaryButtonStyle(size: .compact))
            }
        }.padding(.vertical, Theme.Space.xs)
    }

    private func raise() {
        switch store.act({ $0.pitchStartupRound(startupID: f.id) }) {
        case .offers(let n)?: Haptics.success(); store.show("\(n) investor\(n == 1 ? "" : "s") made an offer.", tone: "good")
        case .none?: store.show("No investor bit this time.", tone: "warn")
        case .tooSoon(let w)?: store.show("Too soon to pitch again: \(w) week\(w == 1 ? "" : "s") to go.", tone: "n")
        default: store.show("This startup is no longer running.", tone: "warn")
        }
    }

    private func askTopUp(_ topUp: Double, _ cur: Currency) {
        pending = PendingAction(title: "Put \(cur.tidyShort(topUp)) into \(f.name)?",
                                message: "From your own cash. It buys about \(Int(saturating: (topUp / max(1, f.burn)).rounded())) more weeks of runway; your share does not change.",
                                button: "Put it in", amount: topUp, currency: cur, tone: .investment, icon: "plus.circle") {
            let ok = store.act { $0.putMoneyIntoStartup(startupID: f.id, amount: topUp) } ?? false
            store.show(ok ? "\(cur.tidyShort(topUp)) put in." : "Not enough cash.", tone: ok ? "good" : "warn")
        }
    }

    private func askShutDown(_ cur: Currency) {
        pending = PendingAction(title: "Shut down \(f.name)?",
                                message: "The team goes and the product stops. What cash is left comes back after costs; your stake is lost and it counts as a failure.",
                                button: "Shut down", destructive: true, tone: .danger, icon: "power") {
            let back = store.act { $0.shutDownStartup(startupID: f.id) } ?? nil
            store.show(back.map { "Shut down. \(cur.tidyShort($0)) comes back to you." } ?? "It was already closed.", tone: "n")
        }
    }

    // MARK: Team and product

    @ViewBuilder private func team(_ p: Startups.Product) -> some View {
        Text("Team and product").capsLabel(Theme.inkFaint).padding(.top, Theme.Space.xs)
        WrapRow {
            Group {
                Button("\u{2212} builder") {
                    store.settle(store.act { $0.changeBuilders(startupID: f.id, by: -1) }, "One builder let go (notice and severance paid by the company): slower work, lower wages.")
                }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(f.developers == 0)
                Button("+ builder") {
                    store.settle(store.act { $0.changeBuilders(startupID: f.id, by: 1) }, "A builder hired at market pay: faster work, higher payroll.")
                }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(f.developers >= 10)
                Button(p.selfHours > 0 ? "Stop working on it" : "Work on it yourself") {
                    let ok = store.act { $0.toggleOwnerHoursOnProduct(startupID: f.id) } ?? false
                    store.show(ok ? (p.selfHours > 0 ? "You stopped working on the product." : "You now put your free hours into the product.") : "You cannot build this product yourself.", tone: ok ? "good" : "warn")
                }.buttonStyle(SecondaryButtonStyle(size: .compact))
            }
        }
    }

    @ViewBuilder private func useInCompanies(_ p: Startups.Product) -> some View {
        let users = engine.companiesThatCanUseProduct(startupID: f.id)
        if !users.isEmpty {
            Text("Use it in your companies").capsLabel(Theme.inkFaint).padding(.top, Theme.Space.xs)
            ForEach(users, id: \.company.id) { c in
                let using: Bool = p.usedBy.contains(c.company.id)
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
                              selection: Binding<Int>(get: { Int(saturating: p.internalPrice.rounded()) }, set: { (pct: Int) in
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
                        Text(r.alreadyCustomer ? "Already a customer" : r.waitWeeks > 0 ? "Asked recently: try again in \(r.waitWeeks.weeksText)" : "\(Int(saturating: (r.odds * 100).rounded()))% chance they sign \u{00B7} relationship: \(Words.level(r.relationship, scale: .quality).lowercased())")
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

    private func productLine(_ p: Startups.Product, _ cur: Currency) -> String {
        let phase: String = p.phase == "live" ? "On sale" : p.phase == "ready" ? "Finished, waiting for your launch decision" : p.phase == "beta" ? "Being tested" : "Being built"
        var parts: [String] = ["\(phase) \(Int(saturating: (p.progress * 100).rounded()))%", "\(f.developers) builder\(f.developers == 1 ? "" : "s") on the payroll"]
        if f.teamWanted > f.developers && p.phase != "live" { parts.append("you asked for \(f.teamWanted)") }
        if p.phase == "live" && f.price > 0 { parts.append("\(cur.tidyDisplay(f.price)) each") }
        if p.selfHours > 0 { parts.append("you help") }
        if p.customers > 0 { parts.append("\(Int(p.customers)) customers") }
        if p.revenueWeekly > 0 { parts.append("\(cur.tidyShort(p.revenueWeekly)) a week") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: Found a startup

/// Found a startup: sector, product, how customers pay, who builds it and how much seed money, then the cost summary (what leaves your cash,
/// what is left, runway and time to a product) before the one confirmation.
struct FoundStartupSheet: View {
    @EnvironmentObject var store: GameStore
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
                    content(e, sec)
                }
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Found a startup")
        .onChange(of: sectorID) { _, _ in productID = ""; modelID = "" }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ sec: StartupProducts.Sector) -> some View {
        let cur: Currency = e.homeCurrency
        let product = sec.products.first { $0.id == productID } ?? sec.products[0]
        let model = sec.models.first { $0.id == modelID } ?? sec.models[0]
        let whoNow: String = who == "self" && !sec.canBuildYourself ? "c2" : who
        let plan = e.startupPlan(sector: sec.id, who: whoNow, seedMultiple: seed)
        VStack(alignment: .leading, spacing: PopupSpace.card) {
            CardSection("Sector") {
                Picker("Sector", selection: $sectorID) { ForEach(StartupProducts.sectors) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Text("Capital need \(sec.capitalNeed) of 4 \u{00B7} built by \(sec.builders)" + (sec.canBuildYourself ? " \u{00B7} you can build it yourself" : "")).popupText(.caption)
            }
            CardSection("Product and how customers pay") {
                Picker("Product", selection: Binding(get: { product.id }, set: { productID = $0 })) { ForEach(sec.products, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Picker("Model", selection: Binding(get: { model.id }, set: { modelID = $0 })) { ForEach(sec.models, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
            }
            CardSection("Who builds it, and how much seed money") {
                let builderChoices: [String] = sec.canBuildYourself ? ["self", "c2", "c4"] : ["c2", "c4"]
                SegmentedPill(items: builderChoices, title: { $0 == "self" ? "You" : $0 == "c2" ? "2 builders" : "4 builders" }, selection: Binding(get: { whoNow }, set: { who = $0 }))
                SegmentedPill(items: [1.0, 2.0, 4.0], title: { $0 == 1.0 ? "Lean" : $0 == 2.0 ? "Double" : "Four times" }, selection: $seed)
            }
            if let p = plan { summary(e, sec, product.id, model.id, whoNow, p, cur) }
        }
    }

    /// The cost summary: what leaves the cash now, what is left, and what the money buys.
    @ViewBuilder private func summary(_ e: GameEngine, _ sec: StartupProducts.Sector, _ productID: String, _ modelID: String, _ whoNow: String,
                                      _ p: Startups.Plan, _ cur: Currency) -> some View {
        let cash: Double = Payments.liquid(e.state)
        let enough: Bool = cash >= p.seed
        CardSection("What it costs") {
            VStack(alignment: .leading, spacing: PopupSpace.row) {
                PopupRow(label: "Seed money, from your cash", value: cur.tidyShort(p.seed))
                PopupRow(label: "Your cash after", value: enough ? cur.tidyShort(cash - p.seed) : "Not enough")
                PopupRow(label: "Builders", value: p.builders == 0 ? "You, in your free hours" : "\(p.builders) at \(cur.tidyShort(p.buildersMonthly)) a month")
                PopupRow(label: "Runway", value: "\(p.runwayWeeks) weeks")
                PopupRow(label: "Test version", value: p.weeksToTest.map { "\($0) weeks" } ?? "Never")
                PopupRow(label: "On sale", value: p.weeksToSell.map { "\($0) weeks" } ?? "Never")
                PopupRow(label: "Investors", value: Funding.interestWord(p.interest).word)
            }
            Text("Risk: most startups fail and the seed money is lost. Each round brings money in but makes your share smaller. If the runway ends before the product sells, raise a round or put money in.")
                .popupText(.caption)
            if !enough { Text("You need \(cur.tidyShort(p.seed - cash)) more in cash.").popupText(.risk) }
        }
        Button("Found it for \(cur.tidyShort(p.seed))") {
            pending = PendingAction(title: "Found a \(sec.name) startup?",
                                    message: "\(cur.tidyDisplay(p.seed)) of seed money leaves your cash now. Most startups fail and the seed money is lost.",
                                    button: "Found it for \(cur.tidyShort(p.seed))", amount: p.seed, currency: cur, tone: .investment, icon: "lightbulb") {
                switch store.act({ $0.foundStartup(name: nil, sector: sec.id, product: productID, model: modelID, who: whoNow, seedMultiple: seed) }) {
                case .ok?: Haptics.success(); store.show("Founded. Build the product, then raise a round.", tone: "good"); dismiss()
                case .notEnoughMoney(let need)?: Haptics.warning(); store.show("You need \(cur.tidyShort(need)) in cash.", tone: "warn")
                default: store.show("That sector is not available.", tone: "warn")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        .disabled(!enough)
    }
}

// MARK: Launch and price

/// The launch decision (and, after launch, the price): the price per customer, a weekly marketing budget, and what to expect. Read from
/// `startupLaunchPreview`; nothing is decided until "Launch". Hiring and firing are in the company's own team screens.
struct StartupLaunchSheet: View {
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
                        SegmentedPill(items: Array(steps.indices), title: { "\(Int(saturating: (steps[$0] * 100).rounded()))%" }, selection: $priceStep)
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
                            .init(label: "New customers", value: String(Int(saturating: funnel.newCustomersWeekly.rounded())), sub: "a week, without luck"),
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
        .centerSheetTitle(launched ? "Change the price" : "Launch")
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
