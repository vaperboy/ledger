import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

struct TradeDetailView: View {
    private enum Way: String, CaseIterable, Hashable { case independent = "On your own", brand = "Under a brand" }
    @EnvironmentObject var store: GameStore
    var tradeID: String
    @State private var way: Way = .independent
    @State private var cityID = ""
    @State private var size = 1.0
    @State private var sizeSet = false
    @State private var name = ""
    @State private var rentIndex: Int?
    @State private var buying = false
    @State private var pending: PendingAction?
    @State private var choices = SetupChoices()
    @State private var channel: SalesChannel = .consumers

    init(tradeID: String, startUnderBrand: Bool = false) {
        self.tradeID = tradeID
        _way = State(initialValue: startUnderBrand ? .brand : .independent)
    }

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[tradeID] {
            let country = e.homeCountry
            let cur = e.homeCurrency
            let city = cityID.isEmpty ? e.state.player.cityID : cityID
            let cityName = country.cities.first { $0.id == city }?.name ?? "town"
            let ban = CompanySetup.banReason(t.id, country: country) ?? (SpecialFamilies.isStartable(t) ? nil : "This kind of business is coming in a later update.")
            let pick = rentIndex.map { NewCompanyPlan.Pick(listingIndex: $0, buy: buying) }
            let plan = ban == nil ? e.newCompanyPlan(tradeID: t.id, cityID: city, size: size, pick: pick, choices: choices) : nil
            let brands = e.franchiseBrands().filter { $0.tradeID == t.id }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    summary(t, plan, ban, cur)
                    if !brands.isEmpty {
                        SegmentedPill(items: Way.allCases, title: { $0 == .brand ? "Under a brand (\(brands.count))" : $0.rawValue }, selection: $way)
                    }
                    if way == .brand && !brands.isEmpty {
                        brandList(e, brands, cur)
                    } else {
                        whereAndHow(t, country, city)
                        if let plan {
                            premises(t, plan, cur)
                            PlanStatement(plan: plan, cur: cur, choices: $choices, onAlternative: { alt in applyAlternative(alt, t) })
                            SalesChannelPicker(tradeID: tradeID, channel: $channel)
                            risks(plan)
                            PrimaryAction(title: "Review and start · \(cur.tidyShort(plan.neededNow))",
                                          blockedReason: plan.registrationShortfall > 0 ? "Your cash is \(cur.tidyShort(plan.registrationShortfall)) short for registration and share capital." : nil) {
                                pending = confirmation(e, t, plan, city, cityName, cur)
                            }
                        } else if ban == nil {
                            EmptyState(title: "This trade cannot be priced here.", centered: false)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissable()
            .appScreen(title: t.name, subtitle: way == .brand ? "Under a franchise brand" : t.category, tab: .company)
            .confirmAction($pending)
            .onAppear { if !sizeSet { size = e.affordableStartSize(tradeID: t.id, cityID: city) ?? CompanySetup.recommendedSize(t, city: country.cities.first { $0.id == city } ?? country.cities[0]); choices = e.suggestedChoices(tradeID: t.id, cityID: city, size: size); sizeSet = true } }
        }
    }

    private func summary(_ t: Trade, _ plan: NewCompanyPlan?, _ ban: String?, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(t.blurb.tidyMoney).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            if let ban { Chip(text: ban, tint: Theme.loss, symbol: "nosign") }
            if let plan { fundingGauge(plan, cur) }
        }
    }

