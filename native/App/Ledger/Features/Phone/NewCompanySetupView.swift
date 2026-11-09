import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// Everything the player has chosen so far for a new company; steps 2 and 3 both price it through the engine.
struct NewCompanyDraft: Equatable {
    var tradeID: String
    var cityID: String
    var name: String
    var pick: NewCompanyPlan.Pick?
    var choices = SetupChoices()
    /// The accountant the company is given; nil takes the standard one.
    var accountantID: Int? = nil

    /// The size the picker prices the trade at, so the figures here match the table to the penny.
    func size(_ e: GameEngine) -> Double? {
        guard let t = e.data.catalog[tradeID] else { return nil }
        let country = e.homeCountry
        let city: Country.City = country.cities.first { $0.id == cityID } ?? country.cities[0]
        return e.affordableStartSize(tradeID: tradeID, cityID: cityID) ?? CompanySetup.recommendedSize(t, city: city)
    }
    func plan(_ e: GameEngine) -> NewCompanyPlan? {
        guard let s = size(e) else { return nil }
        return e.newCompanyPlan(tradeID: tradeID, cityID: cityID, size: s, pick: pick, choices: choices)
    }
    func costs(_ e: GameEngine) -> StartUpCostBreakdown? {
        e.startUpCostBreakdown(tradeID: tradeID, cityID: cityID, premises: pick)
    }
    func monthly(_ e: GameEngine) -> MonthlyFixedCostEstimate? {
        e.monthlyFixedCostEstimate(tradeID: tradeID, cityID: cityID, premises: pick)
    }
}

/// New company, step 2 of 3 in detail (behind "Customise"): name, city, premises and each item, then the estimated
/// monthly cost after opening. Nothing is paid here; the bar goes to the review.
struct NewCompanyDetailedSetupView: View {
    private enum Way: String, Hashable { case rent = "Rent", buy = "Buy", home = "Home" }
    @EnvironmentObject var store: GameStore
    var tradeID: String
    @State var cityID: String
    @State private var name = ""
    @State private var way: Way = .rent
    @State private var placeIndex: Int?
    @State private var goReview = false
    @State private var choices = SetupChoices()
    @State private var accountantID: Int?

    init(tradeID: String, cityID: String) {
        self.tradeID = tradeID
        _cityID = State(initialValue: cityID)
    }

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[tradeID] {
            let country = e.homeCountry
            let basePlan: NewCompanyPlan? = NewCompanyDraft(tradeID: tradeID, cityID: cityID, name: "", pick: nil, choices: choices).plan(e)
            let pick: NewCompanyPlan.Pick? = currentPick(basePlan)
            let draft = NewCompanyDraft(tradeID: tradeID, cityID: cityID, name: name.trimmingCharacters(in: .whitespaces), pick: pick, choices: choices, accountantID: accountantID)
            let plan: NewCompanyPlan? = draft.plan(e)
            let costs: StartUpCostBreakdown? = draft.costs(e)
            let monthly: MonthlyFixedCostEstimate? = draft.monthly(e)
            let brands: [FranchiseBrands.Brand] = e.franchiseBrands().filter { $0.tradeID == t.id }
            let shown: String = draft.name.isEmpty ? t.name : draft.name
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    fields(t, country, costs)
                    AccountantStep(countryCode: e.state.homeCountryCode, currency: e.homeCurrency, accountantID: $accountantID)
                    if let plan { premisesBlock(plan) }
                    if let plan { PlanStatement(plan: plan, cur: e.homeCurrency, choices: $choices, onAlternative: { alt in applyAlternative(alt) }) }
                    if let monthly { monthlyCard(monthly) }
                    if !brands.isEmpty {
                        NavigationLink { TradeDetailView(tradeID: t.id, startUnderBrand: true) } label: {
                            LedgerRow(leading: .glyph(Glyph.market), title: "Under a franchise brand instead", subtitle: "\(brands.count) \(brands.count == 1 ? "brand is" : "brands are") looking for operators in this trade", chevron: true)
                        }.buttonStyle(AcctPressStyle())
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { registerBar(plan) }
            .appScreen(title: "Set up: \(shown)", subtitle: "Step 2 of 3 · customise", tab: .company)
            .navigationDestination(isPresented: $goReview) { NewCompanyReviewView(draft: draft) }
        } else {
            EmptyState(title: "This trade is not available.").appScreen(title: "Set up", tab: .company)
        }
    }

