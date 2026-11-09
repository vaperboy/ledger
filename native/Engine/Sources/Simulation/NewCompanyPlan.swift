import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The New company screen's whole picture before anything is confirmed: the start-up cost with the premises the player picked,
/// what leaves their own account, what is left, and the risks. Pure reads over `CompanySetup.estimate` and the premises listings;
/// the only rule added is arithmetic (replace the estimate's standard premises cost with the chosen place's cost).
/// What the owner chose on the plan beyond the mandatory costs. Nothing optional is bought unless it is chosen here.
public struct SetupChoices: Equatable, Sendable {
    public enum Stock: String, CaseIterable, Equatable, Sendable {
        case full, half, none
        public var share: Double { self == .full ? 1 : self == .half ? 0.5 : 0 }
        public var title: String { self == .full ? "Full opening stock" : self == .half ? "Half the opening stock" : "No opening stock" }
    }
    public var stock: Stock = .full
    /// Buy the equipment the trade can open without (and vehicles beyond the required ones).
    public var optionalEquipment = false
    /// The first line of the standard team only (the people the trade cannot open without), or the whole standard team.
    public var team: CompanySetup.SetupOptions.Team = .minimum
    /// Money to move into the company; nil: the recommended amount that keeps your personal reserve.
    public var putInto: Double? = nil
    /// The owner chooses what the company sells first (the item list starts empty). False keeps the trade's starter items on the list.
    public var chooseFirstItem = true
    public init(stock: Stock = .full, optionalEquipment: Bool = false, team: CompanySetup.SetupOptions.Team = .minimum, putInto: Double? = nil, chooseFirstItem: Bool = true) {
        self.stock = stock; self.optionalEquipment = optionalEquipment; self.team = team; self.putInto = putInto; self.chooseFirstItem = chooseFirstItem
    }
}

/// One line of the start-up statement, grouped by what kind of money it is.
public struct PlanLine: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable { case mandatory, optional, deposit, fee, workingCapital }
    public var id: String
    public var title: String
    public var amount: Double
    public var kind: Kind
    public var note: String
}

/// A cheaper way to start the same trade, offered when the plan is not affordable.
public struct PlanAlternative: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    /// What the company needs from you under this alternative, and how much less than the current plan.
    public var needed: Double
    public var saving: Double
}

public struct NewCompanyPlan: Equatable {
    public enum PremisesKind: Equatable, Sendable {
        /// Rent or buy a place (the engine lists several).
        case place
        /// The trade starts from home and moves into a workshop or office later.
        case home
        /// The trade needs no fixed place.
        case none
    }

    /// One place on offer, with what renting and buying it cost up front.
    public struct PremisesOption: Equatable, Sendable, Identifiable {
        public var id: Int { index }
        public var index: Int
        public var name: String
        public var landlord: String
        public var squareMetres: Double
        /// 1 = standard footfall / location quality
        public var location: Double
        public var monthlyRent: Double
        /// Renting: 3 months deposit (returned when you leave) plus the fit-out.
        public var rentUpfront: Double
        public var deposit: Double
        public var fitOut: Double
        public var purchasePrice: Double
        /// Buying: 35% down plus the fit-out; the rest is a 15-year commercial mortgage.
        public var buyUpfront: Double
        public var downPayment: Double
        public var canBuy: Bool
    }

    public struct Pick: Equatable, Sendable {
        public var listingIndex: Int
        public var buy: Bool
        public init(listingIndex: Int, buy: Bool) { self.listingIndex = listingIndex; self.buy = buy }
    }

