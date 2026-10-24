import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Brands that take new franchisees. You apply, they answer in a week or three, then you meet them to agree the terms, then you start.
struct FranchisesView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            let brands = e.franchiseBrands()
            let cur = e.homeCurrency
            let trades = Array(Set(brands.map { $0.tradeID })).sorted { (e.data.catalog[$0]?.name ?? $0) < (e.data.catalog[$1]?.name ?? $1) }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Brands that take new franchisees. You apply, they answer in a week or three, then you meet them to agree the terms. When the terms are agreed you can start the company under the brand.")
                        .font(.caption).foregroundStyle(Theme.ivoryMuted)
                    if brands.isEmpty { Text("No brand is looking for franchisees right now.").font(.bodyText).foregroundStyle(Theme.ivoryFaint) }
                    ForEach(trades, id: \.self) { t in
                        LedgerSection(e.data.catalog[t]?.name ?? t) {
                            VStack(spacing: 0) {
                                ForEach(Array(brands.filter { $0.tradeID == t }.enumerated()), id: \.element.id) { n, b in
                                    if n > 0 { Hairline() }
                                    FranchiseBrandRow(brand: b)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Franchises")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// One franchise brand: its terms, and the next step with it (apply, meet them, or start under the agreed deal).
struct FranchiseBrandRow: View {
    @EnvironmentObject var store: GameStore
    var brand: FranchiseBrands.Brand

    var body: some View {
        if let e = store.engine { row(e, brand, e.homeCurrency) }
    }

    @ViewBuilder private func row(_ e: GameEngine, _ b: FranchiseBrands.Brand, _ cur: Currency) -> some View {
        let a = e.franchiseApplication(b.id)
        let st = a["st"].string
        let sx = e.franchiseStatus(b)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(b.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text("\(b.tierDescription) · \(b.units) \(b.units == 1 ? "unit" : "units") · \(FranchiseBrands.brandWord(b.strength))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer(minLength: 8)
                Text("Fee \(cur.tidyShort(e.franchiseEntryFee(b)))").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
            }
            switch st {
            case "pending":
                Text("Application sent. Answer in about \(max(1, a["due"].int - e.state.week).weeksText).").font(.caption).foregroundStyle(Theme.caution)
            case "invited":
                HStack {
                    Text("They want to talk. Open for \(max(0, a["exp"].int - e.state.week)) more weeks.").font(.caption).foregroundStyle(Theme.gain)
                    Spacer()
                    NavigationLink { BrandMeetingView(brandID: b.id) } label: { Text("Meet the \(b.role)").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.gold) }
                }
            case "agreed":
                let t = e.franchiseAgreedTerms(b.id)
                HStack {
                    Text("Terms agreed. Entry fee \(cur.tidyShort(t?.fee ?? 0)), royalty \(Currency.percent(t?.royalty ?? 0, decimals: 1)).").font(.caption).foregroundStyle(Theme.gain)
                    Spacer()
                    NavigationLink { BrandMeetingView(brandID: b.id) } label: { Text("Talk again").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted) }
                    NavigationLink { StartFranchisedView(brandID: b.id) } label: { Text("Start with this deal").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.gold) }
                }
            default:
                HStack {
                    if st == "refused" { Text("They turned you down for now.").font(.caption).foregroundStyle(Theme.loss) }
                    else if !sx.ok { Text(sx.why).font(.caption).foregroundStyle(Theme.ivoryFaint) }
                    Spacer()
                    if sx.ok {
                        Button("Apply") {
                            switch store.act({ $0.applyToFranchiseBrand(b.id) }) {
                            case .ok?: Haptics.success(); store.show("Application sent. Expect an answer in a week or three.", tone: "good")
                            case .closed(let why)?: Haptics.warning(); store.show(why, tone: "warn")
                            default: break
                            }
                        }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }.padding(.vertical, 9)
    }
}

/// The meeting with a brand: standard terms, and what you ask for on top. They accept, counter, push back or walk away.
struct BrandMeetingView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var brandID: String
    @State private var ask = FranchiseBrands.Ask()
    @State private var result: FranchiseBrands.Negotiation?
    @State private var showFacts = false

    private let feeSteps: [Double] = [-0.3, -0.2, -0.1, 0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3]
    private let royaltySteps: [Double] = [-0.03, -0.02, -0.01, 0, 0.005, 0.01, 0.015, 0.02, 0.025, 0.03]

    var body: some View {
        if let e = store.engine, let b = e.franchiseBrand(brandID) {
            let cur = e.homeCurrency
            let st = e.franchiseStatus(b)
            let a = e.franchiseApplication(b.id)
            let bd = e.data.catalog[b.tradeID]
            let stats = e.franchiseUnitStats(b)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.name).font(.serifTitle(26)).foregroundStyle(Theme.ivory)
                        Text("\(b.tierDescription) · \(FranchiseBrands.brandWord(b.strength))").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    if !st.ok {
                        Text(st.why).font(.bodyText).foregroundStyle(Theme.loss)
                    } else if !["invited", "agreed"].contains(a["st"].string) {
                        Text("Apply first. They will invite you when they have looked at your application.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                    } else {
                        Text(result?.message ?? "\(b.contact) is listening. Standard terms are below. Ask for what would make this work for you.")
                            .font(.system(size: 13.5)).foregroundStyle(result.map { $0.kind == .accept ? Theme.gain : ($0.kind == .counter || $0.kind == .push) ? Theme.ivory : Theme.loss } ?? Theme.ivoryMuted)
                            .padding(.vertical, 6).overlay(alignment: .leading) { Rectangle().fill(Theme.gold).frame(width: 1.5).offset(x: -10) }.padding(.leading, 10)
                        LedgerSection("Terms") {
                            VStack(spacing: 0) {
                                stepper("Entry fee", feeSteps, current: ask.fee, label: { v in v < 0 ? "Pay \(Int(-v * 100))% more" : v > 0 ? "\(Int(v * 100))% off" : "Standard" }) { ask.fee = $0 }
                                Hairline()
                                stepper("Royalty", royaltySteps, current: ask.royalty, label: { v in Currency.percent(max(0, b.royalty - v), decimals: 1) + (v == 0 ? " (standard)" : "") }) { ask.royalty = $0 }
                                Hairline()
                                stepper("Fit-out covered", [0, 1, 2].map { Double($0) }, current: Double(ask.cover), label: { ["None", "40%", "70%"][Int($0)] }) { ask.cover = Int($0) }
                                if let bd, bd.premisesM2 > 0 {
                                    Hairline()
                                    stepper("Rent covered", [0, 1, 2].map { Double($0) }, current: Double(ask.rent), label: { ["None", "6 months", "12 months"][Int($0)] }) { ask.rent = Int($0) }
                                }
                                if let bd, bd.equipment.contains(where: { $0.vehicleModels != nil }) {
                                    Hairline()
                                    stepper("Vehicles", [0, 1].map { Double($0) }, current: Double(ask.vehicles), label: { $0 == 0 ? "You buy" : "They cover half" }) { ask.vehicles = Int($0) }
                                }
                            }
                        }
                        HStack {
                            Button(result?.terms != nil ? "Propose again" : "Propose these terms") {
                                let r: FranchiseBrands.Negotiation? = store.act({ $0.negotiateFranchise(brandID, ask: ask) }) ?? nil
                                result = r
                                if let c = r?.counter { ask = c }
                            }.buttonStyle(result?.terms != nil ? AnyButtonStyle(QuietButtonStyle()) : AnyButtonStyle(GoldButtonStyle()))
                            if let t = result?.terms, result?.kind == .accept || result?.kind == .counter {
                                Button("Sign this deal") {
                                    store.act { $0.signFranchiseTerms(brandID, terms: t) }
                                    if store.engine?.franchiseAgreedTerms(brandID) != nil { Haptics.success(); store.show("Terms agreed. Start the company under the brand from the list.", tone: "good"); dismiss() }
                                    else { Haptics.warning(); store.show("The brand did not sign. Talk again.", tone: "warn") }
                                }.buttonStyle(GoldButtonStyle())
                            }
                        }
                        if let t = result?.terms, result?.kind == .accept || result?.kind == .counter {
                            Text("Entry fee \(cur.tidyShort(t.fee)), royalty \(Currency.percent(t.royalty, decimals: 1)) plus \(Currency.percent(t.marketing, decimals: 0)) marketing\(cover(t)).").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        }
                    }
                    LedgerSection(title: "Facts", trailing: { Button(showFacts ? "Hide" : "Show") { showFacts.toggle() }.font(.system(size: 11)).foregroundStyle(Theme.gold).buttonStyle(.plain) }) {
                        if showFacts {
                            VStack(spacing: 0) {
                                FlatRow(label: "Units open", value: "\(b.units)", rule: false)
                                FlatRow(label: "Entry fee", value: cur.tidyShort(e.franchiseEntryFee(b)))
                                FlatRow(label: "Royalty", value: Currency.percent(b.royalty, decimals: 1) + " of revenue")
                                FlatRow(label: "Marketing fund", value: Currency.percent(b.marketingFund, decimals: 0))
                                FlatRow(label: "Setup support", value: ["None, you pay everything", "They cover about 40%", "They cover about 70%"][min(2, b.support)])
                                FlatRow(label: "Contract length", value: "\(b.termYears) years")
                                FlatRow(label: "Typical unit revenue", value: cur.tidyShort(stats.revenue) + " / wk")
                                FlatRow(label: "Margin after fees", value: Currency.percent(stats.margin, decimals: 0))
                                FlatRow(label: "Units failing in 5 years", value: "\(Int(b.failPercent))%")
                                FlatRow(label: "Quality standard", value: b.standard >= 70 ? "Strict" : b.standard >= 58 ? "Firm" : "Relaxed")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Franchise meeting")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func cover(_ t: FranchiseBrands.Terms) -> String {
        var parts: [String] = []
        if t.cover > 0 { parts.append("about \(["0%", "40%", "70%"][min(2, t.cover)]) of the set-up") }
        if t.rent > 0 { parts.append("\([0, 6, 12][min(2, t.rent)]) months of rent") }
        if t.vehicles != 0 { parts.append("half of the vehicles") }
        return parts.isEmpty ? "" : ", they cover " + parts.joined(separator: ", ")
    }

    private func stepper(_ title: String, _ steps: [Double], current: Double, label: @escaping (Double) -> String, set: @escaping (Double) -> Void) -> some View {
        let i = steps.firstIndex(where: { abs($0 - current) < 0.0001 }) ?? 0
        return HStack {
            Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
            Spacer()
            Button { set(steps[(i - 1 + steps.count) % steps.count]); result = nil } label: { Text("‹").font(.system(size: 18)).frame(width: 30) }.buttonStyle(.plain).foregroundStyle(Theme.gold)
            Text(label(steps[i])).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory).frame(minWidth: 110)
            Button { set(steps[(i + 1) % steps.count]); result = nil } label: { Text("›").font(.system(size: 18)).frame(width: 30) }.buttonStyle(.plain).foregroundStyle(Theme.gold)
        }.padding(.vertical, 9)
    }
}

/// Type-erased button style, so a button can switch between two styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Start the company under a brand whose terms you agreed.
struct StartFranchisedView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var brandID: String
    @State private var cityID = ""
    @State private var limited = true
    @State private var name = ""
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let b = e.franchiseBrand(brandID), let t = e.franchiseAgreedTerms(brandID) {
            let cc = e.franchiseApplication(brandID)["country"].string
            let country = e.data.countries.resolve(cc.isEmpty ? e.state.homeCountryCode : cc, orHome: e.state.homeCountryCode)
            let cur = Currency(country: country, rates: ExchangeRates(drift: e.state.exchangeRates.values))
            let bd = e.data.catalog[b.tradeID]
            let city = cityID.isEmpty ? (e.franchiseApplication(brandID)["city"].string.isEmpty ? country.cities[0].id : e.franchiseApplication(brandID)["city"].string) : cityID
            let form: LegalForm = (limited || (bd?.needsLimitedCompany ?? false)) ? .limited : .soleTrader
            let est = e.franchiseStartEstimate(brandID: brandID, cityID: city, form: form)
            let fund = max(0, min(((est?.estimate.total ?? 0) + (est?.fee ?? 0)) * 1.15, Payments.liquid(e.state) - (est?.estimate.personalOutlay ?? 0)))
            let short = max(0, (est?.estimate.total ?? 0) + (est?.fee ?? 0) + (est?.estimate.personalOutlay ?? 0) - Payments.liquid(e.state))
            let left = max(0, Payments.liquid(e.state) - (est?.estimate.personalOutlay ?? 0) - fund)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start under \(b.name)").font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        Text("Entry fee \(cur.tidyShort(t.fee)) · royalty \(Currency.percent(t.royalty, decimals: 1)) · marketing \(Currency.percent(t.marketing, decimals: 0)) · \(b.termYears) years").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    LedgerSection("Where and how") {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            Picker("City", selection: Binding(get: { city }, set: { cityID = $0 })) { ForEach(country.cities) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                            if bd?.needsLimitedCompany == true { Text("This trade needs a limited company.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                            else { Picker("Legal form", selection: $limited) { Text("Sole trader").tag(false); Text("Limited company").tag(true) }.pickerStyle(.segmented) }
                            TextField("Company name", text: $name).textFieldStyle(.plain).font(.system(size: 15)).padding(.vertical, 8).overlay(alignment: .bottom) { Hairline() }
                        }
                    }
                    if let est {
                        LedgerSection("Start-up cost") {
                            VStack(spacing: 0) {
                                FlatRow(label: "Start-up estimate", value: cur.tidyShort(est.estimate.total), sub: "Documents, equipment, premises, stock, first payroll.", rule: false)
                                FlatRow(label: "Franchise entry fee", value: cur.tidyShort(est.fee))
                                if t.cover > 0 || t.rent > 0 || t.vehicles != 0 { FlatRow(label: "The brand covers", value: "part of the set-up", sub: "It arrives in the company's account when you start.", tint: Theme.gain) }
                                FlatRow(label: "You have available", value: cur.tidyShort(Payments.liquid(e.state)))
                                FlatRow(label: "Total to find", value: cur.tidyShort(est.estimate.total + est.fee), sub: "Estimate plus entry fee, before the brand's cover.", tint: Theme.ivory)
                                FlatRow(label: "Left in your accounts afterwards", value: cur.tidyShort(left), tint: left > 0 ? Theme.gain : Theme.caution)
                            }
                        }
                        LedgerSection("Risks") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("You pay \(Currency.percent(t.royalty, decimals: 1)) of sales as royalty and \(Currency.percent(t.marketing, decimals: 0)) to the brand's marketing for \(b.termYears) years. Leaving early means a buyout.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                                Text("The brand sets standards you must keep. The premises and equipment are set up with the standard choices; you can change the place afterwards under Equipment.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                                if short > 0 { Text("You are \(cur.tidyShort(short)) short. If the company cannot pay the entry fee it starts independent, without the brand.").font(.system(size: 12.5)).foregroundStyle(Theme.caution) }
                                Text("It earns nothing until it is set up and open.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                            }
                        }
                        Button("Review and start") {
                            pending = PendingAction(title: "Start under \(b.name)?",
                                                    message: "\(cur.tidyShort(est.estimate.total + est.fee)) to start, including the \(cur.tidyShort(est.fee)) entry fee. \(cur.tidyShort(fund)) goes into the company from your cash now. You keep about \(cur.tidyShort(left)). Royalty \(Currency.percent(t.royalty, decimals: 1)) of sales for \(b.termYears) years.",
                                                    button: "Start it") {
                                let r = store.act { $0.startFranchisedCompany(brandID: brandID, cityID: city, form: form, name: name, fundWith: fund) }
                                switch r {
                                case .success(let id)?: Haptics.success(); store.show("Started under \(b.name).", tone: "good"); store.openCompany(id); dismiss()
                                case .failure(.banned(let why))?: Haptics.failure(); store.show(why, tone: "bad")
                                case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You can't afford the registration costs yet.", tone: "warn")
                                default: Haptics.warning(); store.show("Not possible here.", tone: "warn")
                                }
                            }
                        }.buttonStyle(GoldButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Start a franchise")
            .navigationBarTitleDisplayMode(.inline)
            .confirmAction($pending)
        } else {
            Text("These terms have expired. Meet the brand again.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }
}
