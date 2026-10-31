import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Brands that take new franchisees, shelved by trade. You apply, they answer in a week or three, then you meet them to agree the terms,
/// then you start. Each brand is its own card: fee, units and strength in a figure strip, and one next step.
struct FranchisesView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            let brands: [FranchiseBrands.Brand] = e.franchiseBrands()
            let trades: [String] = Array(Set(brands.map { $0.tradeID })).sorted { (e.data.catalog[$0]?.name ?? $0) < (e.data.catalog[$1]?.name ?? $1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NoteCard(text: "Brands that take new franchisees. You apply, they answer in a week or three, then you meet them to agree the terms. When the terms are agreed you can start the company under the brand.")
                    if brands.isEmpty {
                        NoteCard(text: "No brand is looking for franchisees right now.", glyph: Glyph.clock)
                    } else {
                        overview(e, brands, trades)
                    }
                    ForEach(trades, id: \.self) { t in tradeShelf(e, brands, trade: t) }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .appScreen(title: "Franchises", subtitle: "Brands that take franchisees", tab: .group)
        }
    }

    private func overview(_ e: GameEngine, _ brands: [FranchiseBrands.Brand], _ trades: [String]) -> some View {
        let cur: Currency = e.homeCurrency
        let cheapest: Double = brands.map { e.franchiseEntryFee($0) }.min() ?? 0
        let items: [KeyFigures.Item] = [
            .init(label: "Brands open", value: "\(brands.count)"),
            .init(label: "Trades", value: "\(trades.count)"),
            .init(label: "Lowest entry fee", value: cur.tidyShort(cheapest)),
        ]
        return Card(padding: 14, radius: Theme.Radius.hero) { FigureStrip(items: items, columns: 3) }
    }

    private func tradeShelf(_ e: GameEngine, _ brands: [FranchiseBrands.Brand], trade t: String) -> some View {
        let list: [FranchiseBrands.Brand] = brands.filter { $0.tradeID == t }
        return MoreBlock(title: e.data.catalog[t]?.name ?? t, card: false, trailing: { Text("\(list.count)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
            ForEach(list, id: \.id) { b in FranchiseBrandRow(brand: b) }
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

    private func chipLabel(_ text: String, tint: Color = Theme.gold) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 4).frame(minHeight: 28)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
            .contentShape(Rectangle())
    }

    private func statusLine(_ text: String, _ tint: Color) -> some View {
        Text(text.tidyMoney).font(.system(size: 12.5)).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func next(_ e: GameEngine, _ b: FranchiseBrands.Brand, _ cur: Currency) -> some View {
        let a = e.franchiseApplication(b.id)
        let st: String = a["st"].string
        let sx = e.franchiseStatus(b)
        switch st {
        case "pending":
            statusLine("Application sent. Answer in about \(max(1, a["due"].int - e.state.week).weeksText).", Theme.caution)
        case "invited":
            statusLine("They want to talk. Open for \(max(0, a["exp"].int - e.state.week)) more weeks.", Theme.gain)
            NavigationLink { BrandMeetingView(brandID: b.id) } label: { chipLabel("Meet the \(b.role)") }.buttonStyle(.plain)
        case "agreed":
            let t = e.franchiseAgreedTerms(b.id)
            statusLine("Terms agreed. Entry fee \(cur.tidyShort(t?.fee ?? 0)), royalty \(Currency.percent(t?.royalty ?? 0, decimals: 1)).", Theme.gain)
            HStack(spacing: 8) {
                NavigationLink { BrandMeetingView(brandID: b.id) } label: { chipLabel("Talk again", tint: Theme.ivoryMuted) }.buttonStyle(.plain)
                NavigationLink { StartFranchisedView(brandID: b.id) } label: { chipLabel("Start with this deal") }.buttonStyle(.plain)
            }
        default:
            if st == "refused" { statusLine("They turned you down for now.", Theme.loss) }
            else if !sx.ok { statusLine(sx.why, Theme.ivoryFaint) }
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

    @ViewBuilder private func row(_ e: GameEngine, _ b: FranchiseBrands.Brand, _ cur: Currency) -> some View {
        let figures: [KeyFigures.Item] = [
            .init(label: "Entry fee", value: cur.tidyShort(e.franchiseEntryFee(b))),
            .init(label: "Units", value: "\(b.units)"),
            .init(label: "Brand", value: FranchiseBrands.brandWord(b.strength)),
        ]
        EntityCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconCircle(glyph: Glyph.group, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                        Text("\(b.tierDescription) · \(b.units) \(b.units == 1 ? "unit" : "units")").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                FigureStrip(items: figures, columns: 3)
                next(e, b, cur)
            }
        }
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
            let st = e.franchiseStatus(b)
            let a = e.franchiseApplication(b.id)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !st.ok {
                        NoteCard(text: st.why.tidyMoney, glyph: Glyph.warning, tint: Theme.loss)
                    } else if !["invited", "agreed"].contains(a["st"].string) {
                        NoteCard(text: "Apply first. They will invite you when they have looked at your application.", glyph: Glyph.clock)
                    } else {
                        talk(e, b)
                    }
                    facts(e, b)
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .appScreen(title: b.name, subtitle: "\(b.tierDescription) · \(FranchiseBrands.brandWord(b.strength))", tab: .group)
        }
    }

    // MARK: The talk

    private func replyTint() -> Color {
        guard let r = result else { return Theme.ivoryMuted }
        switch r.kind {
        case .accept: return Theme.gain
        case .counter, .push: return Theme.ivory
        default: return Theme.loss
        }
    }

    private func talk(_ e: GameEngine, _ b: FranchiseBrands.Brand) -> some View {
        let cur: Currency = e.homeCurrency
        let bd = e.data.catalog[b.tradeID]
        let signable: Bool = result?.terms != nil && (result?.kind == .accept || result?.kind == .counter)
        return VStack(alignment: .leading, spacing: 16) {
            NoteCard(text: result?.message ?? "\(b.contact) is listening. Standard terms are below. Ask for what would make this work for you.", glyph: Glyph.people, tint: replyTint())
            MoreBlock("Terms") { termSteppers(b, bd) }
            HStack(spacing: 10) {
                QuietButton(title: result?.terms != nil ? "Propose again" : "Propose these terms", fullWidth: true) {
                    let r: FranchiseBrands.Negotiation? = store.act({ $0.negotiateFranchise(brandID, ask: ask) }) ?? nil
                    result = r
                    if let c = r?.counter { ask = c }
                }
                if signable, let t = result?.terms {
                    QuietButton(title: "Sign this deal", fullWidth: true) { sign(t) }
                }
            }
            if signable, let t = result?.terms {
                Text("Entry fee \(cur.tidyShort(t.fee)), royalty \(Currency.percent(t.royalty, decimals: 1)) plus \(Currency.percent(t.marketing, decimals: 0)) marketing\(cover(t)).")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).padding(.horizontal, 2)
            }
        }
    }

    private func sign(_ t: FranchiseBrands.Terms) {
        store.act { $0.signFranchiseTerms(brandID, terms: t) }
        if store.engine?.franchiseAgreedTerms(brandID) != nil { Haptics.success(); store.show("Terms agreed. Start the company under the brand from the list.", tone: "good"); dismiss() }
        else { Haptics.warning(); store.show("The brand did not sign. Talk again.", tone: "warn") }
    }

    @ViewBuilder private func termSteppers(_ b: FranchiseBrands.Brand, _ bd: Trade?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            stepper("Entry fee", feeSteps, current: ask.fee, label: { v in v < 0 ? "Pay \(Int(-v * 100))% more" : v > 0 ? "\(Int(v * 100))% off" : "Standard" }) { ask.fee = $0 }
            CardLine()
            stepper("Royalty", royaltySteps, current: ask.royalty, label: { v in Currency.percent(max(0, b.royalty - v), decimals: 1) + (v == 0 ? " (standard)" : "") }) { ask.royalty = $0 }
            CardLine()
            stepper("Fit-out covered", [0, 1, 2].map { Double($0) }, current: Double(ask.cover), label: { ["None", "40%", "70%"][Int($0)] }) { ask.cover = Int($0) }
            if let bd, bd.premisesM2 > 0 {
                CardLine()
                stepper("Rent covered", [0, 1, 2].map { Double($0) }, current: Double(ask.rent), label: { ["None", "6 months", "12 months"][Int($0)] }) { ask.rent = Int($0) }
            }
            if let bd, bd.equipment.contains(where: { $0.vehicleModels != nil }) {
                CardLine()
                stepper("Vehicles", [0, 1].map { Double($0) }, current: Double(ask.vehicles), label: { $0 == 0 ? "You buy" : "They cover half" }) { ask.vehicles = Int($0) }
            }
        }
    }

    // MARK: Facts

    private func factItems(_ e: GameEngine, _ b: FranchiseBrands.Brand, _ cur: Currency) -> [KeyFigures.Item] {
        [
            .init(label: "Units open", value: "\(b.units)"),
            .init(label: "Entry fee", value: cur.tidyShort(e.franchiseEntryFee(b))),
            .init(label: "Royalty", value: Currency.percent(b.royalty, decimals: 1), sub: "of revenue"),
            .init(label: "Marketing fund", value: Currency.percent(b.marketingFund, decimals: 0)),
            .init(label: "Contract", value: "\(b.termYears) years"),
            .init(label: "Failing in 5 yrs", value: "\(Int(b.failPercent))%"),
        ]
    }

    private func factRows(_ e: GameEngine, _ b: FranchiseBrands.Brand, _ cur: Currency) -> some View {
        let stats = e.franchiseUnitStats(b)
        return VStack(alignment: .leading, spacing: 0) {
            FlatRow(label: "Setup support", value: ["None, you pay everything", "They cover about 40%", "They cover about 70%"][min(2, b.support)], rule: false)
            FlatRow(label: "Typical unit revenue", value: cur.tidyShort(stats.revenue) + " / wk")
            FlatRow(label: "Margin after fees", value: Currency.percent(stats.margin, decimals: 0))
            FlatRow(label: "Quality standard", value: b.standard >= 70 ? "Strict" : b.standard >= 58 ? "Firm" : "Relaxed")
        }
    }

    private func facts(_ e: GameEngine, _ b: FranchiseBrands.Brand) -> some View {
        let cur: Currency = e.homeCurrency
        return MoreBlock(title: "Facts", trailing: {
            Button(showFacts ? "Less" : "More") { showFacts.toggle() }.buttonStyle(TinyButtonStyle())
        }) {
            VStack(alignment: .leading, spacing: 10) {
                FigureStrip(items: factItems(e, b, cur), columns: 3)
                if showFacts {
                    CardLine()
                    factRows(e, b, cur)
                }
            }
        }
    }

    private func cover(_ t: FranchiseBrands.Terms) -> String {
        var parts: [String] = []
        if t.cover > 0 { parts.append("about \(["0%", "40%", "70%"][min(2, t.cover)]) of the set-up") }
        if t.rent > 0 { parts.append("\([0, 6, 12][min(2, t.rent)]) months of rent") }
        if t.vehicles != 0 { parts.append("half of the vehicles") }
        return parts.isEmpty ? "" : ", they cover " + parts.joined(separator: ", ")
    }

    private func arrow(_ glyph: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlyphView(glyph: glyph, size: 12, weight: 2, tint: Theme.gold)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                .contentShape(Circle())
        }.buttonStyle(.plain)
    }

    private func stepper(_ title: String, _ steps: [Double], current: Double, label: @escaping (Double) -> String, set: @escaping (Double) -> Void) -> some View {
        let i: Int = steps.firstIndex(where: { abs($0 - current) < 0.0001 }) ?? 0
        return HStack(spacing: 8) {
            Text(title).font(.system(size: 14)).foregroundStyle(Theme.ivory)
            Spacer(minLength: 6)
            arrow(Glyph.back) { set(steps[(i - 1 + steps.count) % steps.count]); result = nil }
            Text(label(steps[i])).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                .frame(minWidth: 104).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.8)
            arrow(Glyph.chevron) { set(steps[(i + 1) % steps.count]); result = nil }
        }.padding(.vertical, 8)
    }
}

