import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// Start one trade: how (on your own or under a franchise brand), where, which legal form and size, which premises, then the whole
/// cost, what is left and the risks, before anything is confirmed. All numbers come from `GameEngine.newCompanyPlan`.
struct TradeDetailView: View {
    private enum Way: String, CaseIterable, Hashable { case independent = "On your own", brand = "Under a brand" }
    @EnvironmentObject var store: GameStore
    var tradeID: String
    @State private var way: Way = .independent
    @State private var cityID = ""
    @State private var limited = false
    @State private var size = 1.0
    @State private var sizeSet = false
    @State private var name = ""
    @State private var rentIndex: Int?
    @State private var buying = false
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[tradeID] {
            let country = e.homeCountry
            let cur = e.homeCurrency
            let form: LegalForm = (limited || t.needsLimitedCompany) ? .limited : .soleTrader
            let city = cityID.isEmpty ? e.state.player.cityID : cityID
            let cityName = country.cities.first { $0.id == city }?.name ?? "town"
            let ban = CompanySetup.banReason(t.id, country: country) ?? (SpecialFamilies.isStartable(t) ? nil : "This kind of business is coming in a later update.")
            let pick = rentIndex.map { NewCompanyPlan.Pick(listingIndex: $0, buy: buying) }
            let plan = ban == nil ? e.newCompanyPlan(tradeID: t.id, cityID: city, form: form, size: size, pick: pick) : nil
            let brands = e.franchiseBrands().filter { $0.tradeID == t.id }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    summary(t, plan, ban, cur)
                    if !brands.isEmpty {
                        SectionTabs(items: Way.allCases, title: { $0 == .brand ? "Under a brand (\(brands.count))" : $0.rawValue }, selection: $way)
                            .padding(.horizontal, -Theme.Space.margin)
                    }
                    if way == .brand && !brands.isEmpty {
                        brandList(e, brands, cur)
                    } else {
                        whereAndHow(t, country, city, form)
                        if let plan {
                            premises(t, plan, cur)
                            costLines(plan, cur)
                            risks(plan)
                            if plan.registrationShortfall > 0 {
                                Text("Your current account needs \(cur.tidyShort(plan.registrationShortfall)) more for registration and share capital before this company can be registered. Move money from savings in Bank.")
                                    .font(.caption).foregroundStyle(Theme.caution)
                            }
                            Button("Review and start") { pending = confirmation(e, t, plan, form, city, cityName, cur) }
                                .buttonStyle(GoldButtonStyle()).disabled(plan.registrationShortfall > 0)
                        } else if ban == nil {
                            Text("This trade cannot be priced here.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                        }
                        if brands.isEmpty {
                            Text("No franchise brand is looking for operators in this trade right now. Another way in: buying a rival that is already trading, from the rival's page under Market.")
                                .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle(t.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmAction($pending)
            .onAppear { if !sizeSet { size = CompanySetup.recommendedSize(t, city: country.cities.first { $0.id == city } ?? country.cities[0]); sizeSet = true } }
        }
    }

    // MARK: Summary first

    private func summary(_ t: Trade, _ plan: NewCompanyPlan?, _ ban: String?, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                IconBadge(symbol: TradeSymbol.of(family: t.family), tint: Theme.gold, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                    Text(t.category).font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
            }
            Text(t.blurb.tidyMoney).font(.bodyText).foregroundStyle(Theme.ivoryMuted)
            if let ban { Chip(text: ban, tint: Theme.loss, symbol: "nosign") }
            if let plan {
                KeyFigures(items: [
                    .init(label: "Start-up cost", value: cur.tidyShort(plan.total), sub: "everything included"),
                    .init(label: "You have", value: cur.tidyShort(plan.available), sub: "account and savings"),
                    plan.shortfall > 0 ? .init(label: "Short by", value: cur.tidyShort(plan.shortfall), tint: Theme.loss, sub: "opening waits for money")
                                       : .init(label: "Left for you", value: cur.tidyShort(plan.personalLeft), tint: Theme.gain, sub: "after it is funded")
                ])
            }
        }
    }

    // MARK: Where and how

    @ViewBuilder private func whereAndHow(_ t: Trade, _ country: Country, _ city: String, _ form: LegalForm) -> some View {
        LedgerSection("Where and how") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Picker("City", selection: Binding(get: { city }, set: { cityID = $0; rentIndex = nil })) { ForEach(country.cities) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                if t.needsLimitedCompany { Text("This trade needs a limited company.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                else {
                    Picker("Legal form", selection: $limited) { Text("Sole trader").tag(false); Text("Limited company").tag(true) }.pickerStyle(.segmented)
                    Text(limited ? "Your personal assets are protected; profits are taxed in the company and again when paid out. Needs share capital and a registration fee."
                                 : "Simple and cheap. You are personally liable for debts; profit is taxed as your income.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
                if t.maxSize > t.minSize {
                    Stepper(value: $size, in: t.minSize...t.maxSize, step: 0.5) { Text("Size \(size, specifier: "%.1f")").font(.bodyText) }
                    Text("A bigger company needs more equipment, people and space, and costs more to start.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
                TextField("Company name (optional)", text: $name).textFieldStyle(.plain).font(.system(size: 15)).padding(.vertical, 6).overlay(alignment: .bottom) { Hairline() }
            }
        }
    }

    // MARK: Premises

    @ViewBuilder private func premises(_ t: Trade, _ plan: NewCompanyPlan, _ cur: Currency) -> some View {
        LedgerSection("Premises") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                switch plan.premisesKind {
                case .none:
                    Text("This trade needs no fixed premises, so there is no rent to pay.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                case .home:
                    Text("It starts at home: no rent, no deposit. Once the team reaches four people morale and quality slip every week until you move into a workshop or office. You can do that later under Operations.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                case .place:
                    let chosen = rentIndex ?? plan.standardIndex
                    ForEach(plan.options) { o in
                        Button { rentIndex = o.index; if !o.canBuy { buying = false } } label: {
                            ListRow(symbol: o.index == chosen ? "checkmark.circle.fill" : "circle", tint: o.index == chosen ? Theme.gold : Theme.ivoryMuted,
                                    title: o.name, subtitle: "\(Int(o.squareMetres)) m² · \(cur.tidyShort(o.monthlyRent)) a month · \(o.landlord)",
                                    trailing: cur.tidyShort(buying && o.index == chosen ? o.buyUpfront : o.rentUpfront), trailingSub: "up front")
                        }.buttonStyle(.plain)
                    }
                    if let o = plan.options.first(where: { $0.index == chosen }) {
                        Picker("Rent or buy", selection: Binding(get: { buying }, set: { buying = $0; if rentIndex == nil { rentIndex = chosen } })) {
                            Text("Rent").tag(false)
                            if o.canBuy { Text("Buy").tag(true) }
                        }.pickerStyle(.segmented)
                        if buying {
                            Text("Buying: \(cur.tidyShort(o.purchasePrice)). You pay \(cur.tidyShort(o.downPayment)) down and \(cur.tidyShort(o.fitOut)) to fit it out; the rest is a 15-year commercial mortgage. You own the place and pay no rent, but the money is tied up.")
                                .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        } else {
                            Text("Renting: a deposit of \(cur.tidyShort(o.deposit)) (three months, returned when you leave) and \(cur.tidyShort(o.fitOut)) to fit it out. Then \(cur.tidyShort(o.monthlyRent)) a month. Moving later is possible.")
                                .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        if !(rentIndex != nil) { Text("Nothing picked: the standard middle place is rented.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                    }
                }
            }
        }
    }

    // MARK: Cost, risks

    @ViewBuilder private func costLines(_ plan: NewCompanyPlan, _ cur: Currency) -> some View {
        let est = plan.estimate
        LedgerSection(title: "Start-up cost", trailing: { Text(cur.tidyShort(plan.total)).font(.figure(15)).foregroundStyle(Theme.ivory) }) {
            VStack(spacing: 0) {
                line("Permits and documents", est.documents, cur, first: true)
                line("Equipment", est.equipment, cur)
                line("Vehicles (down payment)", est.vehicles, cur)
                line("Premises", plan.premisesCost, cur)
                line("Opening stock", est.stock, cur)
                line("First payroll", est.firstPayroll, cur)
                line("Registration", est.registration, cur)
                line("First property (deposit and costs)", est.property, cur)
                line("Waiting for a licence", est.wait, cur)
                line("Working buffer", est.buffer, cur)
                line("Abroad", est.abroad, cur)
                if est.shareCapital > 0 { FlatRow(label: "Share capital (stays in the company)", value: cur.tidyShort(est.shareCapital), sub: "From your account, on top of the cost above.") }
                FlatRow(label: "Put into the company from your cash", value: cur.tidyShort(plan.intoCompany), sub: "The cost with a 15% margin, as far as your money goes.")
                FlatRow(label: "Left in your accounts afterwards", value: cur.tidyShort(plan.personalLeft), tint: plan.personalLeft > 0 ? Theme.gain : Theme.caution)
            }
        }
    }

    @ViewBuilder private func line(_ label: String, _ v: Double, _ cur: Currency, first: Bool = false) -> some View {
        if v > 0 { FlatRow(label: label, value: cur.tidyShort(v), rule: !first) }
    }

    @ViewBuilder private func risks(_ plan: NewCompanyPlan) -> some View {
        LedgerSection("Risks") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.risks.enumerated()), id: \.offset) { _, r in
                    Text(r.tidyMoney).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Brands

    @ViewBuilder private func brandList(_ e: GameEngine, _ brands: [FranchiseBrands.Brand], _ cur: Currency) -> some View {
        LedgerSection("Franchise brands for this trade") {
            VStack(alignment: .leading, spacing: 4) {
                Text("A known brand brings customers and support, and takes an entry fee and a royalty. You apply, they answer in a week or three, you agree the terms, then you start under the brand.")
                    .font(.caption).foregroundStyle(Theme.ivoryMuted)
                ForEach(Array(brands.enumerated()), id: \.element.id) { n, b in
                    if n > 0 { Hairline() }
                    FranchiseBrandRow(brand: b)
                }
            }
        }
    }

    // MARK: Confirmation and result

    private func confirmation(_ e: GameEngine, _ t: Trade, _ plan: NewCompanyPlan, _ form: LegalForm, _ city: String, _ cityName: String, _ cur: Currency) -> PendingAction {
        let place: String = {
            switch plan.premisesKind {
            case .none: return "No premises."
            case .home: return "Starts at home."
            case .place:
                let o = plan.options.first { $0.index == (plan.pick?.listingIndex ?? plan.standardIndex) }
                return ((plan.pick?.buy ?? false) ? "Buying " : "Renting ") + (o?.name ?? "a place") + "."
            }
        }()
        let msg = "\(cur.tidyShort(plan.total)) to start. \(cur.tidyShort(plan.intoCompany)) goes into the company from your cash now" + (plan.estimate.shareCapital > 0 ? ", plus \(cur.tidyShort(plan.estimate.shareCapital)) share capital" : "") + ". You keep about \(cur.tidyShort(plan.personalLeft)). \(place) " +
            (plan.shortfall > 0 ? "You are \(cur.tidyShort(plan.shortfall)) short, so opening will wait for money. " : "") +
            (form == .limited ? "A limited company protects your personal assets." : "As a sole trader you are personally liable for its debts.") + " Risk: it earns nothing until it is set up and open."
        let pick = plan.pick
        let fund = plan.intoCompany
        let nm = name.trimmingCharacters(in: .whitespaces)
        let sz = size
        return PendingAction(title: "Start \(t.name) in \(cityName)?", message: msg.tidyMoney, button: "Start it") {
            let r = store.act { $0.startCompanyChoosingPremises(tradeID: t.id, cityID: city, form: form, size: sz, name: nm.isEmpty ? nil : nm, pick: pick, fundWith: fund) }
            switch r {
            case .success(let out)?:
                Haptics.success()
                var text = "Started. Set it up, then open for business."
                if out.premises == .notEnoughCash { text = "Started, but the company could not pay for the place you picked. Choose premises under Equipment." }
                else if !out.setupNotes.isEmpty { text = "Started. Some set-up is left (usually cash): see the checklist in the company." }
                store.show(text, tone: out.premises == .notEnoughCash || !out.setupNotes.isEmpty ? "warn" : "good")
                store.openCompany(out.companyID)
            case .failure(.banned(let why))?: Haptics.failure(); store.show(why, tone: "bad")
            case .failure(.notYetAvailable)?: store.show("Coming in a later update.", tone: "warn")
            case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You can't afford the registration costs yet.", tone: "warn")
            default: Haptics.warning(); store.show("Not possible here.", tone: "warn")
            }
        }
    }
}
