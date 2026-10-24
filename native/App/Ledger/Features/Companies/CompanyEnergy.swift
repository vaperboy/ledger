import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A label and a figure on one line with a hairline above: the flat row used by the sections of energy, fish, holding and club.
struct FlatRow: View {
    var label: String
    var value: String
    var sub: String = ""
    var tint: Color = Theme.ivory
    var rule = true
    var body: some View {
        VStack(spacing: 0) {
            if rule { Hairline() }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                Text(value).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(tint).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 9)
        }
    }
}

/// The renewable power plant and the oil and gas company: what they own, what they produce, and how to grow.
struct CompanyEnergy: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var megawatts = 10.0
    @State private var confirmDrill = false
    @State private var pending: PendingAction?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if company.type == "power" { plant } else { oil }
        }
        .confirmAction($pending)
    }

    // MARK: Power

    private var plant: some View {
        let p = engine.powerPlant(companyID: company.id)
        let cur = engine.currency(for: company)
        let perMW = engine.turbinePrice(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection("Power plant") {
                VStack(alignment: .leading, spacing: 0) {
                    KeyFigures(items: [
                        .init(label: "Producing", value: "\(Int((p?.megawatts ?? 0).rounded())) MW", sub: p?.source ?? ""),
                        .init(label: "Being built", value: "\(Int((p?.building ?? 0).rounded())) MW", sub: p?.weeksToReady.map { "first ready in \($0) wk" } ?? ""),
                        .init(label: "Output last week", value: "\(Int((p?.outputMWh ?? 0).rounded())) MWh"),
                    ])
                    FlatRow(label: "Average price", value: cur.tidyShort(p?.averagePrice ?? 0) + " / MWh", sub: "Sold at the power market price, less what is hedged.").padding(.top, 8)
                    FlatRow(label: "Market price index", value: String(format: "%.0f%% of normal", engine.state.economy.power * 100),
                            tint: engine.state.economy.power < 0.85 ? Theme.loss : engine.state.economy.power > 1.15 ? Theme.gain : Theme.ivory)
                }
            }
            LedgerSection("Build more") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Text("\(Int(megawatts)) MW").font(.system(size: 15, weight: .medium).monospacedDigit())
                        Spacer()
                        StepperPill(value: $megawatts, range: 1...100, step: 5)
                    }
                    Text("About \(cur.tidyShort(perMW * megawatts)) now (\(cur.tidyShort(perMW)) per MW). New capacity takes \(buildWeeks) weeks to build and only then produces. Output follows the weather and the season.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    Button("Order \(Int(megawatts)) MW…") {
                        let mw = megawatts
                        pending = PendingAction(title: "Order \(Int(mw)) MW?", message: "About \(cur.display(perMW * mw)) is paid from company cash (it has \(cur.tidyShort(company.cash))). Nothing is produced for \(buildWeeks) weeks, and output then follows the weather and the power price.", button: "Order") {
                            if store.act({ $0.orderTurbines(companyID: company.id, megawatts: mw) }) == true { Haptics.success(); store.show("Ordered \(Int(mw)) MW. Construction has started.", tone: "good") }
                            else { Haptics.warning(); store.show("The company does not have \(cur.tidyShort(perMW * mw)) in cash. Put money in under Finances.", tone: "warn") }
                        }
                    }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private var buildWeeks: Int { EnergyModel.source(of: company).buildWeeks }

    // MARK: Oil and gas

    private var oil: some View {
        let cur = engine.currency(for: company)
        let fields = engine.oilFields(companyID: company.id)
        let price = engine.oilPricePerBarrel(companyID: company.id)
        let drill = engine.explorationCost()
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection("Production") {
                VStack(alignment: .leading, spacing: 0) {
                    KeyFigures(items: [
                        .init(label: "Fields", value: "\(fields.filter { $0.state != "depleted" }.count)", sub: "\(fields.filter { $0.state == "dev" }.count) in development"),
                        .init(label: "Last week", value: "\(Int(company.lastWeekUnits.rounded())) kbbl"),
                        .init(label: "Oil price", value: cur.tidyShort(price), sub: "per barrel"),
                    ])
                    FlatRow(label: "Market index", value: String(format: "%.0f%% of normal", engine.state.economy.oil * 100),
                            sub: "Taxes on oil are very high. Term contracts take part of the swing out.",
                            tint: engine.state.economy.oil < 0.85 ? Theme.loss : engine.state.economy.oil > 1.15 ? Theme.gain : Theme.ivory).padding(.top, 8)
                }
            }
            LedgerSection("Fields") {
                VStack(spacing: 0) {
                    if fields.isEmpty { Text("No fields yet. Buy a stake in a producing field for income right away, or drill.").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(Array(fields.enumerated()), id: \.element.id) { n, f in
                        FlatRow(label: f.name, value: String(format: "%.1f M bbl left", f.millionBarrelsLeft),
                                sub: f.state == "dev" ? "In development · \(f.weeksToProduction) weeks to production" : f.state == "prod" ? "Producing about \(Int(f.weeklyBarrels.rounded())) kbbl a week" : "Depleted",
                                rule: n > 0)
                    }
                }
            }
            LedgerSection("Grow") {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach([2000.0, 5000, 10000], id: \.self) { k in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Stake with \(Int(k / 1000)) M barrels left").font(.system(size: 13.5))
                                Text(cur.tidyShort(engine.oilStakePrice(thousandBarrels: k))).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer()
                            Button("Buy…") {
                                let cost = engine.oilStakePrice(thousandBarrels: k)
                                pending = PendingAction(title: "Buy a stake with \(Int(k / 1000)) M barrels left?", message: "\(cur.display(cost)) from company cash (it has \(cur.tidyShort(company.cash))). The field produces right away, and the barrels run out over time.", button: "Buy stake") {
                                    switch store.act({ $0.buyOilStake(companyID: company.id, thousandBarrels: k) }) {
                                    case .ok?: Haptics.success(); store.show("Stake acquired.", tone: "good")
                                    default: Haptics.warning(); store.show("The company needs \(cur.tidyShort(cost)) in cash.", tone: "warn")
                                    }
                                }
                            }.buttonStyle(QuietButtonStyle())
                        }
                        Hairline()
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Drill an exploration well").font(.system(size: 13.5))
                            Text("\(cur.tidyShort(drill)) · most wells find nothing; a hit takes about three years to produce").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer()
                        Button("Drill") { confirmDrill = true }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }
        .confirmationDialog("Drill an exploration well?", isPresented: $confirmDrill, titleVisibility: .visible) {
            Button("Drill for \(cur.tidyShort(drill))", role: .destructive) {
                switch store.act({ $0.exploreForOil(companyID: company.id) }) {
                case .hit?: Haptics.success(); store.show("Discovery! Check your inbox.", tone: "good")
                case .dry?: Haptics.warning(); store.show("A dry well.", tone: "bad")
                default: store.show("Not enough cash.", tone: "warn")
                }
            }
        }
    }
}

/// The salmon farm: the fish in the pens, the price, and whether to keep stocking and harvesting.
struct CompanySalmon: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let cohorts = engine.salmonCohorts(companyID: company.id)
        let cur = engine.currency(for: company)
        let fm = company.value("fm")
        let stocking = company.value("flags")["autoStock"].isNull || company.value("flags")["autoStock"].double != 0
        let harvesting = company.value("flags")["harvest"].isNull || company.value("flags")["harvest"].double != 0
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection("In the pens") {
                VStack(alignment: .leading, spacing: 0) {
                    KeyFigures(items: [
                        .init(label: "Fish", value: String(format: "%.0f k", cohorts.reduce(0) { $0 + $1.fish } / 1000)),
                        .init(label: "Biomass", value: "\(Int(fm["bio"].double.rounded())) t"),
                        .init(label: "Price a kilo", value: cur.tidyShort(engine.salmonPricePerKilo())),
                    ])
                    if cohorts.isEmpty {
                        Text("No fish in the pens. A new cohort is stocked when the cash allows.").font(.caption).foregroundStyle(Theme.ivoryFaint).padding(.top, 8)
                    }
                    ForEach(cohorts) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Hairline()
                            HStack {
                                Text("Cohort \(c.id + 1) · week \(c.age)").font(.system(size: 13.5))
                                Spacer()
                                Text("\(Int((c.fish / 1000).rounded())) k fish · \(String(format: "%.1f", c.kilosEach)) kg").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                            }.padding(.top, 8)
                            RateBar(label: "Ready to harvest", fraction: c.readyShare, tint: c.readyShare >= 0.95 ? Theme.gain : Theme.gold)
                        }.padding(.top, 4)
                    }
                    Text("Fish grow for about 18 months, then are sold at the market price. Lice, storms and algae can cost a cohort.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 8)
                }
            }
            LedgerSection("Routine") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Toggle("Stock new fish automatically", isOn: Binding(get: { stocking }, set: { v in store.act { $0.setSalmonAutomation(companyID: company.id, stocking: v, harvesting: harvesting) } })).tint(Theme.gold)
                    Toggle("Harvest when ripe", isOn: Binding(get: { harvesting }, set: { v in store.act { $0.setSalmonAutomation(companyID: company.id, stocking: stocking, harvesting: v) } })).tint(Theme.gold)
                    Text("A new cohort needs cash for the young fish (a few million) and then feed every week for over a year before anything is sold.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }
}