    private func applyAlternative(_ alt: PlanAlternative) {
        switch alt.id {
        case "rent": way = .rent
        default: break
        }
    }

    // MARK: Premises state

    private func currentPick(_ base: NewCompanyPlan?) -> NewCompanyPlan.Pick? {
        guard let base, base.premisesKind == .place else { return nil }
        let buying: Bool = way == .buy && (base.options.first { $0.index == (placeIndex ?? base.standardIndex) }?.canBuy ?? false)
        if placeIndex == nil && !buying { return nil }
        return NewCompanyPlan.Pick(listingIndex: placeIndex ?? base.standardIndex, buy: buying)
    }

    // MARK: Fields

    @ViewBuilder private func fields(_ t: Trade, _ country: Country, _ costs: StartUpCostBreakdown?) -> some View {
        let cities: [Country.City] = country.cities
        let cityName: String = cities.first { $0.id == cityID }?.name ?? "Home city"
        let taxNote: String = taxNote(country, costs)
        SharpTable {
            fieldRow("Name", hint: "Leave empty and one is chosen for you") {
                TextField(t.name, text: $name).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .textStyle(.body)
            }
            fieldRow("City", hint: "") {
                Menu {
                    ForEach(cities) { c in Button(c.name) { cityID = c.id; placeIndex = nil; way = .rent } }
                } label: {
                    HStack(spacing: 4) {
                        Text(cityName).textStyle(.body)
                        LedgerGlyph(glyph: Glyph.chevronDown, size: 12, tint: Theme.inkFaint)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(taxNote).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.tableLine).frame(height: 1) }
            fieldRow("Opening", hint: "Set it up, then open for business") {
                Text("After set-up").textStyle(.body, tint: Theme.inkSoft)
            }
        }
    }

    /// The tax note comes from the country's own data (corporate rate), not from fixed text.
    private func taxNote(_ country: Country, _ costs: StartUpCostBreakdown?) -> String {
        let pct = Int(saturating: (country.corporateTax * 100).rounded())
        let capital: String = (costs?.shareCapital ?? 0) > 0 ? " Share capital of \(store.money(costs?.shareCapital ?? 0)) is locked in the company." : ""
        return "The company pays \(pct)% corporation tax on profit." + capital
    }

    private func fieldRow<C: View>(_ label: String, hint: String, @ViewBuilder value: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).textStyle(.caption)
                Spacer(minLength: 12)
                value()
            }
            if !hint.isEmpty { Text(hint).textStyle(.caption, tint: Theme.inkFaint) }
        }
        .frame(minHeight: 28)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.tableLine).frame(height: 1) }
    }

    // MARK: Premises

    @ViewBuilder private func premisesBlock(_ plan: NewCompanyPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Premises").capsLabel()
            switch plan.premisesKind {
            case .none:
                Text("This trade needs no fixed premises, so there is no rent to pay.").textStyle(.body, tint: Theme.inkSoft)
            case .home:
                SegmentedPill(items: [Way.home], title: { $0.rawValue }, selection: .constant(Way.home))
                Text("It starts at home: no rent, no deposit. Once the team reaches four people morale and quality slip every week until you move into a workshop or office. You can do that later under Operations.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            case .place:
                placePicker(plan)
            }
        }
    }

    @ViewBuilder private func placePicker(_ plan: NewCompanyPlan) -> some View {
        let chosen: Int = placeIndex ?? plan.standardIndex
        let option: NewCompanyPlan.PremisesOption? = plan.options.first { $0.index == chosen }
        let canBuy: Bool = option?.canBuy ?? false
        let ways: [Way] = canBuy ? [.rent, .buy] : [.rent]
        let selection = Binding<Way>(get: { canBuy ? way : .rent }, set: { way = $0; if placeIndex == nil { placeIndex = chosen } })
        SegmentedPill(items: ways, title: { $0.rawValue }, selection: selection)
        ForEach(plan.options) { o in
            let up: Double = (way == .buy && canBuy && o.index == chosen) ? o.buyUpfront : o.rentUpfront
            let kind: String = store.engine?.data.catalog[plan.tradeID]?.premisesKind ?? "office"
            let places: String = Workplaces.places(kind: kind, squareMetres: o.squareMetres).map { (n: Int) -> String in " · \(n) places" } ?? ""
            let sub: String = "\(Int(o.squareMetres)) m²\(places) · \(store.money(o.monthlyRent)) a month · \(o.landlord)"
            ChoiceCard(title: o.name, subtitle: sub, trailing: store.money(up) + " up front", selected: o.index == chosen, thumb: ThumbSpec(kind: .premisesPhoto, key: ArtLibrary.premisesKey(kind: store.engine?.data.catalog[plan.tradeID]?.premisesKind ?? "office", squareMetres: o.squareMetres), glyph: Glyph.home, shape: .wide)) {
                placeIndex = o.index
                if !o.canBuy { way = .rent }
            }
        }
        if let o = option {
            if way == .buy && o.canBuy {
                Text("Buying: \(store.money(o.purchasePrice)). You pay \(store.money(o.downPayment)) down and \(store.money(o.fitOut)) to fit it out; the rest is a 15-year commercial mortgage. You own the place and pay no rent, but the money is tied up.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Renting: a deposit of \(store.money(o.deposit)) (three months, returned when you leave) and \(store.money(o.fitOut)) to fit it out. Moving later is possible.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
        if placeIndex == nil {
            Text("Nothing picked: the standard middle place is rented.").textStyle(.caption, tint: Theme.inkFaint)
        }
    }

    // MARK: Cost cards

    private func costCard(_ costs: StartUpCostBreakdown, _ plan: NewCompanyPlan) -> some View {
        let personal: Double = plan.available
        return VStack(alignment: .leading, spacing: 6) {
            Text("Cost today").capsLabel()
            ForEach(costs.lines) { l in amountLine(l.label, l.amount) }
            if costs.shareCapital > 0 { amountLine("Share capital (locked in the company)", costs.shareCapital) }
            Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 2)
            amountLine("Total", costs.total + costs.shareCapital, strong: true)
            HStack {
                Text("Paid from").textStyle(.caption)
                Spacer()
                Text("Your cash · \(store.money(personal))").textStyle(.caption, tint: Theme.ink, numeric: true)
            }
            if plan.registrationShortfall > 0 {
                Text("Your cash needs \(store.money(plan.registrationShortfall)) more for registration and share capital.")
                    .textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
            } else if plan.shortfall > 0 {
                Text("You are \(store.money(plan.shortfall)) short of the whole cost, so opening would wait for money.")
                    .textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func monthlyCard(_ m: MonthlyFixedCostEstimate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("After opening · monthly, estimate").capsLabel()
            ForEach(m.lines) { l in
                let label: String = l.id == "wages" ? "Wages for \(m.staffCount) \(m.staffCount == 1 ? "person" : "people")" : l.label
                amountLine(label, l.amount)
            }
            Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 2)
            amountLine("About", m.total, strong: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func amountLine(_ label: String, _ v: Double, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13.5, weight: strong ? .medium : .regular)).foregroundStyle(strong ? Theme.ivory : Theme.ivoryMuted)
            Spacer(minLength: 8)
            Text(store.money(v)).font(.system(size: 13.5, weight: strong ? .semibold : .regular).monospacedDigit()).foregroundStyle(Theme.ivory)
        }
    }

    /// Goes to the review: nothing is paid on this step.
    private func registerBar(_ plan: NewCompanyPlan?) -> some View {
        let reason: String? = plan == nil ? "This company can no longer be priced."
            : ((plan?.registrationShortfall ?? 0) > 0 ? "Needs \(store.money(plan?.registrationShortfall ?? 0)) more cash." : nil)
        return NewCompanyStepBar(title: "Review · \(store.money(plan?.payToday ?? 0))", blockedReason: reason, identifier: "new-company-review") { goReview = true }
    }
}

/// New company, step 3 of 3: one total, what is left and the running cost, then the details and risks before any money moves.
/// The engine does the registering; a refusal is shown as it is.
struct NewCompanyReviewView: View {
    @EnvironmentObject var store: GameStore
    var draft: NewCompanyDraft
    @State private var working = false
    @State private var refusal: String?

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[draft.tradeID], let plan = draft.plan(e) {
            let cityName: String = e.homeCountry.cities.first { $0.id == draft.cityID }?.name ?? "town"
            let monthly: MonthlyFixedCostEstimate? = draft.monthly(e)
            let company: String = draft.name.isEmpty ? t.name : draft.name
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    Figure(label: "Paid today from your cash", value: store.money(plan.payToday), note: "\(t.name) in \(cityName)", size: .display)
                    FigureRow(items: [
                        KeyFigures.Item(label: "Left after", value: store.money(plan.accountsAfter)),
                        KeyFigures.Item(label: "Your reserve", value: store.money(plan.personalReserve)),
                        KeyFigures.Item(label: "Monthly", value: monthly.map { "about " + store.money($0.total) } ?? "n/a")
                    ])
                    LedgerSection("The company") {
                        VStack(spacing: 0) {
                            line("Premises", premisesText(plan))
                        }
                    }
                    LedgerSection("The cost") {
                        VStack(spacing: 0) {
                            line("Needed now", store.money(plan.neededNow))
                            Hairline()
                            line("Recommended investment", store.money(plan.recommendedInvestment))
                            Hairline()
                            line("Of which must be paid", store.money(plan.mandatoryTotal))
                            Hairline()
                            line("Optional extras you chose", store.money(plan.optionalTotal))
                            Hairline()
                            line("Working capital", store.money(plan.workingCapital))
                            if plan.estimate.shareCapital > 0 {
                                Hairline()
                                line("Share capital (locked in)", store.money(plan.estimate.shareCapital))
                            }
                        }
                    }
                    if plan.shortfall > 0 || !plan.risks.isEmpty {
                        LedgerSection("Risks") {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                if plan.shortfall > 0 {
                                    Text("The company is \(store.money(plan.shortfall)) short of that scope: set-up pays the mandatory costs first, skips what the cash cannot carry and opening waits for money.")
                                        .textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
                                }
                                ForEach(Array(plan.risks.enumerated()), id: \.offset) { (_: Int, r: String) in
                                    Text(r.tidyMoney).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if let refusal {
                        Text(refusal).textStyle(.body, tint: Theme.loss).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("register-refusal")
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                let reason: String? = plan.registrationShortfall > 0 ? "Needs \(store.money(plan.registrationShortfall)) more cash." : (working ? "Registering…" : nil)
                NewCompanyStepBar(title: "Pay \(store.money(plan.payToday)) and start", blockedReason: reason, identifier: "new-company-pay") { register(e) }
            }
            .appScreen(title: "Register \(company)", subtitle: "Step 3 of 3 · check and pay", tab: .company)
        } else {
            EmptyState(title: "This company can no longer be priced.", message: "Go back and choose again.")
                .appScreen(title: "Register", tab: .company)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(label).textStyle(.caption)
            Spacer(minLength: Theme.Space.m)
            Text(value.tidyText).textStyle(.body, numeric: true).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    private func premisesText(_ plan: NewCompanyPlan) -> String {
        switch plan.premisesKind {
        case .none: return "None needed"
        case .home: return "Starts at home"
        case .place:
            let o = plan.options.first { $0.index == (plan.pick?.listingIndex ?? plan.standardIndex) }
            return ((plan.pick?.buy ?? false) ? "Buy: " : "Rent: ") + (o?.name ?? "a place")
        }
    }

    private func register(_ e: GameEngine) {
        working = true
        refusal = registerNewCompany(store, engine: e, draft: draft)
        working = false
    }
}
