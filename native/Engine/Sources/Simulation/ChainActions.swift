import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {

    func chainRequirements(companyID: Int) -> [Chains.Requirement] { state.company(companyID).map { Chains.requirements(state, $0) } ?? [] }
    func chainOf(companyID: Int) -> JSONValue? { state.company(companyID).flatMap { Chains.chain(state, of: $0) } }
    var chainSummaries: [Chains.Summary] { Chains.summaries(state, data: data) }
    func chainSummary(id: Int) -> Chains.Summary? { chainSummaries.first { $0.id == id } }
    func chainSummary(containing companyID: Int) -> Chains.Summary? { chainSummaries.first { $0.stores.contains { $0.id == companyID } } }
    var looseStoreGroups: [Chains.LooseGroup] { Chains.looseGroups(state, data: data) }
    func chainRules(chainID: Int) -> JSONValue { Chains.chain(state, id: chainID)?["rules"] ?? .null }
    func reach(companyID: Int) -> Chains.Reach? { state.company(companyID).map { Chains.reach(state, $0, data: data) } }
    func companiesThatCanJoin(chainID: Int) -> [Company] {
        guard let ch = Chains.chain(state, id: chainID) else { return [] }
        return state.companies.filter { $0.status.isLive && $0.type == ch["type"].string && $0.value("chain").isNull }
    }

    func documentState(companyID: Int, document: String) -> (status: String, weeksLeft: Int) {
        guard let co = state.company(companyID) else { return ("", 0) }
        let d = co.value("docs")[document]
        return (d["st"].string, max(0, d["done"].int - state.week))
    }
    func documentFee(companyID: Int, document: String) -> Double {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return 0 }
        return Documents.cost(document, company: co, bd, World(state: state, data: data))
    }

    @discardableResult
    mutating func applyForChainDocument(companyID: Int, document: String) -> Chains.ChainDocResult {
        var r = Chains.ChainDocResult.notFound
        update { s, d, _ in r = Chains.applyDocument(&s, companyID: companyID, doc: document, data: d) }
        return r
    }

    @discardableResult
    mutating func makeChain(companyID: Int, name: String) -> Int? {
        var id: Int?
        update { s, d, _ in id = Chains.make(&s, companyID: companyID, name: name, data: d) }
        return id
    }

    mutating func joinChain(chainID: Int, companyID: Int, rename: Bool) {
        update { s, d, _ in Chains.join(&s, chainID: chainID, companyID: companyID, rename: rename, data: d) }
    }

    func chainTrade(chainID: Int) -> Trade? { Chains.chain(state, id: chainID).flatMap { data.catalog[$0["type"].string] } }

    func chainKnobPlan(chainID: Int, knob: String, value: Int) -> Chains.KnobStandardPlan? { Chains.knobStandardPlan(state, chainID: chainID, knob: knob, value: value, data: data) }

    @discardableResult
    mutating func setChainKnob(chainID: Int, knob: String, value: Int) -> Chains.KnobStandardPlan {
        var out = Chains.KnobStandardPlan(lines: [])
        update { s, d, _ in out = Chains.setKnobStandard(&s, chainID: chainID, knob: knob, value: value, data: d) }
        return out
    }

    func chainKnobStandard(chainID: Int, knob: String) -> Int? { Chains.knobStandard(state, chainID: chainID, knob: knob) }

    func chainKnobExceptions(chainID: Int, knob: String) -> [(storeID: Int, storeName: String, value: Int)] { Chains.knobExceptions(state, chainID: chainID, knob: knob, data: data) }

    @discardableResult
    mutating func releaseChainKnob(chainID: Int, knob: String) -> SettingResult {
        applySetting(refuse: { Chains.chain($0, id: chainID) == nil ? "That chain no longer exists." : nil }, probe: { Chains.chain($0, id: chainID) ?? .null }) { s, _, _ in Chains.releaseKnobStandard(&s, chainID: chainID, knob: knob) }
    }

    @discardableResult
    mutating func setChainRule(chainID: Int, rule: Chains.Rule) -> SettingResult {
        applySetting(refuse: { Chains.chain($0, id: chainID) == nil ? "That chain no longer exists." : nil }, probe: { Chains.chain($0, id: chainID) ?? .null }) { s, d, _ in
            if case .knob(let id, let o) = rule { Chains.setKnobStandard(&s, chainID: chainID, knob: id, value: o, data: d) }
            else { Chains.setRule(&s, chainID: chainID, rule: rule) }
        }
    }
    @discardableResult
    mutating func setStoreRule(companyID: Int, rule: Chains.StoreRule) -> SettingResult {
        applySetting(refuse: { s in
            guard let co = s.company(companyID) else { return "That store no longer exists." }
            return Chains.chain(s, of: co) == nil ? "That store is not part of a chain." : nil
        }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in Chains.setStoreRule(&s, companyID: companyID, rule: rule) }
    }

    func franchiseRequirements(companyID: Int) -> [Franchising.Requirement] { state.company(companyID).map { Franchising.requirements(state, $0) } ?? [] }
    func isFranchisor(companyID: Int) -> Bool { state.company(companyID)?.value("fr")["on"].bool ?? false }
    func canFranchise(companyID: Int) -> Bool { state.company(companyID).map { FranchiseBrands.isFranchisable($0.type) } ?? false }
    func franchiseApplicants(companyID: Int) -> [Franchising.Applicant] { state.company(companyID).map { Franchising.applicants($0) } ?? [] }
    func franchiseSystem(companyID: Int) -> JSONValue { state.company(companyID)?.value("fr") ?? .null }
    func standardTalkTerms(companyID: Int) -> Franchising.TalkTerms { Franchising.TalkTerms(standardFor: franchiseSystem(companyID: companyID)) }
    func talkSums(companyID: Int, applicantID: Int, terms: Franchising.TalkTerms) -> Franchising.TalkSums? {
        guard let co = state.company(companyID), let a = Franchising.applicants(co).first(where: { $0.id == applicantID }) else { return nil }
        return Franchising.talkSums(state, company: co, applicant: a, terms: terms, data: data)
    }

    @discardableResult
    mutating func launchFranchise(companyID: Int, entryFee: Double, royalty: Double, support: Int) -> Franchising.LaunchResult {
        var r = Franchising.LaunchResult.already
        update { s, _, _ in r = Franchising.launch(&s, companyID: companyID, fee: entryFee, royalty: royalty, support: support) }
        return r
    }

    mutating func offerToApplicant(companyID: Int, applicantID: Int, terms: Franchising.TalkTerms) -> Franchising.OfferResult? {
        var r: Franchising.OfferResult?
        update { s, d, c in r = Franchising.makeOffer(&s, companyID: companyID, applicantID: applicantID, terms: terms, data: d, context: c) }
        return r
    }

    @discardableResult
    mutating func terminateFranchiseUnit(companyID: Int, unitID: Int) -> Bool {
        var ok = false
        update { s, _, c in ok = Franchising.terminate(&s, companyID: companyID, unitID: unitID, context: c) }
        return ok
    }

    func masterFranchiseCountries(companyID: Int) -> [Country] {
        guard let co = state.company(companyID), co.value("fr")["on"].bool else { return [] }
        return data.countries.countries.filter { $0.code != co.countryCode && CompanySetup.banReason(co.type, country: $0) == nil }
    }

    @discardableResult
    mutating func sellMasterFranchise(companyID: Int, country: String) -> Franchising.MasterResult {
        var r = Franchising.MasterResult.bad
        update { s, d, _ in r = Franchising.sellMaster(&s, companyID: companyID, country: country, data: d) }
        return r
    }

    var franchiseCountry: String { state.homeCountryCode }

    func franchiseBrands(country: String? = nil) -> [FranchiseBrands.Brand] {
        FranchiseBrands.available(country: country ?? state.homeCountryCode, World(state: state, data: data))
    }
    func franchiseBrand(_ id: String) -> FranchiseBrands.Brand? { FranchiseBrands.brand(id, World(state: state, data: data)) }
    func franchiseApplication(_ brandID: String) -> JSONValue { FranchiseBrands.application(state, brandID) }
    func franchiseAgreedTerms(_ brandID: String) -> FranchiseBrands.Terms? { FranchiseBrands.agreedTerms(state, brandID) }
    func franchiseEntryFee(_ b: FranchiseBrands.Brand, country: String? = nil) -> Double {
        FranchiseBrands.fee(b, country: data.countries.resolve(country ?? state.homeCountryCode, orHome: state.homeCountryCode))
    }
    func franchiseUnitStats(_ b: FranchiseBrands.Brand) -> (revenue: Double, margin: Double) { FranchiseBrands.unitStats(b, World(state: state, data: data)) }
    func franchiseStatus(_ b: FranchiseBrands.Brand) -> FranchiseBrands.Status { FranchiseBrands.status(b, state, World(state: state, data: data)) }

    @discardableResult
    mutating func applyToFranchiseBrand(_ brandID: String, country: String? = nil, cityID: String? = nil) -> FranchiseBrands.ApplyResult {
        guard let b = franchiseBrand(brandID) else { return .closed("Unknown brand.") }
        var r = FranchiseBrands.ApplyResult.already
        update { s, d, _ in r = FranchiseBrands.apply(&s, brand: b, country: country ?? s.homeCountryCode, city: cityID ?? s.player.cityID, data: d) }
        return r
    }

    mutating func negotiateFranchise(_ brandID: String, ask: FranchiseBrands.Ask) -> FranchiseBrands.Negotiation? {
        guard let b = franchiseBrand(brandID) else { return nil }
        var r: FranchiseBrands.Negotiation?
        update { s, d, _ in
            let cc = FranchiseBrands.application(s, brandID)["country"].string
            r = FranchiseBrands.negotiate(&s, brand: b, ask: ask, data: d, country: cc.isEmpty ? nil : cc)
        }
        return r
    }

    mutating func signFranchiseTerms(_ brandID: String, terms: FranchiseBrands.Terms) {
        guard let b = franchiseBrand(brandID) else { return }
        update { s, _, _ in FranchiseBrands.sign(&s, brand: b, terms: terms) }
    }

    func franchiseStartEstimate(brandID: String, cityID: String) -> (estimate: CompanySetup.Estimate, fee: Double, size: Double)? {
        guard let b = franchiseBrand(brandID), let t = franchiseAgreedTerms(brandID), let bd = data.catalog[b.tradeID] else { return nil }
        let country = franchiseApplication(brandID)["country"].string
        let cc = country.isEmpty ? state.homeCountryCode : country
        guard let c = data.countries[cc], let city = c.city(cityID) ?? c.cities.first else { return nil }
        let size = CompanySetup.recommendedSize(bd, city: city, brandStrength: b.strength / 100)
        guard let est = CompanySetup.estimate(tradeID: b.tradeID, cityID: city.id, size: size, countryCode: cc, state: state, data: data) else { return nil }
        return (est, t.fee, size)
    }

    func franchiseStartPlan(brandID: String, cityID: String, pick: NewCompanyPlan.Pick? = nil) -> (plan: NewCompanyPlan, fee: Double)? {
        guard let b = franchiseBrand(brandID), let t = franchiseAgreedTerms(brandID), let est = franchiseStartEstimate(brandID: brandID, cityID: cityID) else { return nil }
        let country = franchiseApplication(brandID)["country"].string
        guard let plan = newCompanyPlan(tradeID: b.tradeID, cityID: cityID, size: est.size, pick: pick, countryCode: country.isEmpty ? nil : country) else { return nil }
        return (plan, t.fee)
    }

    mutating func startFranchisedCompanyChoosingPremises(brandID: String, cityID: String, name: String?, accountantID: Int? = nil, pick: NewCompanyPlan.Pick?) -> Result<NewCompanyOutcome, CompanySetup.StartError> {
        guard let b = franchiseBrand(brandID), let t = franchiseAgreedTerms(brandID) else { return .failure(.notAllowedHere) }
        let country = franchiseApplication(brandID)["country"].string
        let cc = country.isEmpty ? state.homeCountryCode : country
        let size = data.countries[cc].flatMap { c in c.city(cityID).flatMap { city in data.catalog[b.tradeID].map { CompanySetup.recommendedSize($0, city: city, brandStrength: b.strength / 100) } } }
        let nm = (name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
        let r = startCompany(tradeID: b.tradeID, cityID: cityID, size: size, name: nm, countryCode: cc, accountantID: accountantID, quickSetup: false)
        guard case .success(let id) = r else {
            if case .failure(let e) = r { return .failure(e) }
            return .failure(.notAllowedHere)
        }
        var out = NewCompanyOutcome(companyID: id, premises: nil, setupNotes: [])
        update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            if s.companies[i].cash >= t.fee {
                Payments.companyPays(&s, companyID: id, amount: t.fee, category: "oth", label: "Franchise entry fee: \(b.name)")
                FranchiseBrands.applyToCompany(&s, companyIndex: i, brand: b, terms: t, data: d)
                var m = s.rest["fbApps"]?.object ?? [:]; m[brandID] = nil; s.rest["fbApps"] = .object(m)
            } else {
                s.note("Not enough funding for the franchise fee, so \(s.companies[i].name) starts independent.", tone: "bad", companyID: id)
            }
            if let pick, let bd = d.catalog[s.companies[i].type], let k = bd.premisesKind, k != "none", k != "home",
               let l = CompanySetup.listings(for: s.companies[i], bd, World(state: s, data: d)).first(where: { $0.index == pick.listingIndex }) {
                out.premises = CompanySetup.setPremises(&s, companyID: id, listing: l, buy: pick.buy, data: d)
            }
            out.setupNotes = CompanySetup.quickSetup(&s, companyID: id, data: d)
        }
        return .success(out)
    }

    func franchiseeInfo(companyID: Int) -> JSONValue { state.company(companyID)?.value("franchise") ?? .null }
    func franchiseMinimumQuality(companyID: Int) -> Double { Franchising.brandMinimumQuality(franchiseeInfo(companyID: companyID)) }
    func franchiseBuyout(companyID: Int) -> Double { state.company(companyID).map { Franchising.buyout($0, week: state.week) } ?? 0 }

    @discardableResult
    mutating func leaveFranchise(companyID: Int) -> Bool {
        var ok = false
        update { s, _, c in ok = Franchising.leaveFranchise(&s, companyID: companyID, context: c) }
        return ok
    }

    func supplyKinds(companyID: Int) -> [IntercompanySupply.Kind] { state.company(companyID).map { IntercompanySupply.kindsFor($0) } ?? [] }
    func supplyLinks() -> [IntercompanySupply.Link] { IntercompanySupply.links(state) }
    func supplyLink(buyer: Int, kind: String) -> IntercompanySupply.Link? { IntercompanySupply.link(state, buyer: buyer, kind: kind) }
    func possibleSuppliers(buyer: Int, kind: String) -> [Company] {
        guard let co = state.company(buyer), let k = IntercompanySupply.kind(kind) else { return [] }
        return IntercompanySupply.suppliers(state, for: co, kind: k)
    }
    func yearlySupplySpend(buyer: Int, kind: String) -> Double {
        guard let co = state.company(buyer), let k = IntercompanySupply.kind(kind) else { return 0 }
        return IntercompanySupply.yearlySpend(co, k)
    }
    func supplyPriceFactor(supplier: Int, mode: String) -> Double {
        state.company(supplier).map { IntercompanySupply.priceFactor(mode: mode, supplier: $0, data: data, perkCut: Ambitions.supplyCostCut(state, data)) } ?? 1
    }
}