    public var tradeID: String
    public var estimate: CompanySetup.Estimate
    public var premisesKind: PremisesKind
    public var options: [PremisesOption]
    /// The place that is used when nothing is picked: the one quick set-up rents.
    public var standardIndex: Int
    public var pick: Pick?
    /// The estimate with the picked place's cost in place of the standard premises cost.
    public var total: Double
    public var premisesCost: Double
    public var registrationAndCapital: Double
    /// Money put into the company on top of the share capital: the full cost with a 15% margin, as far as the account allows.
    public var intoCompany: Double
    public var available: Double
    public var personalLeft: Double
    public var shortfall: Double
    /// The account cannot pay registration and share capital: the company cannot even be registered yet.
    public var registrationShortfall: Double
    public var risks: [String]
    public var isFunded: Bool { shortfall <= 0 && registrationShortfall <= 0 }
    /// The choices this plan was priced with.
    public var choices = SetupChoices()
    /// The statement: mandatory costs, optional items that were chosen, deposits, fees and working capital.
    public var lines: [PlanLine] = []
    /// What the company needs for the scope chosen (mandatory + chosen optional + working capital), before the 15% margin.
    public var neededNow = 0.0
    /// The investment the game recommends (equipment, team, buffer on top of what is needed now); never charged by itself.
    public var recommendedInvestment = 0.0
    public var mandatoryTotal = 0.0, optionalTotal = 0.0, workingCapital = 0.0
    /// Optional items that were NOT chosen, with their price, so the player can add them knowingly.
    public var notChosen: [PlanLine] = []
    /// The part of your own money kept back: three monthly loan instalments and a small personal float.
    public var personalReserve = 0.0
    /// Your accounts after registration, capital and the money moved into the company.
    public var accountsAfter: Double { max(0, available - registrationAndCapital - intoCompany) }
    /// The company's cash once the mandatory costs and the chosen optional items are paid.
    public var companyCashAfterSetup: Double { intoCompany - mandatoryTotal + registrationAndCapitalInCompany - optionalTotal }
    /// Share capital stays in the company; registration and abroad fees do not.
    public var registrationAndCapitalInCompany = 0.0
    public var alternatives: [PlanAlternative] = []
    /// The reserve is intact only if your accounts after setup are at least the reserve.
    public var keepsReserve: Bool { accountsAfter + 0.5 >= personalReserve }
}

/// What happened when a company was started with a chosen place.
public struct NewCompanyOutcome: Equatable {
    public var companyID: Int
    /// nil: no place was picked (home, none, or the standard one)
    public var premises: CompanySetup.PremisesResult?
    /// What quick set-up could not do (usually cash).
    public var setupNotes: [String]
    /// What was left out on purpose (optional equipment, extra staff) with its cost, so it can be added later knowingly.
    public var skipped: [CompanySetup.SetupSkipped] = []
    /// The company's cash and your accounts right after the start.
    public var companyCash = 0.0
    public var accountsAfter = 0.0
}

public extension GameEngine {
    /// A copy of the state with a throw-away company, so a listing and its terms can be priced before the company exists. The account
    /// is topped up in the copy so registration never hides the numbers (affordability is reported separately).
    func previewCompany(tradeID: String, cityID: String, size: Double, countryCode: String? = nil) -> (state: GameState, companyID: Int)? {
        var tmp = state
        tmp.cash += Double(Int32.max)
        let cx = FinanceContext(countries: data.countries, trades: data.catalog)
        guard case .success(let id) = CompanySetup.create(&tmp, tradeID: tradeID, cityID: cityID, size: size, name: "tmp", countryCode: countryCode, data: data, context: cx) else { return nil }
        return (tmp, id)
    }