    private func fundingGauge(_ plan: NewCompanyPlan, _ cur: Currency) -> some View {
        let covered: Double = plan.total > 0 ? min(1, max(0, plan.available / plan.total)) : 1
        let tint: Color = plan.shortfall > 0 ? Theme.loss : Theme.gain
        let verdict: String = plan.shortfall > 0 ? "Short by \(cur.tidyShort(plan.shortfall)): opening waits for money" : "Funded, \(cur.tidyShort(plan.personalLeft)) left for you"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Start-up cost").capsLabel()
                Spacer(minLength: 8)
                Text(cur.tidyShort(plan.total)).textStyle(.figure, numeric: true)
            }
            ProgressLine(fraction: covered, tint: tint, height: 6)
            HStack {
                Text("You have \(cur.tidyShort(plan.available))").textStyle(.caption)
                Spacer(minLength: 8)
                Text(verdict).font(.system(size: 12, weight: .medium)).foregroundStyle(tint).multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func whereAndHow(_ t: Trade, _ country: Country, _ city: String) -> some View {
        CardSection("Where and how") {
            Picker("City", selection: Binding(get: { city }, set: { cityID = $0; rentIndex = nil })) { ForEach(country.cities) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
            CardLine()
            Text("Needs share capital and a registration fee.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            if t.maxSize > t.minSize {
                CardLine()
                Stepper(value: $size, in: t.minSize...t.maxSize, step: 0.5) { Text("Size \(size, specifier: "%.1f")").textStyle(.body) }
            }
            CardLine()
            LedgerField(placeholder: "Company name (optional)", text: $name, onSubmit: { KeyboardDismiss.hide() })
        }
    }

    @ViewBuilder private func premises(_ t: Trade, _ plan: NewCompanyPlan, _ cur: Currency) -> some View {
        PremisesPicker(plan: plan, cur: cur, rentIndex: $rentIndex, buying: $buying)
    }

    private static let costColumns: [TableColumn] = [TableColumn(title: "Cost line"), TableColumn(title: "Amount", width: 96)]

    private struct CostLine: Identifiable { var id: String { label }; var label: String; var amount: String }

    @ViewBuilder private func costLines(_ plan: NewCompanyPlan, _ cur: Currency) -> some View {
        let est = plan.estimate
        let items: [(String, Double)] = [
            ("Permits and documents", est.documents), ("Equipment", est.equipment), ("Vehicles (down payment)", est.vehicles),
            ("Premises", plan.premisesCost), ("Opening stock", est.stock), ("First payroll", est.firstPayroll),
            ("Registration", est.registration), ("First property (deposit and costs)", est.property),
            ("Waiting for a licence", est.wait), ("Working buffer", est.buffer), ("Abroad", est.abroad)
        ]
        let shown: [CostLine] = items.filter { $0.1 > 0 }.map { CostLine(label: $0.0, amount: cur.tidyShort($0.1)) }
        let leftTint: Color = plan.personalLeft > 0 ? Theme.gain : Theme.caution
        SharpTable {
            TableHeader(columns: Self.costColumns)
            ForEach(shown) { l in TableRow(columns: Self.costColumns, title: l.label, values: [l.amount]) }
            TableRow(columns: Self.costColumns, title: "Total", values: [cur.tidyShort(plan.total)], selected: true)
            if est.shareCapital > 0 {
                TableRow(columns: Self.costColumns, title: "Share capital", note: "From your account, on top of the cost above.", values: [cur.tidyShort(est.shareCapital)])
            }
            TableRow(columns: Self.costColumns, title: "Set aside for the start", note: "The cost with a 15% margin, as far as your money goes.", values: [cur.tidyShort(plan.intoCompany)])
            TableRow(columns: Self.costColumns, title: "Left in your account", values: [cur.tidyShort(plan.personalLeft)], valueTints: [leftTint])
        }
    }

    @ViewBuilder private func risks(_ plan: NewCompanyPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Risks").capsLabel().padding(.bottom, 6)
            ForEach(Array(plan.risks.enumerated()), id: \.offset) { n, r in
                if n > 0 { Hairline() }
                HStack(alignment: .top, spacing: 10) {
                    GlyphView(glyph: Glyph.warning, size: 16, weight: 1.4, tint: Theme.caution)
                    Text(r.tidyMoney).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyAlternative(_ alt: PlanAlternative, _ t: Trade) {
        switch alt.id {
        case "rent": buying = false
        case "smaller": size = max(t.minSize, size - 0.5)
        default: break
        }
    }

    @ViewBuilder private func brandList(_ e: GameEngine, _ brands: [FranchiseBrands.Brand], _ cur: Currency) -> some View {
        CardSection("Franchise brands for this trade") {
            Text("A known brand brings customers and support, and takes an entry fee and a royalty. You apply, they answer in a week or three, you agree the terms, then you start under the brand.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(brands.enumerated()), id: \.element.id) { n, b in
                if n > 0 { CardLine() }
                FranchiseBrandRow(brand: b)
            }
        }
    }

    private func confirmation(_ e: GameEngine, _ t: Trade, _ plan: NewCompanyPlan, _ city: String, _ cityName: String, _ cur: Currency) -> PendingAction {
        let place: String = {
            switch plan.premisesKind {
            case .none: return "No premises."
            case .home: return "Starts at home."
            case .place:
                let o = plan.options.first { $0.index == (plan.pick?.listingIndex ?? plan.standardIndex) }
                return ((plan.pick?.buy ?? false) ? "Buying " : "Renting ") + (o?.name ?? "a place") + "."
            }
        }()
        let msg = "Needed now: \(cur.tidyShort(plan.neededNow)) (recommended investment \(cur.tidyShort(plan.recommendedInvestment)); nothing is bought or hired for you, you equip and staff it yourself). Of that \(cur.tidyShort(plan.mandatoryTotal)) that must be paid, \(cur.tidyShort(plan.optionalTotal)) of optional extras you chose and \(cur.tidyShort(plan.workingCapital)) of working capital. \(cur.tidyShort(plan.intoCompany)) goes into the company from your cash now" + (plan.estimate.shareCapital > 0 ? ", plus \(cur.tidyShort(plan.estimate.shareCapital)) share capital" : "") + ". You keep \(cur.tidyShort(plan.accountsAfter)) (your reserve is \(cur.tidyShort(plan.personalReserve))). \(place) " +
            (plan.shortfall > 0 ? "The company is \(cur.tidyShort(plan.shortfall)) short of that scope, so set-up skips what the cash cannot carry and opening waits for money. " : "") +
            "Risk: it earns nothing until it is set up and open."
        let pick = plan.pick
        let fund = plan.intoCompany
        let nm = name.trimmingCharacters(in: .whitespaces)
        let sz = size
        var chosen = choices
        chosen.channel = channel
        return PendingAction(title: "Start \(t.name) in \(cityName)?", message: msg.tidyMoney, button: "Start it", amount: plan.total, currency: cur) {
            let r = store.act { $0.startCompanyChoosingPremises(tradeID: t.id, cityID: city, size: sz, name: nm.isEmpty ? nil : nm, pick: pick, choices: chosen) }
            switch r {
            case .success(let out)?:
                Haptics.success()
                PlayerHistory.noteStarted()
                var text = "Started. Set it up, then open for business."
                if out.premises == .notEnoughCash { text = "Started, but the company could not pay for the place you picked. Choose premises in AirStay." }
                else if !out.skipped.isEmpty { text = "Started. Left for you to decide: " + out.skipped.map { $0.title }.prefix(3).joined(separator: ", ") + (out.skipped.count > 3 ? " and more." : ".") }
                else if !out.setupNotes.isEmpty { text = "Started. Some set-up is left (usually cash): see the checklist in the company." }
                store.show(text, tone: out.premises == .notEnoughCash || !out.setupNotes.isEmpty || !out.skipped.isEmpty ? "warn" : "good")
                store.openCompany(out.companyID)
            case .failure(.banned(let why))?: Haptics.failure(); store.show(why, tone: "bad")
            case .failure(.notYetAvailable)?: store.show("Coming in a later update.", tone: "warn")
            case .failure(.notEnoughCash)?: Haptics.warning(); store.show("Not enough cash for the registration costs.", tone: "warn")
            default: Haptics.warning(); store.show("Not possible here.", tone: "warn")
            }
        }
    }
}

struct PremisesPicker: View {
    @EnvironmentObject var store: GameStore
    var plan: NewCompanyPlan
    var cur: Currency
    @Binding var rentIndex: Int?
    @Binding var buying: Bool

    var body: some View {
        CardSection("Premises") {
            switch plan.premisesKind {
            case .none:
                Text("This trade needs no fixed premises, so there is no rent to pay.").popupText(.subtitle)
            case .home:
                Text("It starts at home: no rent, no deposit. Once the team reaches four people morale and quality slip every week until you move into a workshop or office. You can do that later under Operations.")
                    .popupText(.subtitle)
            case .place:
                placeChoices
            }
        }
    }

    @ViewBuilder private var placeChoices: some View {
        let chosen = rentIndex ?? plan.standardIndex
        ForEach(plan.options) { o in
            ChoiceCard(title: o.name, subtitle: "\(Int(o.squareMetres)) m² · \(cur.tidyShort(o.monthlyRent)) a month · \(o.landlord)",
                       trailing: cur.tidyShort(buying && o.index == chosen ? o.buyUpfront : o.rentUpfront) + " up front", selected: o.index == chosen, thumb: premisesThumb(o)) {
                rentIndex = o.index
                if !o.canBuy { buying = false }
            }
        }
        if let o = plan.options.first(where: { $0.index == chosen }) {
            let modes: [Bool] = o.canBuy ? [false, true] : [false]
            SegmentedPill(items: modes, title: { $0 ? "Buy" : "Rent" }, selection: Binding(get: { buying }, set: { buying = $0; if rentIndex == nil { rentIndex = chosen } }))
            Text(modeNote(o)).popupText(.caption)
            if rentIndex == nil { Text("Nothing picked: the standard middle place is rented.").popupText(.caption) }
        }
    }

    private func premisesThumb(_ o: NewCompanyPlan.PremisesOption) -> ThumbSpec {
        let kind: String = store.engine?.data.catalog[plan.tradeID]?.premisesKind ?? "office"
        return ThumbSpec(kind: .premisesPhoto, key: ArtLibrary.premisesKey(kind: kind, squareMetres: o.squareMetres, variant: o.index), glyph: Glyph.home, shape: .wide)
    }

    private func modeNote(_ o: NewCompanyPlan.PremisesOption) -> String {
        if buying {
            return "Buying: \(cur.tidyShort(o.purchasePrice)). You pay \(cur.tidyShort(o.downPayment)) down and \(cur.tidyShort(o.fitOut)) to fit it out; the rest is a 15-year commercial mortgage. You own the place and pay no rent, but the money is tied up."
        }
        return "Renting: a deposit of \(cur.tidyShort(o.deposit)) (three months, returned when you leave) and \(cur.tidyShort(o.fitOut)) to fit it out. Then \(cur.tidyShort(o.monthlyRent)) a month. Moving later is possible."
    }
}