/// Start the company under a brand whose terms you agreed.
struct StartFranchisedView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var brandID: String
    @State private var cityID = ""
    @State private var limited = true
    @State private var name = ""
    @State private var rentIndex: Int?
    @State private var buying = false
    @State private var pending: PendingAction?

    /// The money picture of the start, worked out once per render from the engine's plan.
    private struct StartFigures {
        var total: Double
        var fund: Double
        var short: Double
        var left: Double
        var available: Double
    }

    var body: some View {
        if let e = store.engine, let b = e.franchiseBrand(brandID), let t = e.franchiseAgreedTerms(brandID) {
            let cc: String = e.franchiseApplication(brandID)["country"].string
            let country = e.data.countries.resolve(cc.isEmpty ? e.state.homeCountryCode : cc, orHome: e.state.homeCountryCode)
            let cur = Currency(country: country, rates: ExchangeRates(drift: e.state.exchangeRates.values))
            let bd = e.data.catalog[b.tradeID]
            let appCity: String = e.franchiseApplication(brandID)["city"].string
            let city: String = cityID.isEmpty ? (appCity.isEmpty ? country.cities[0].id : appCity) : cityID
            let form: LegalForm = (limited || (bd?.needsLimitedCompany ?? false)) ? .limited : .soleTrader
            let pick = rentIndex.map { NewCompanyPlan.Pick(listingIndex: $0, buy: buying) }
            let fp = e.franchiseStartPlan(brandID: brandID, cityID: city, form: form, pick: pick)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    whereAndHow(country, city: city, needsLimited: bd?.needsLimitedCompany == true)
                    if let fp { plan(e, b, t, fp, cur: cur, city: city, form: form, pick: pick) }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .appScreen(title: "Start under \(b.name)", subtitle: "Entry fee \(cur.tidyShort(t.fee)) · royalty \(Currency.percent(t.royalty, decimals: 1)) · marketing \(Currency.percent(t.marketing, decimals: 0)) · \(b.termYears) years", tab: .group)
            .confirmAction($pending)
        } else {
            Text("These terms have expired. Meet the brand again.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func whereAndHow(_ country: Country, city: String, needsLimited: Bool) -> some View {
        MoreBlock("Where and how") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconCircle(glyph: Glyph.world, size: 34)
                    Picker("City", selection: Binding(get: { city }, set: { cityID = $0; rentIndex = nil })) { ForEach(country.cities) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                    Spacer(minLength: 0)
                }
                if needsLimited { Text("This trade needs a limited company.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted) }
                else { SegmentedPill(items: [false, true], title: { $0 ? "Limited company" : "Sole trader" }, selection: $limited) }
                Card(padding: 10, radius: Theme.Radius.table) {
                    TextField("Company name", text: $name).textFieldStyle(.plain).font(.system(size: 15))
                }
            }
        }
    }

    private func figures(_ e: GameEngine, _ fp: (plan: NewCompanyPlan, fee: Double)) -> StartFigures {
        let outlay: Double = fp.plan.estimate.personalOutlay
        let total: Double = fp.plan.total + fp.fee
        let liquid: Double = Payments.liquid(e.state)
        let fund: Double = max(0, min(total * 1.15, liquid - outlay))
        return StartFigures(total: total, fund: fund, short: max(0, total + outlay - liquid), left: max(0, liquid - outlay - fund), available: liquid)
    }

    @ViewBuilder private func plan(_ e: GameEngine, _ b: FranchiseBrands.Brand, _ t: FranchiseBrands.Terms, _ fp: (plan: NewCompanyPlan, fee: Double),
                                   cur: Currency, city: String, form: LegalForm, pick: NewCompanyPlan.Pick?) -> some View {
        let f: StartFigures = figures(e, fp)
        PremisesPicker(plan: fp.plan, cur: cur, rentIndex: $rentIndex, buying: $buying)
        HeroFigure(label: "Total to find", value: cur.tidyShort(f.total), note: "Estimate plus entry fee, before the brand's cover.")
        costCard(t, fp, f, cur)
        risks(b, t, f, cur)
        QuietButton(title: "Review and start", fullWidth: true) { confirm(b, t, fp, f, cur, city: city, form: form, pick: pick) }
    }

    private func costCard(_ t: FranchiseBrands.Terms, _ fp: (plan: NewCompanyPlan, fee: Double), _ f: StartFigures, _ cur: Currency) -> some View {
        let items: [KeyFigures.Item] = [
            .init(label: "You have", value: cur.tidyShort(f.available)),
            .init(label: "Left afterwards", value: cur.tidyShort(f.left), tint: f.left > 0 ? Theme.gain : Theme.caution),
        ]
        return MoreBlock("Start-up cost") {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: "Start-up estimate", value: cur.tidyShort(fp.plan.total), sub: "Documents, equipment, the place you picked, stock, first payroll.", rule: false)
                FlatRow(label: "Franchise entry fee", value: cur.tidyShort(fp.fee))
                if t.cover > 0 || t.rent > 0 || t.vehicles != 0 { FlatRow(label: "The brand covers", value: "part of the set-up", sub: "It arrives in the company's account when you start.", tint: Theme.gain) }
                CardLine().padding(.vertical, 8)
                FigureStrip(items: items, columns: 2)
            }
        }
    }

    private func risks(_ b: FranchiseBrands.Brand, _ t: FranchiseBrands.Terms, _ f: StartFigures, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Risks").capsLabel().padding(.horizontal, 2)
            NoteCard(text: "You pay \(Currency.percent(t.royalty, decimals: 1)) of sales as royalty and \(Currency.percent(t.marketing, decimals: 0)) to the brand's marketing for \(b.termYears) years. Leaving early means a buyout.", glyph: Glyph.reports)
            NoteCard(text: "The brand sets standards you must keep. The brand approves the place you pick; the equipment is set up with the standard choices.", glyph: Glyph.achievements)
            if f.short > 0 {
                NoteCard(text: "You are \(cur.tidyShort(f.short)) short. If the company cannot pay the entry fee it starts independent, without the brand.", glyph: Glyph.warning, tint: Theme.caution)
            }
            NoteCard(text: "It earns nothing until it is set up and open.", glyph: Glyph.clock)
        }
    }

    private func confirm(_ b: FranchiseBrands.Brand, _ t: FranchiseBrands.Terms, _ fp: (plan: NewCompanyPlan, fee: Double), _ f: StartFigures, _ cur: Currency,
                         city: String, form: LegalForm, pick: NewCompanyPlan.Pick?) {
        pending = PendingAction(title: "Start under \(b.name)?",
                                message: "\(cur.tidyShort(f.total)) to start, including the \(cur.tidyShort(fp.fee)) entry fee. \(cur.tidyShort(f.fund)) goes into the company from your cash now. You keep about \(cur.tidyShort(f.left)). Royalty \(Currency.percent(t.royalty, decimals: 1)) of sales for \(b.termYears) years.",
                                button: "Start it") {
            let r = store.act { $0.startFranchisedCompanyChoosingPremises(brandID: brandID, cityID: city, form: form, name: name, pick: pick, fundWith: f.fund) }
            switch r {
            case .success(let out)?:
                let late = out.premises == .notEnoughCash
                Haptics.success()
                store.show(late ? "Started under \(b.name), but the company could not pay for the place you picked. Choose premises under Equipment." : "Started under \(b.name).", tone: late ? "warn" : "good")
                store.openCompany(out.companyID); dismiss()
            case .failure(.banned(let why))?: Haptics.failure(); store.show(why, tone: "bad")
            case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You can't afford the registration costs yet.", tone: "warn")
            default: Haptics.warning(); store.show("Not possible here.", tone: "warn")
            }
        }
    }
}