    /// The full plan for a trade in a city. `pick` nil means the standard rented place.
    func newCompanyPlan(tradeID: String, cityID: String, size: Double, pick: NewCompanyPlan.Pick? = nil, countryCode: String? = nil,
                        choices: SetupChoices = SetupChoices(), withAlternatives: Bool = true) -> NewCompanyPlan? {
        guard let bd = data.catalog[tradeID] else { return nil }
        var probe = state
        probe.cash += Double(Int32.max)
        guard let est = CompanySetup.estimate(tradeID: tradeID, cityID: cityID, size: size, countryCode: countryCode, state: probe, data: data) else { return nil }
        let kind: NewCompanyPlan.PremisesKind = {
            guard let k = bd.premisesKind, k != "none" else { return .none }
            return k == "home" ? .home : .place
        }()
        var options: [NewCompanyPlan.PremisesOption] = []
        if kind == .place, let (tmp, id) = previewCompany(tradeID: tradeID, cityID: cityID, size: size, countryCode: countryCode), let co = tmp.company(id) {
            let w = World(state: tmp, data: data)
            for l in CompanySetup.listings(for: co, bd, w) {
                guard let t = CompanySetup.premisesTerms(co, l, data: data, world: w) else { continue }
                options.append(.init(index: l.index, name: l.name, landlord: l.landlord, squareMetres: l.squareMetres, location: l.location,
                                     monthlyRent: t.monthlyRent, rentUpfront: t.deposit + t.fitOut, deposit: t.deposit, fitOut: t.fitOut,
                                     purchasePrice: t.purchasePrice, buyUpfront: t.downPayment + t.fitOut, downPayment: t.downPayment,
                                     canBuy: bd.premisesKind != "slope"))
            }
        }
        let standard = min(2, max(0, options.count - 1))
        var chosen = pick
        if let p = chosen, !options.contains(where: { $0.index == p.listingIndex }) { chosen = nil }
        if let p = chosen, p.buy, options.first(where: { $0.index == p.listingIndex })?.canBuy == false { chosen = nil }
        var premisesCost = est.premises
        if kind == .place, let o = options.first(where: { $0.index == (chosen?.listingIndex ?? standard) }) {
            premisesCost = (chosen?.buy ?? false) ? o.buyUpfront : o.rentUpfront
        }
        let total = est.total - est.premises + premisesCost
        let outlay = est.personalOutlay
        let available = Payments.liquid(state)
        let reserve = personalReserve()
        let regShort = max(0, est.registration + est.shareCapital + est.abroad - state.cash)
        // The scope the owner chose: what the trade cannot open without, plus only the optional items ticked.
        let optionalEquip = max(0, est.equipment - est.requiredEquipment) + max(0, est.vehicles - est.requiredVehicles)
        let stockChosen = jsRound(est.stock * choices.stock.share)
        let payroll = choices.team == .minimum ? est.minimumPayroll : est.firstPayroll
        let chosenOption = options.first(where: { $0.index == (chosen?.listingIndex ?? standard) })
        var lines: [PlanLine] = []
        var notChosen: [PlanLine] = []
        func add(_ id: String, _ title: String, _ amount: Double, _ kind: PlanLine.Kind, _ note: String = "") {
            if amount > 0 { lines.append(PlanLine(id: id, title: title, amount: amount, kind: kind, note: note)) }
        }
        add("docs", "Permits and documents", est.documents, .mandatory, "Needed before it can open.")
        add("reqEq", "Equipment the trade cannot open without", est.requiredEquipmentUpfront, .mandatory, "A fifth down where it can be financed.")
        add("reqVeh", "Required vehicles (down payment)", est.requiredVehicles, .mandatory, "The rest is a loan the company repays monthly.")
        if kind == .place, let o = chosenOption {
            let buying = chosen?.buy ?? false
            add("deposit", buying ? "Down payment on the place" : "Rent deposit (returned when you leave)", buying ? o.downPayment : o.deposit, .deposit, "")
            add("fitout", "Fit-out of the place", o.fitOut, .mandatory, "")
        } else { add("prem", "Premises", premisesCost, .mandatory, "") }
        add("property", "First property (deposit and costs)", est.property, .mandatory, "")
        add("wait", "Wages and rent while a long licence is awaited", est.wait, .mandatory, "")
        add("reg", "Registration", est.registration, .fee, "")
        add("abroad", "Representative and counsel abroad", est.abroad, .fee, "")
        add("optEq", "Optional equipment and vehicles", choices.optionalEquipment ? optionalEquip : 0, .optional, "Chosen by you.")
        add("stock", choices.stock.title, stockChosen, .optional, "Bought when the last paper is approved, only in the share you chose.")
        add("payroll", choices.team == .minimum ? "First month of the core team" : "First month of the whole standard team", payroll, .workingCapital, "Kept in the company to pay wages.")
        add("buffer", "Working buffer", est.buffer, .workingCapital, "Kept in the company for the first weeks.")
        if !choices.optionalEquipment && optionalEquip > 0 {
            notChosen.append(PlanLine(id: "optEq", title: "Optional equipment and vehicles", amount: optionalEquip, kind: .optional, note: "Not bought. Add it when the business can carry it."))
        }
        if choices.stock != .full, est.stock > 0 {
            notChosen.append(PlanLine(id: "stockRest", title: "The rest of the standard opening stock", amount: est.stock - stockChosen, kind: .optional, note: "Not bought now."))
        }
        if choices.team == .minimum, est.firstPayroll - est.minimumPayroll > 0 {
            notChosen.append(PlanLine(id: "team", title: "The rest of the standard team (a month)", amount: est.firstPayroll - est.minimumPayroll, kind: .optional, note: "Not hired now; each hire is a monthly cost."))
        }
        let mandatory = lines.filter { $0.kind == .mandatory || $0.kind == .deposit }.reduce(0) { $0 + $1.amount }
        let optionalSum = lines.filter { $0.kind == .optional }.reduce(0) { $0 + $1.amount }
        let working = lines.filter { $0.kind == .workingCapital }.reduce(0) { $0 + $1.amount }
        let fees = lines.filter { $0.kind == .fee }.reduce(0) { $0 + $1.amount }
        // What the company itself needs: everything except registration and abroad fees, which leave your own account.
        // the game buys and hires nothing at start, so only what the paperwork and the place need is charged; the full
        // figure (equipment, a team, a buffer) is the RECOMMENDED investment, shown but never taken unless the player puts it in.
        let recommendedIDs: Set<String> = ["optEq", "payroll", "buffer"]
        let needed = lines.filter { $0.kind != .fee && !recommendedIDs.contains($0.id) }.reduce(0) { $0 + $1.amount }
        let wanted = needed
        let into: Double
        if let put = choices.putInto { into = max(0, min(put, available - outlay)) } else { into = max(0, min(wanted, available - reserve - outlay)) }
        let shortfall = max(0, needed + outlay - available)
        let cur = homeCurrency
        var risks: [String] = []
        if available < total + outlay {
            risks.append("Below the recommended start-up investment (\(cur.short(total + outlay)), you have \(cur.short(available))). Only what the paperwork and place need is taken now; buy equipment and hire as the money comes in.")
        }
        if est.wait > 0 {
            risks.append("A long licence is needed. Wages and rent while you wait (\(cur.short(est.wait))) are already in the cost, and the company earns nothing until it is approved.")
        }
        risks.append("Share capital of \(cur.short(est.shareCapital)) is locked into the limited company. Profit is taxed in the company and again when you take it out.")
        if kind == .home { risks.append("It starts at home with no rent. From four people on the team, morale and quality slip every week until you move into a place of its own.") }
        if (chosen?.buy ?? false) { risks.append("Buying ties up the down payment and leaves a 15-year mortgage; selling later takes the market's price, not what you paid.") }
        risks.append("It earns nothing until it is set up and open; most new businesses need months to break even.")
        var plan = NewCompanyPlan(tradeID: tradeID, estimate: est, premisesKind: kind, options: options, standardIndex: standard, pick: chosen, total: total,
                                  premisesCost: premisesCost, registrationAndCapital: outlay, intoCompany: into, available: available,
                                  personalLeft: max(0, available - outlay - into), shortfall: shortfall,
                                  registrationShortfall: regShort, risks: risks)
        plan.choices = choices
        plan.lines = lines
        plan.notChosen = notChosen
        plan.neededNow = needed
        plan.recommendedInvestment = mandatory + optionalSum + working
        plan.mandatoryTotal = mandatory + fees
        plan.optionalTotal = optionalSum
        plan.workingCapital = working
        plan.personalReserve = reserve
        plan.registrationAndCapitalInCompany = est.shareCapital
        // The money does not carry the usual place: start from the cheapest one on offer (the player can still pick another).
        if pick == nil, kind == .place, plan.shortfall > 0, let cheap = options.min(by: { $0.rentUpfront < $1.rentUpfront }), cheap.index != standard,
           cheap.rentUpfront < (chosenOption?.rentUpfront ?? .infinity),
           var cheaper = newCompanyPlan(tradeID: tradeID, cityID: cityID, size: size, pick: .init(listingIndex: cheap.index, buy: false), countryCode: countryCode, choices: choices, withAlternatives: false),
           cheaper.shortfall < plan.shortfall {
            cheaper.pick = nil; cheaper.standardIndex = cheap.index
            plan = cheaper
        }
        if withAlternatives && (shortfall > 0 || !plan.keepsReserve) {
            plan.alternatives = setupAlternatives(plan, size: size, cityID: cityID, countryCode: countryCode, pick: pick)
        }
        return plan
    }

