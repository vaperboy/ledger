import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The New company screen's whole picture before anything is confirmed: the start-up cost with the premises the player picked,
/// what leaves their own account, what is left, and the risks. Pure reads over `CompanySetup.estimate` and the premises listings;
/// the only rule added is arithmetic (replace the estimate's standard premises cost with the chosen place's cost).
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
}

/// What happened when a company was started with a chosen place.
public struct NewCompanyOutcome: Equatable {
    public var companyID: Int
    /// nil: no place was picked (home, none, or the standard one)
    public var premises: CompanySetup.PremisesResult?
    /// What quick set-up could not do (usually cash).
    public var setupNotes: [String]
}

public extension GameEngine {
    /// A copy of the state with a throw-away company, so a listing and its terms can be priced before the company exists. The account
    /// is topped up in the copy so registration never hides the numbers (affordability is reported separately).
    private func previewCompany(tradeID: String, cityID: String, form: LegalForm, size: Double) -> (state: GameState, companyID: Int)? {
        var tmp = state
        tmp.cash += Double(Int32.max)
        let cx = FinanceContext(countries: data.countries, trades: data.catalog)
        guard case .success(let id) = CompanySetup.create(&tmp, tradeID: tradeID, cityID: cityID, form: form, size: size, name: "tmp", data: data, context: cx) else { return nil }
        return (tmp, id)
    }

    /// The full plan for a trade in a city. `pick` nil means the standard rented place.
    func newCompanyPlan(tradeID: String, cityID: String, form: LegalForm, size: Double, pick: NewCompanyPlan.Pick? = nil) -> NewCompanyPlan? {
        guard let bd = data.catalog[tradeID] else { return nil }
        var probe = state
        probe.cash += Double(Int32.max)
        guard let est = CompanySetup.estimate(tradeID: tradeID, cityID: cityID, form: form, size: size, state: probe, data: data) else { return nil }
        let kind: NewCompanyPlan.PremisesKind = {
            guard let k = bd.premisesKind, k != "none" else { return .none }
            return k == "home" ? .home : .place
        }()
        var options: [NewCompanyPlan.PremisesOption] = []
        if kind == .place, let (tmp, id) = previewCompany(tradeID: tradeID, cityID: cityID, form: form, size: size), let co = tmp.company(id) {
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
        let into = max(0, min(total * 1.15, available - outlay))
        let regShort = max(0, est.registration + est.shareCapital + est.abroad - state.cash)
        let cur = homeCurrency
        var risks: [String] = []
        if available < total + outlay {
            risks.append("About \(cur.short(total + outlay - available)) short of the full cost: registration comes first, then the company can open only as far as its cash goes. Equipment, stock or hiring wait for money.")
        }
        if est.wait > 0 {
            risks.append("A long licence is needed. Wages and rent while you wait (\(cur.short(est.wait))) are already in the cost, and the company earns nothing until it is approved.")
        }
        if form == .soleTrader {
            risks.append("As a sole trader you are personally liable for the company's debts" + ((chosen?.buy ?? false) ? ", including the mortgage on a bought place." : "."))
        } else {
            risks.append("Share capital of \(cur.short(est.shareCapital)) is locked into the limited company. Profit is taxed in the company and again when you take it out.")
        }
        if kind == .home { risks.append("It starts at home with no rent. From four people on the team, morale and quality slip every week until you move into a place of its own.") }
        if (chosen?.buy ?? false) { risks.append("Buying ties up the down payment and leaves a 15-year mortgage; selling later takes the market's price, not what you paid.") }
        risks.append("It earns nothing until it is set up and open; most new businesses need months to break even.")
        return NewCompanyPlan(tradeID: tradeID, estimate: est, premisesKind: kind, options: options, standardIndex: standard, pick: chosen, total: total,
                              premisesCost: premisesCost, registrationAndCapital: outlay, intoCompany: into, available: available,
                              personalLeft: max(0, available - outlay - into), shortfall: max(0, total + outlay - available),
                              registrationShortfall: regShort, risks: risks)
    }

    /// Start a company, take the picked place (rent or buy) and then do the standard set-up for everything else.
    /// With no pick it behaves exactly like `startCompany`.
    mutating func startCompanyChoosingPremises(tradeID: String, cityID: String, form: LegalForm, size: Double?, name: String?, pick: NewCompanyPlan.Pick?, fundWith amount: Double) -> Result<NewCompanyOutcome, CompanySetup.StartError> {
        let r = startCompany(tradeID: tradeID, cityID: cityID, form: form, size: size, name: name, fundWith: amount, quickSetup: false)
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
            out.setupNotes = CompanySetup.quickSetup(&s, companyID: id, data: d)
        }
        return .success(out)
    }
}
