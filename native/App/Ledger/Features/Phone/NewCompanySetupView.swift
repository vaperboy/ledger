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
    var form: LegalForm
    var name: String
    var pick: NewCompanyPlan.Pick?

    /// The size the picker prices the trade at, so the figures here match the table to the penny.
    func size(_ e: GameEngine) -> Double? {
        guard let t = e.data.catalog[tradeID] else { return nil }
        let country = e.homeCountry
        let city: Country.City = country.cities.first { $0.id == cityID } ?? country.cities[0]
        return CompanySetup.recommendedSize(t, city: city)
    }
    func plan(_ e: GameEngine) -> NewCompanyPlan? {
        guard let s = size(e) else { return nil }
        return e.newCompanyPlan(tradeID: tradeID, cityID: cityID, form: form, size: s, pick: pick)
    }
    func costs(_ e: GameEngine) -> StartUpCostBreakdown? {
        e.startUpCostBreakdown(tradeID: tradeID, cityID: cityID, legalForm: form, premises: pick)
    }
    func monthly(_ e: GameEngine) -> MonthlyFixedCostEstimate? {
        e.monthlyFixedCostEstimate(tradeID: tradeID, cityID: cityID, legalForm: form, premises: pick)
    }
}

/// New company, step 2 of 3: the details of the company. Name, city, legal form, premises, then the exact cost today and the estimated
/// monthly cost after opening. Nothing is paid here; "Register" goes to the review.
struct NewCompanySetupView: View {
    private enum Way: String, Hashable { case rent = "Rent", buy = "Buy", home = "Home" }
    private enum FormChoice: String, Hashable { case sole = "Sole trader", limited = "Limited company" }
    @EnvironmentObject var store: GameStore
    var tradeID: String
    @State var cityID: String
    @State private var name = ""
    @State private var limited = false
    @State private var way: Way = .rent
    @State private var placeIndex: Int?
    @State private var goReview = false