    /// The opening stock a first company can afford: the full standard stock when the money carries it, else half, else none (stock can be bought as sales start).
    func suggestedChoices(tradeID: String, cityID: String, size: Double, pick: NewCompanyPlan.Pick? = nil) -> SetupChoices {
        var c = SetupChoices()
        for stock in [SetupChoices.Stock.full, .half, .none] {
            c.stock = stock
            if let p = newCompanyPlan(tradeID: tradeID, cityID: cityID, size: size, pick: pick, choices: c, withAlternatives: false), p.isFunded { return c }
        }
        return c
    }

    /// Money kept back from the move into the company: three monthly instalments of the player's own loans and a small float.
    func personalReserve() -> Double {
        let instalments = state.loans.filter { $0.companyID == 0 }.reduce(0.0) { $0 + $1.monthlyPayment }
        return jsRound(instalments * 3 + homeCurrency.scaledPrice(2500))
    }

    /// Cheaper ways to start the same trade: a smaller size, renting instead of buying, the core team only, no optional extras.
    private func setupAlternatives(_ plan: NewCompanyPlan, size: Double, cityID: String, countryCode: String?, pick: NewCompanyPlan.Pick?) -> [PlanAlternative] {
        guard let bd = data.catalog[plan.tradeID] else { return [] }
        let cur = homeCurrency
        var out: [PlanAlternative] = []
        func offer(_ id: String, _ title: String, _ detail: String, _ p: NewCompanyPlan?) {
            guard let p, p.neededNow < plan.neededNow - 1 else { return }
            out.append(PlanAlternative(id: id, title: title, detail: detail + " Needs \(cur.short(p.neededNow)) instead of \(cur.short(plan.neededNow)).", needed: p.neededNow, saving: plan.neededNow - p.neededNow))
        }
        if plan.choices.optionalEquipment || plan.choices.stock != .none || plan.choices.team == .standard {
            var c = plan.choices
            c.optionalEquipment = false; c.team = .minimum; c.stock = plan.choices.stock == .full ? .half : .none; c.putInto = nil
            offer("lean", "Core team, only what it must have", "Only the required equipment, the core team and less opening stock.",
                  newCompanyPlan(tradeID: plan.tradeID, cityID: cityID, size: size, pick: pick, countryCode: countryCode, choices: c, withAlternatives: false))
        }
        if pick?.buy == true {
            let rented = NewCompanyPlan.Pick(listingIndex: pick?.listingIndex ?? plan.standardIndex, buy: false)
            offer("rent", "Rent the place instead of buying", "Only a deposit and the fit-out go out now.",
                  newCompanyPlan(tradeID: plan.tradeID, cityID: cityID, size: size, pick: rented, countryCode: countryCode, choices: plan.choices, withAlternatives: false))
        }
        let smaller = max(bd.minSize, ((size - 0.5) * 2).rounded() / 2)
        if smaller < size {
            offer("smaller", "Start smaller (size \(String(format: "%.1f", smaller)))", "Fewer people, less equipment and a smaller place.",
                  newCompanyPlan(tradeID: plan.tradeID, cityID: cityID, size: smaller, pick: nil, countryCode: countryCode, choices: plan.choices, withAlternatives: false))
        }
        return out
    }

