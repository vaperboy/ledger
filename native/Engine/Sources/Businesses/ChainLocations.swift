import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Locations of a chain: one quoted way to open another (what it costs, how it is named), and managers for the locations that come from the chain
/// level (a chain CEO or chain manager) instead of from the owner. A location is a store of `Chains` under the chain's brand; opening runs
/// `Chains.openStore`, hiring uses the existing manager machinery (`ManagerModel.fillManager`, promotions).
public enum ChainLocations {
    // MARK: Names

    static func cityName(_ co: Company, data: GameData) -> String { data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? "" }

    /// The brand a company's locations carry: the chain's name, else its own name without a trailing city.
    static func brand(_ s: GameState, _ co: Company, data: GameData) -> String {
        if let ch = Chains.chain(s, of: co) { return ch["name"].string }
        var n = co.name
        let city = cityName(co, data: data)
        if !city.isEmpty && n.hasSuffix(" " + city) { n.removeLast(city.count + 1) }
        return n
    }

    /// The name of a company bought or opened as a branch of `co`.
    static func branchName(_ s: GameState, of co: Company, newCompany c: Company, data: GameData) -> String {
        LocationNames.locationName(s, brand: brand(s, co, data: data), countryCode: c.countryCode, cityID: c.cityID, cityName: cityName(c, data: data), excluding: c.id, data: data)
    }

    // MARK: Quote

    /// What opening one more location in a city involves. Nothing is changed.
    public struct Quote: Equatable, Sendable {
        public var chainID: Int
        public var cityID: String
        public var cityName: String
        /// The name the location will carry.
        public var name: String
        /// Premises fit-out, equipment and vehicles to the chain's standard.
        public var fitOut: Double
        /// Rent a month of the standard place.
        public var monthlyRent: Double
        /// Rent deposit paid up front.
        public var deposit: Double
        /// Licences and registration papers the new location needs.
        public var licences: Double
        /// First stock, the first staff and a buffer, with the chain's 15% for the opening.
        public var other: Double
        /// All of it, paid now.
        public var total: Double
        public var canAfford: Bool
        /// A chain manager or CEO is in post: the location gets its manager without you.
        public var managerFromChain: Bool
    }

    public static func quote(_ s: GameState, chainID: Int, cityID: String, size: Double = 1, data: GameData) -> Quote? {
        guard let ch = Chains.chain(s, id: chainID), let first = Chains.stores(s, ch).first,
              let total = Chains.newStoreCost(s, chainID: chainID, cityID: cityID, size: size, data: data),
              let est = CompanySetup.estimate(tradeID: ch["type"].string, cityID: cityID, form: first.form, size: size, countryCode: first.countryCode, state: s, data: data),
              let found = data.countries.city(cityID, preferring: first.countryCode) else { return nil }
        let fitOut = est.premisesFitOut + est.equipment + est.vehicles
        let deposit = max(0, est.premises - est.premisesFitOut)
        let licences = est.documents + est.registration
        let name = LocationNames.locationName(s, brand: ch["name"].string, countryCode: first.countryCode, cityID: cityID, cityName: found.city.name, data: data)
        return Quote(chainID: chainID, cityID: cityID, cityName: found.city.name, name: name, fitOut: fitOut, monthlyRent: est.monthlyRent, deposit: deposit, licences: licences,
                     other: max(0, total - fitOut - deposit - licences), total: total, canAfford: Payments.liquid(s) >= total, managerFromChain: chainLead(s, chainID: chainID) != nil)
    }

    // MARK: Opening

    /// Open a location: premises, equipment and people to the chain's standard, named by place, on the chain's rules from day one, and with a
    /// manager from the chain level when there is one. `fundedBy` is a chain paying from its own stores' spare cash.
    public static func open(_ s: inout GameState, chainID: Int, cityID: String, size: Double = 1, data: GameData, context fc: FinanceContext, fundedBy parts: [Int: Double]? = nil) -> Result<Int, CompanySetup.StartError> {
        let r = Chains.openStore(&s, chainID: chainID, cityID: cityID, size: size, data: data, context: fc, fundedBy: parts)
        if case .success(let id) = r, let lead = chainLead(s, chainID: chainID) { _ = fillManager(&s, storeID: id, lead: lead, data: data) }
        return r
    }

    // MARK: Managers from the chain level

    /// The chain CEO, else the chain manager: whoever stands above the store managers and appoints them.
    public static func chainLead(_ s: GameState, chainID: Int) -> Person? {
        if let ch = Chains.chain(s, id: chainID), !ch["ceo56"].isNull, let n = s.people[ch["ceo56"]["npc"].int] { return n }
        if let rg = ManagerModel.regionals(s).first(where: { $0["scope"].string == "chain:\(chainID)" }) { return s.people[rg["npc"].int] }
        return nil
    }

    /// A worker at least this good is promoted to manager of their own location before anyone is hired from outside.
    static let promotionSkill = 55.0

    /// Give a location with no manager one: the best worker there when ready, else a hire through the chain lead's search.
    @discardableResult
    static func fillManager(_ s: inout GameState, storeID: Int, lead: Person, data: GameData) -> Bool {
        guard let co = s.company(storeID), HierarchyHiring.needsStoreManager(s, co, data: data) else { return false }
        if promoteWorker(&s, storeID: storeID, data: data) { return true }
        return ManagerModel.fillManager(&s, companyID: storeID, by: lead.name, why: "", boss: lead, data: data) != nil
    }

    static func promoteWorker(_ s: inout GameState, storeID: Int, data: GameData) -> Bool {
        guard let co = s.company(storeID) else { return false }
        let ranked = co.staff.compactMap { m -> (id: Int, skill: Double)? in
            s.people[m.id].map { (id: m.id, skill: ManagerModel.skillOf(s, m, $0, data: data)) }
        }.sorted { $0.skill != $1.skill ? $0.skill > $1.skill : $0.id < $1.id }
        guard let top = ranked.first, top.skill >= promotionSkill,
              let c = ManagerModel.candidate(s, companyID: storeID, personID: top.id, data: data),
              let post = ManagerModel.promotionPosts(s, companyID: storeID, personID: top.id, data: data).first(where: { $0.id == "mgr@\(storeID)" }), post.blocked.isEmpty else { return false }
        _ = ManagerModel.applyPromotion(&s, c, post: post, wage: post.ask, terms: ManagerModel.PromotionTerms(duties: ["hire"], authority: 1, report: "month"), data: data)
        return s.company(storeID)?.managerID != nil
    }

    /// Every location of the chain without a manager gets one from the chain level. Returns how many were filled.
    @discardableResult
    public static func fillManagers(_ s: inout GameState, chainID: Int, data: GameData) -> Int {
        guard let ch = Chains.chain(s, id: chainID), let lead = chainLead(s, chainID: chainID) else { return 0 }
        var n = 0
        for st in Chains.stores(s, ch) { if fillManager(&s, storeID: st.id, lead: lead, data: data) { n += 1 } }
        return n
    }
}