    init(tradeID: String, cityID: String) {
        self.tradeID = tradeID
        _cityID = State(initialValue: cityID)
    }

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[tradeID] {
            let country = e.homeCountry
            let form: LegalForm = (limited || t.needsLimitedCompany) ? .limited : .soleTrader
            let basePlan: NewCompanyPlan? = NewCompanyDraft(tradeID: tradeID, cityID: cityID, form: form, name: "", pick: nil).plan(e)
            let pick: NewCompanyPlan.Pick? = currentPick(basePlan)
            let draft = NewCompanyDraft(tradeID: tradeID, cityID: cityID, form: form, name: name.trimmingCharacters(in: .whitespaces), pick: pick)
            let plan: NewCompanyPlan? = draft.plan(e)
            let costs: StartUpCostBreakdown? = draft.costs(e)
            let monthly: MonthlyFixedCostEstimate? = draft.monthly(e)
            let brands: [FranchiseBrands.Brand] = e.franchiseBrands().filter { $0.tradeID == t.id }
            let shown: String = draft.name.isEmpty ? t.name : draft.name
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    fields(t, country, form, costs)
                    if let plan { premisesBlock(plan) }
                    if let costs, let plan { costCard(costs, plan) }
                    if let monthly { monthlyCard(monthly) }
                    if !brands.isEmpty {
                        NavigationLink { TradeDetailView(tradeID: t.id) } label: {
                            CardRow(glyph: Glyph.market, title: "Under a franchise brand instead", subtitle: "\(brands.count) \(brands.count == 1 ? "brand is" : "brands are") looking for operators in this trade")
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { registerBar(shown, plan) }
            .appScreen(title: "Set up: \(t.name)", subtitle: "Step 2 of 3 · details of the company", tab: .company)
            .navigationDestination(isPresented: $goReview) { NewCompanyReviewView(draft: draft) }
        } else {
            Text("This trade is not available.").foregroundStyle(Theme.ivoryMuted).appScreen(title: "Set up", tab: .company)
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

    @ViewBuilder private func fields(_ t: Trade, _ country: Country, _ form: LegalForm, _ costs: StartUpCostBreakdown?) -> some View {
        let cities: [Country.City] = country.cities
        let cityName: String = cities.first { $0.id == cityID }?.name ?? "Home city"
        let formChoice = Binding<FormChoice>(get: { form == .limited ? .limited : .sole }, set: { limited = $0 == .limited })
        let taxNote: String = taxNote(form, country, costs)
        SharpTable {
            fieldRow("Name", hint: "Leave empty and one is chosen for you") {
                TextField(t.name, text: $name).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .font(.system(size: 14)).foregroundStyle(Theme.ivory)
            }
            fieldRow("City", hint: "") {
                Menu {
                    ForEach(cities) { c in Button(c.name) { cityID = c.id; placeIndex = nil; way = .rent } }
                } label: {
                    HStack(spacing: 4) {
                        Text(cityName).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Legal form").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                if t.needsLimitedCompany {
                    Text("Limited company (this trade needs one)").font(.system(size: 14)).foregroundStyle(Theme.ivory)
                } else {
                    SegmentedPill(items: [FormChoice.sole, FormChoice.limited], title: { $0.rawValue }, selection: formChoice)
                }
                Text(taxNote).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.tableLine).frame(height: 1) }
            fieldRow("Opening", hint: "Set it up, then open for business") {
                Text("After set-up").font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
            }
        }
    }

    /// The tax note comes from the country's own data (corporate rate), not from fixed text.
    private func taxNote(_ form: LegalForm, _ country: Country, _ costs: StartUpCostBreakdown?) -> String {
        if form == .soleTrader {
            return "Simple and cheap. Profit is taxed as your own income, and you are personally liable for debts."
        }
        let pct = Int((country.corporateTax * 100).rounded())
        let capital: String = (costs?.shareCapital ?? 0) > 0 ? " Share capital of \(store.money(costs?.shareCapital ?? 0)) is locked in the company." : ""
        return "Your personal assets are protected. The company pays \(pct)% corporation tax on profit, and more tax when you take it out." + capital
    }

    private func fieldRow<C: View>(_ label: String, hint: String, @ViewBuilder value: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                Spacer(minLength: 12)
                value()
            }
            if !hint.isEmpty { Text(hint).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
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
                Text("This trade needs no fixed premises, so there is no rent to pay.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            case .home:
                SegmentedPill(items: [Way.home], title: { $0.rawValue }, selection: .constant(Way.home))
                Text("It starts at home: no rent, no deposit. Once the team reaches four people morale and quality slip every week until you move into a workshop or office. You can do that later under Operations.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
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
            let sub: String = "\(Int(o.squareMetres)) m² · \(store.money(o.monthlyRent)) a month · \(o.landlord)"
            ChoiceCard(title: o.name, subtitle: sub, trailing: store.money(up) + " up front", selected: o.index == chosen) {
                placeIndex = o.index
                if !o.canBuy { way = .rent }
            }
        }
        if let o = option {
            if way == .buy && o.canBuy {
                Text("Buying: \(store.money(o.purchasePrice)). You pay \(store.money(o.downPayment)) down and \(store.money(o.fitOut)) to fit it out; the rest is a 15-year commercial mortgage. You own the place and pay no rent, but the money is tied up.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Renting: a deposit of \(store.money(o.deposit)) (three months, returned when you leave) and \(store.money(o.fitOut)) to fit it out. Moving later is possible.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
        if placeIndex == nil {
            Text("Nothing picked: the standard middle place is rented.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
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
                Text("Paid from").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                Text("Personal account · \(store.money(personal))").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
            if plan.registrationShortfall > 0 {
                Text("Your current account needs \(store.money(plan.registrationShortfall)) more for registration and share capital. Move money from savings in Bank.")
                    .font(.system(size: 12)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
            } else if plan.shortfall > 0 {
                Text("You are \(store.money(plan.shortfall)) short of the whole cost, so opening would wait for money.")
                    .font(.system(size: 12)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
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

    private func registerBar(_ shown: String, _ plan: NewCompanyPlan?) -> some View {
        let ok: Bool = plan != nil && (plan?.registrationShortfall ?? 0) <= 0
        return HStack {
            QuietButton(title: "Register \(shown) ›", fullWidth: true) { if ok { goReview = true } }
                .opacity(ok ? 1 : 0.4).disabled(!ok)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Theme.page)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// New company, step 3 of 3: a compact confirmation before any money moves. The engine does the registering; a refusal is shown as it is.
struct NewCompanyReviewView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var draft: NewCompanyDraft
    @State private var working = false
    @State private var refusal: String?

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[draft.tradeID], let plan = draft.plan(e) {
            let cityName: String = e.homeCountry.cities.first { $0.id == draft.cityID }?.name ?? "town"
            let costs: StartUpCostBreakdown? = draft.costs(e)
            let monthly: MonthlyFixedCostEstimate? = draft.monthly(e)
            let company: String = draft.name.isEmpty ? t.name : draft.name
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 8) {
                        line("Company", company)
                        line("Trade", "\(t.name) in \(cityName)")
                        line("Legal form", draft.form == .limited ? "Limited company" : "Sole trader")
                        line("Premises", premisesText(plan))
                        line("Start-up cost", store.money((costs?.total ?? plan.total)))
                        if plan.estimate.shareCapital > 0 { line("Share capital (locked in)", store.money(plan.estimate.shareCapital)) }
                        line("Paid from", "Personal account")
                        line("Left in your accounts", store.money(plan.personalLeft))
                        if let monthly { line("Monthly after opening", "about " + store.money(monthly.total)) }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    if plan.shortfall > 0 {
                        Text("You are \(store.money(plan.shortfall)) short of the whole cost, so opening will wait for money.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(plan.risks.enumerated()), id: \.offset) { _, r in
                        Text(r.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    if let refusal {
                        Text(refusal).font(.system(size: 13)).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("register-refusal")
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                let blocked: Bool = plan.registrationShortfall > 0 || working
                HStack(spacing: 12) {
                    QuietButton(title: "Back") { dismiss() }
                    QuietButton(title: "Pay \(store.money(plan.total + plan.estimate.shareCapital)) and register", fullWidth: true) { register(e, t, plan) }
                        .opacity(blocked ? 0.4 : 1).disabled(blocked)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Theme.page)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            }
            .appScreen(title: "Register \(company)", subtitle: "Step 3 of 3 · check and pay", tab: .company)
        } else {
            Text("This company can no longer be priced. Go back and choose again.").foregroundStyle(Theme.ivoryMuted)
                .appScreen(title: "Register", tab: .company)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer(minLength: 12)
            Text(value.tidyText).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory).multilineTextAlignment(.trailing)
        }
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

    private func register(_ e: GameEngine, _ t: Trade, _ plan: NewCompanyPlan) {
        working = true
        refusal = nil
        let d = draft
        let size: Double? = d.size(e)
        let fund: Double = plan.intoCompany
        let nm: String? = d.name.isEmpty ? nil : d.name
        let r = store.act { $0.startCompanyChoosingPremises(tradeID: d.tradeID, cityID: d.cityID, form: d.form, size: size, name: nm, pick: d.pick, fundWith: fund) }
        working = false
        switch r {
        case .success(let out)?:
            Haptics.success()
            var text = "Registered. Set it up, then open for business."
            var tone = "good"
            if out.premises == .notEnoughCash { text = "Registered, but the company could not pay for the place you picked. Choose premises under Setup."; tone = "warn" }
            else if !out.setupNotes.isEmpty { text = "Registered. Some set-up is left (usually cash): see the checklist in the company."; tone = "warn" }
            store.show(text, tone: tone)
            store.openCompany(out.companyID, section: .setup)
        case .failure(.banned(let why))?:
            Haptics.failure(); refusal = why
        case .failure(.notYetAvailable)?:
            Haptics.warning(); refusal = "This kind of business is coming in a later update."
        case .failure(.notEnoughCash)?:
            Haptics.warning(); refusal = "You can't afford the registration costs yet."
        case .failure(.notAllowedHere)?:
            Haptics.warning(); refusal = "This company can't be started here."
        case nil:
            refusal = "Nothing happened: the game is not ready. Try again."
        }
    }
}