    /// The whole standard team and the optional equipment are never bought for the player: they hire and buy by hand (or appoint a manager who does).
    func tutorialLimited(_ c: SetupChoices) -> SetupChoices {
        var out = c
        out.team = .minimum
        out.optionalEquipment = false
        return out
    }

    /// Start a company, take the picked place (rent or buy) and then do the set-up the owner chose. The set-up is budgeted: required
    /// equipment, the core team (or the whole team if chosen) only while the company's cash carries the wages, and an opening stock of the
    /// chosen share. What was left out comes back in `skipped` with its cost. `choices` default to the careful start.
    mutating func startCompanyChoosingPremises(tradeID: String, cityID: String, size: Double?, name: String?, pick: NewCompanyPlan.Pick?, fundWith amount: Double,
                                               choices requested: SetupChoices = SetupChoices(), accountantID: Int? = nil) -> Result<NewCompanyOutcome, CompanySetup.StartError> {
        let choices: SetupChoices = tutorialLimited(requested)
        let r = startCompany(tradeID: tradeID, cityID: cityID, size: size, name: name, accountantID: accountantID, fundWith: amount, quickSetup: false)
        guard case .success(let id) = r else {
            if case .failure(let e) = r { return .failure(e) }
            return .failure(.notAllowedHere)
        }
        var out = NewCompanyOutcome(companyID: id, premises: nil, setupNotes: [])
        update { s, d, _ in
            if let pick, let i = s.companyIndex(id), let bd = d.catalog[s.companies[i].type], let k = bd.premisesKind, k != "none", k != "home",
               let l = CompanySetup.listings(for: s.companies[i], bd, World(state: s, data: d)).first(where: { $0.index == pick.listingIndex }) {
                out.premises = CompanySetup.setPremises(&s, companyID: id, listing: l, buy: pick.buy, data: d)
            }
            if let i = s.companyIndex(id) {
                var f = s.companies[i].value("flags")
                f["stockShare"] = .number(choices.stock.share)
                s.companies[i].set("flags", f)
                if choices.chooseFirstItem { SalesItems.markFirstChoicePending(&s, i) }
            }
            var options = CompanySetup.SetupOptions(team: choices.team, optionalEquipment: choices.optionalEquipment, payrollMonthsReserve: 2, equipmentInPlace: true, teamInPlace: true)
            // Nothing is filled in for the player: documents are signed on the Setup screen, the place and the equipment are chosen in AirStay and TechPro.
            options.applyDocuments = false; options.autoPremises = false; options.buyProperty = false
            let rep = CompanySetup.quickSetupReport(&s, companyID: id, data: d, options: options)
            out.setupNotes = rep.log
            out.skipped = rep.skipped
            out.companyCash = s.company(id)?.cash ?? 0
            out.accountsAfter = s.cash
        }
        return .success(out)
    }
}
