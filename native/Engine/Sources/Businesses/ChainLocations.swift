import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum ChainLocations {

    static func cityName(_ co: Company, data: GameData) -> String { data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? "" }

    static func brand(_ s: GameState, _ co: Company, data: GameData) -> String {
        if let ch = Chains.chain(s, of: co) { return ch["name"].string }
        var n = co.name
        let city = cityName(co, data: data)
        if !city.isEmpty && n.hasSuffix(" " + city) { n.removeLast(city.count + 1) }
        return n
    }

    static func branchName(_ s: GameState, of co: Company, newCompany c: Company, data: GameData) -> String {
        LocationNames.locationName(s, brand: brand(s, co, data: data), countryCode: c.countryCode, cityID: c.cityID, cityName: cityName(c, data: data), excluding: c.id, data: data)
    }

    public struct Quote: Equatable, Sendable {
        public var chainID: Int
        public var cityID: String
        public var cityName: String
        public var name: String
        public var fitOut: Double
        public var monthlyRent: Double
        public var deposit: Double
        public var licences: Double
        public var other: Double
        public var total: Double
        public var canAfford: Bool
        public var managerFromChain: Bool
    }

    public static func quote(_ s: GameState, chainID: Int, cityID: String, size: Double = 1, data: GameData) -> Quote? {
        guard let ch = Chains.chain(s, id: chainID), let first = Chains.stores(s, ch).first,
              let total = Chains.newStoreCost(s, chainID: chainID, cityID: cityID, size: size, data: data),
              let est = CompanySetup.estimate(tradeID: ch["type"].string, cityID: cityID, size: size, countryCode: first.countryCode, state: s, data: data),
              let found = data.countries.city(cityID, preferring: first.countryCode) else { return nil }
        let fitOut = est.premisesFitOut + est.equipment + est.vehicles
        let deposit = max(0, est.premises - est.premisesFitOut)
        let licences = est.documents + est.registration
        let name = LocationNames.locationName(s, brand: ch["name"].string, countryCode: first.countryCode, cityID: cityID, cityName: found.city.name, data: data)
        return Quote(chainID: chainID, cityID: cityID, cityName: found.city.name, name: name, fitOut: fitOut, monthlyRent: est.monthlyRent, deposit: deposit, licences: licences,
                     other: max(0, total - fitOut - deposit - licences), total: total, canAfford: Payments.liquid(s) >= total, managerFromChain: chainLead(s, chainID: chainID) != nil)
    }

    public static func open(_ s: inout GameState, chainID: Int, cityID: String, size: Double = 1, data: GameData, context fc: FinanceContext, fundedBy parts: [Int: Double]? = nil) -> Result<Int, CompanySetup.StartError> {
        let r = Chains.openStore(&s, chainID: chainID, cityID: cityID, size: size, data: data, context: fc, fundedBy: parts)
        if case .success(let id) = r, let lead = chainLead(s, chainID: chainID) { _ = fillManager(&s, storeID: id, lead: lead, data: data) }
        return r
    }

    public static func openByVote(_ s: inout GameState, chainID: Int, cityID: String, size: Double = 1, data: GameData, context fc: FinanceContext) -> Result<Int, CompanySetup.StartError> {
        guard let ch = Chains.chain(s, id: chainID), let first = Chains.stores(s, ch).first else { return .failure(.notAllowedHere) }
        if ManagerModel.boardGate(s, kind: "open", companyID: first.id) != nil { return .failure(.notAllowedHere) }
        return open(&s, chainID: chainID, cityID: cityID, size: size, data: data, context: fc)
    }

    public struct LocationProposal: Identifiable, Equatable, Sendable {
        public var id: Int
        public var chainID: Int
        public var kind: String
        public var cityID: String
        public var cityName: String
        public var size: Double
        public var storeID: Int
        public var storeName: String
        public var by: String
        public var why: String
        public var week: Int
        public var cost: Double
        public var target: String { kind == "open" ? cityID : String(storeID) }
    }

    static func memoKey(kind: String, target: String) -> String { "loc:\(kind):\(target)" }

    public static func proposals(_ s: GameState, chainID: Int) -> [LocationProposal] {
        ManagerModel.board(s, key: "ch:\(chainID)")["locp"].array.map { p in
            LocationProposal(id: p["id"].int, chainID: chainID, kind: p["k"].string, cityID: p["city"].string, cityName: p["cn"].string, size: p["size"].isNull ? 1 : p["size"].double,
                             storeID: p["co"].int, storeName: p["sn"].string, by: p["by"].string, why: p["why"].string, week: p["w"].int, cost: p["cost"].double)
        }
    }

    public static func leadLabel(_ s: GameState, chainID: Int) -> String? {
        guard let ch = Chains.chain(s, id: chainID), let n = chainLead(s, chainID: chainID) else { return nil }
        return "\(n.name), \(ch["ceo56"].isNull ? "Chain manager" : "CEO")"
    }

    @discardableResult
    public static func proposeOpen(_ s: inout GameState, chainID: Int, cityID: String, size: Double = 1, by: String, why: String, data: GameData) -> Int? {
        guard let ch = Chains.chain(s, id: chainID), let first = Chains.stores(s, ch).first, let q = quote(s, chainID: chainID, cityID: cityID, size: size, data: data) else { return nil }
        return addProposal(&s, chainID: chainID, by: by, why: why, ["k": "open", "city": .string(cityID), "cn": .string(q.cityName), "size": .number(size),
                                                                      "co": .number(Double(first.id)), "sn": .string(first.name), "cost": .number(q.total)])
    }

    @discardableResult
    public static func proposeClosure(_ s: inout GameState, storeID: Int, by: String, why: String, data: GameData) -> Int? {
        guard let co = s.company(storeID), let ch = Chains.chain(s, of: co), ChainBranches.refusal(s, co) == nil,
              let plan = ChainBranches.closurePlan(s, storeID: storeID, data: data) else { return nil }
        return addProposal(&s, chainID: ch["id"].int, by: by, why: why, ["k": "shut", "co": .number(Double(storeID)), "sn": .string(co.name), "city": .string(co.cityID),
                                                                         "cn": .string(cityName(co, data: data)), "cost": .number(max(0, -plan.net))])
    }

    private static func addProposal(_ s: inout GameState, chainID: Int, by: String, why: String, _ fields: [String: JSONValue]) -> Int? {
        let key = "ch:\(chainID)"
        var b = ManagerModel.board(s, key: key)
        var list = b["locp"].array
        let kind = fields["k"]?.string ?? ""
        let target = kind == "open" ? (fields["city"]?.string ?? "") : String(fields["co"]?.int ?? 0)
        if list.contains(where: { $0["k"].string == kind && ($0["k"].string == "open" ? $0["city"].string : String($0["co"].int)) == target }) { return nil }
        let quiet = b["memo"][memoKey(kind: kind, target: target)]
        if !quiet.isNull && quiet.int > s.week { return nil }
        let id = s.makeID()
        var rec = fields
        rec["id"] = .number(Double(id)); rec["w"] = .number(Double(s.week)); rec["why"] = .string(why); rec["by"] = .string(by)
        list.append(.object(rec))
        b["locp"] = .array(list)
        ManagerModel.writeBoard(&s, key: key, b)
        return id
    }

    static func carryOut(_ s: inout GameState, _ d: ManagerModel.BoardDecision, data: GameData, context fc: FinanceContext) -> ManagerModel.BoardDecisionResult {
        guard let p = proposals(s, chainID: ManagerModel.keyID(d.key)).first(where: { $0.id == d.proposalID }) else { return .gone }
        if p.kind == "open" {
            switch open(&s, chainID: p.chainID, cityID: p.cityID, size: p.size, data: data, context: fc) {
            case .success(let id): return .done("\(s.company(id)?.name ?? "A new location") is being set up in \(p.cityName).")
            case .failure(.notEnoughCash): return .refused("There is not enough cash to open it now.")
            case .failure(.banned(let why)): return .refused(why)
            case .failure(.notAllowedHere): return .refused("This trade cannot open there.")
            case .failure(.notYetAvailable): return .refused("It is not available yet.")
            }
        }
        switch ChainBranches.close(&s, storeID: p.storeID, data: data) {
        case .success(let plan): return .done("\(plan.storeName) is closed. Its people and stock went to \(plan.receiverName).")
        case .failure(let why): return .refused(why.text)
        }
    }

    static func leadProposals(_ s: inout GameState, chainID: Int, data: GameData) {
        guard GameCalendar.isMonthEnd(week: s.week), let ch = Chains.chain(s, id: chainID), let label = leadLabel(s, chainID: chainID) else { return }
        for st in Chains.stores(s, ch) where st.status == .open {
            let h = Array(st.monthlyHistory.suffix(6))
            guard h.count == 6, h.allSatisfy({ $0.profit < 0 }) else { continue }
            let loss = -h.reduce(0.0) { $0 + $1.profit }
            proposeClosure(&s, storeID: st.id, by: label, why: "\(st.name) has lost money six months in a row, \(World(state: s, data: data).currency(st).short(loss)) in all.", data: data)
        }
    }

    public static func chainLead(_ s: GameState, chainID: Int) -> Person? {
        if let ch = Chains.chain(s, id: chainID), !ch["ceo56"].isNull, let n = s.people[ch["ceo56"]["npc"].int] { return n }
        if let rg = ManagerModel.regionals(s).first(where: { $0["scope"].string == "chain:\(chainID)" }) { return s.people[rg["npc"].int] }
        return nil
    }

    static let promotionSkill = 55.0

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
        _ = ManagerModel.applyPromotion(&s, c, post: post, wage: post.ask, terms: ManagerModel.PromotionTerms(authority: 1), data: data)
        return s.company(storeID)?.managerID != nil
    }

    @discardableResult
    public static func fillManagers(_ s: inout GameState, chainID: Int, data: GameData) -> Int {
        guard let ch = Chains.chain(s, id: chainID), let lead = chainLead(s, chainID: chainID) else { return 0 }
        var n = 0
        for st in Chains.stores(s, ch) { if fillManager(&s, storeID: st.id, lead: lead, data: data) { n += 1 } }
        return n
    }
}
