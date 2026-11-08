import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Delegated appointments inside a chain or regional hierarchy: the higher rank hires one level down, the owner appoints
/// the top. The CEO appoints the chain manager, the chain manager appoints the regional manager of a city where the chain has four or more stores,
/// and the regional manager (else the chain manager, else the CEO) appoints the manager of every store that has none. Real basis: a franchise or
/// chain head office delegates the hiring of a unit manager to the area manager who will work with that person.
/// The appointer uses the same one door as the owner: a shortlist, a bargain weighed with their own skill (`AutoHire`), then `ManagerModel.hire`
/// or `ManagerModel.hireExecutive`. Their authority (`lvl`, `buy` on the boss record) decides what happens:
///  - authority 2 (full control), or authority 1 and a wage within their limit: they hire and the owner gets an inbox note;
///  - authority 0 (asks first), or a wage above their limit: the owner gets a request ("hier") naming the person and the wage and decides;
///  - nobody above the post: the vacancy stays with the owner (the Team vacancy screen).
/// The owner can always hire into the post themselves. A post is searched for only once it has been open `searchWeeks` (the staffing plan's timing), and the
/// company that gets the manager pays a recruiting fee. Saved only when used: `rest["hier"]` holds the week each post may be tried again and, under "o:" + key, the week it opened.
public enum HierarchyHiring {
    public static let action = "hier"
    /// A city with this many open stores of one chain gets its own regional manager.
    public static let regionalMinStores = 4
    static let retryWeeks = 2
    /// Weeks a post is open before the search ends in an offer, and the fee in months of the wage once someone is appointed.
    static let searchWeeks = StaffingPlan.searchWeeks
    static let feeMonths = 0.5
    static let declineWeeks = 8

    public enum Post: Equatable, Sendable {
        case storeManager(companyID: Int)
        case regional(chainID: Int, cityID: String)
        case chainManager(chainID: Int)

        var key: String {
            switch self {
            case .storeManager(let id): return "m\(id)"
            case .regional(let cid, let city): return "r\(cid):\(city)"
            case .chainManager(let cid): return "c\(cid)"
            }
        }
    }

    /// The person who hires into a post: the lowest rank above it.
    public struct Appointer: Equatable, Sendable {
        public var personID: Int
        /// region, chainmgr or ceo56.
        public var kind: String
        public var name: String
        public var title: String
        /// 0 asks the owner first, 1 within limits, 2 full control.
        public var level: Int
        public var buy: Double
    }

    // MARK: Who appoints

    static func firstStore(_ s: GameState, _ chainID: Int) -> Company? {
        Chains.chain(s, id: chainID).flatMap { ch in Chains.stores(s, ch).first { $0.status.isLive } }
    }

    /// Who hires into this post, nil when nobody stands above it (then it is the owner's).
    public static func appointer(_ s: GameState, post: Post, data: GameData) -> Appointer? {
        var kinds: [String]
        var anchor: Company?
        switch post {
        case .storeManager(let id):
            anchor = s.company(id)
            kinds = anchor.flatMap { Chains.chain(s, of: $0) } != nil ? ["region", "chainmgr", "ceo56"] : ["region"]
        case .regional(let cid, _):
            anchor = firstStore(s, cid); kinds = ["chainmgr", "ceo56"]
        case .chainManager(let cid):
            anchor = firstStore(s, cid); kinds = ["ceo56"]
        }
        guard let co = anchor, let b = ManagerModel.decisionChain(s, co, data: data).first(where: { kinds.contains($0.kind) }) else { return nil }
        return Appointer(personID: b.personID, kind: b.kind, name: b.name, title: ManagerModel.titleFor(co, kind: b.kind, data: data, state: s), level: b.level, buy: b.buy)
    }

    /// Whether the appointer may take this wage on their own.
    public static func withinAuthority(_ a: Appointer, wage: Double) -> Bool { a.level >= 2 || (a.level >= 1 && wage <= a.buy) }

    /// A store with no manager and a boss above with authority: that boss also hires its ordinary staff (the store manager's job while there is none).
    public static func staffBoss(_ s: GameState, _ co: Company, data: GameData) -> Appointer? {
        guard co.managerID == nil, co.ownerHours <= 0, let b = appointer(s, post: .storeManager(companyID: co.id), data: data), b.level >= 1 else { return nil }
        return b
    }

    // MARK: Which posts are open

    static func needsStoreManager(_ s: GameState, _ co: Company, data: GameData) -> Bool {
        guard co.managerID == nil, co.status == .open || co.status == .setup, co.type != "hold", co.ownerHours <= 0, let bd = data.catalog[co.type], bd.family != "club" else { return false }
        return true
    }

    static func recentProfit(_ list: [Company]) -> Double {
        list.reduce(0) { acc, c in
            let h = c.monthlyHistory.suffix(3)
            return acc + (h.count == 3 ? h.reduce(0) { $0 + $1.profit } / 3 : 0)
        }
    }

    // MARK: When to try again

    static func nextTry(_ s: GameState, _ key: String) -> Int { s.rest["hier"]?[key].int ?? 0 }
    /// The week a post was first seen open (set on first sight, cleared when it is filled).
    static func openSince(_ s: inout GameState, _ post: Post, open: Bool) -> Int {
        let k = "o:" + post.key
        let now = s.rest["hier"]?[k]
        guard open else {
            if let n = now, !n.isNull { var h = s.rest["hier"] ?? .object([:]); h[k] = .null; s.rest["hier"] = h }
            return s.week
        }
        if let n = now, !n.isNull { return n.int }
        var h = s.rest["hier"] ?? .object([:])
        h[k] = .number(Double(s.week))
        s.rest["hier"] = h
        return s.week
    }

    /// Weeks a post has been open, for the staffing plan.
    public static func weeksOpen(_ s: GameState, _ post: Post) -> Int {
        guard let n = s.rest["hier"]?["o:" + post.key], !n.isNull else { return 0 }
        return max(0, s.week - n.int)
    }

    static func setNext(_ s: inout GameState, _ key: String, _ week: Int) {
        var h = s.rest["hier"] ?? .object([:])
        h[key] = .number(Double(week))
        s.rest["hier"] = h
    }

    // MARK: The weekly step

    /// Called every week from the group step. Chain levels first, so a new regional manager takes the stores of the city at once.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for ch in Chains.list(s) {
            let cid = ch["id"].int
            let stores = Chains.stores(s, ch).filter { $0.status == .open }
            guard !stores.isEmpty else { continue }
            let regs = ManagerModel.regionals(s)
            if stores.count >= 2, !regs.contains(where: { $0["scope"].string == "chain:\(cid)" }) { attempt(&s, post: .chainManager(chainID: cid), data: data) }
            let byCity = Dictionary(grouping: stores, by: { $0.cityID })
            for city in byCity.keys.sorted() where (byCity[city]?.count ?? 0) >= regionalMinStores && !regs.contains(where: { $0["scope"].string == "chain:\(cid):\(city)" }) {
                attempt(&s, post: .regional(chainID: cid, cityID: city), data: data)
            }
        }
        for id in s.companies.map({ $0.id }) {
            guard let co = s.company(id), needsStoreManager(s, co, data: data) else { _ = openSince(&s, .storeManager(companyID: id), open: false); continue }
            attempt(&s, post: .storeManager(companyID: id), data: data)
        }
    }

    /// Words for the post in messages: ("manager of Store", company id the message belongs to).
    static func describe(_ s: GameState, _ post: Post, data: GameData) -> (what: String, companyID: Int)? {
        switch post {
        case .storeManager(let id):
            guard let co = s.company(id), let bd = data.catalog[co.type] else { return nil }
            return ("\(ManagerModel.title(bd).lowercased()) of \(co.name)", id)
        case .regional(let cid, let city):
            guard let st = firstStore(s, cid) else { return nil }
            return ("regional manager for \(ManagerModel.cityName(s, city, data))", st.id)
        case .chainManager(let cid):
            guard let st = firstStore(s, cid), let ch = Chains.chain(s, id: cid) else { return nil }
            let name = ch["name"].string
            return ("chain manager of \(name.isEmpty ? "the chain" : name)", st.id)
        }
    }

    static func stillOpen(_ s: GameState, _ post: Post, data: GameData) -> Bool {
        switch post {
        case .storeManager(let id): return s.company(id).map { needsStoreManager(s, $0, data: data) } ?? false
        case .regional(let cid, let city): return !ManagerModel.regionals(s).contains { $0["scope"].string == "chain:\(cid):\(city)" } && Chains.chain(s, id: cid) != nil
        case .chainManager(let cid): return !ManagerModel.regionals(s).contains { $0["scope"].string == "chain:\(cid)" } && Chains.chain(s, id: cid) != nil
        }
    }

    /// One appointer, one post: search, bargain, then hire, or ask the owner.
    static func attempt(_ s: inout GameState, post: Post, data: GameData) {
        guard stillOpen(s, post, data: data) else { _ = openSince(&s, post, open: false); return }
        let opened = openSince(&s, post, open: true)
        guard let boss = appointer(s, post: post, data: data), let bossPerson = s.people[boss.personID], let d = describe(s, post, data: data) else { return }
        let key = post.key
        if s.week - opened < searchWeeks { return }
        if s.week < nextTry(s, key) { return }
        if s.inbox.contains(where: { $0.actionID == action && $0.status == "open" && $0.value("data")["key"].string == key }) { return }
        setNext(&s, key, s.week + retryWeeks)
        let hirer = AutoHire.hirer(person: bossPerson)
        var deal: AutoHire.Deal?
        switch post {
        case .storeManager(let id):
            guard let ci = s.companyIndex(id), let bd = data.catalog[s.companies[ci].type] else { return }
            var found = (0..<3).map { _ in ManagerModel.generateCandidate(company: s.companies[ci], type: bd.managerType, faces: false, state: &s, data: data) }
            found.append(ManagerModel.generateCandidate(company: s.companies[ci], type: "gen", faces: false, state: &s, data: data))
            deal = AutoHire.bestManagerDeal(candidates: found, companyID: id, hirer: hirer, state: &s, data: data)
        case .regional, .chainManager:
            var level = ManagerModel.ExecLevel.chainmgr
            if case .regional = post { level = .region }
            let found = ManagerModel.generateExecutives(&s, level: level, data: data)
            let cur = ManagerModel.playerCurrency(s, data)
            let rate = ManagerModel.executiveGoingRate(level: level, state: s, data: data)
            deal = AutoHire.bestDeal(found, hirer: hirer, rank: ManagerModel.execRank(level), floor: 0, currency: cur, about: 500,
                                     fair: { _, perceived in cur.roundedStep(rate * (0.8 + 0.4 * perceived / 100), about: 500) }, factor: { _ in 1 }, state: &s)
        }
        guard let deal = deal else { return }
        let wage = deal.price
        let cur = ManagerModel.playerCurrency(s, data)
        if !withinAuthority(boss, wage: wage) {
            let why = boss.level < 1 ? "\(boss.name) asks you before every hire." : "The pay is above the limit you set for \(boss.name)."
            s.addMessage(kind: "ask", from: boss.name, title: "Appoint \(deal.person.name) as \(d.what)?",
                         body: "\(boss.name) (\(boss.title.lowercased())) found \(deal.person.name) for the post of \(d.what) at \(cur.display(wage)) a month. \(why)",
                         companyID: d.companyID, tone: "n", status: "open",
                         options: [.option("Appoint \(deal.person.name)", "\(cur.display(wage)) a month."), .option("Not now", "\(boss.name) looks again later.")],
                         action: action, data: .object(["t": .string(action), "kind": .string(action), "key": .string(key), "npc": .number(Double(deal.person.id)), "wage": .number(wage),
                                                      "boss": .number(Double(boss.personID)), "lvl": .number(5)]), expiresWeek: s.week + 3)
            return
        }
        // the money: a store pays its own manager, so it needs a cushion (a sister store lends it, as for any chain request)
        if case .storeManager(let id) = post, let co = s.company(id) {
            let need = wage * 3 - co.cash
            if need > 0, ManagerModel.sisterCash(&s, to: co, need: need, data: data) == nil {
                s.note("\(boss.name) (\(boss.title.lowercased())) put off hiring a \(d.what): \(co.name) cannot yet pay a manager.", tone: "n", companyID: d.companyID)
                return
            }
        } else if case .regional(let cid, let city) = post {
            let there = Chains.chain(s, id: cid).map { Chains.stores(s, $0).filter { $0.status == .open && $0.cityID == city } } ?? []
            if recentProfit(there) < wage { return }
        } else if case .chainManager(let cid) = post {
            let all = Chains.chain(s, id: cid).map { Chains.stores(s, $0).filter { $0.status == .open } } ?? []
            if recentProfit(all) < wage { return }
        }
        guard execute(&s, post: post, personID: deal.person.id, wage: wage, data: data) else { return }
        payFee(&s, post: post, wage: wage, data: data)
        s.addMessage(kind: "info", from: boss.name, title: "\(deal.person.name) appointed as \(d.what)",
                     body: "\(boss.name) (\(boss.title.lowercased())) appointed \(deal.person.name) as \(d.what) at \(cur.display(wage)) a month, within the authority you gave. You can change the pay or let them go in Team.",
                     companyID: d.companyID, tone: "good", status: "done")
    }

    /// The hire itself, through the doors the owner uses.
    @discardableResult
    static func execute(_ s: inout GameState, post: Post, personID: Int, wage: Double, data: GameData) -> Bool {
        switch post {
        case .storeManager(let id): return ManagerModel.hire(&s, personID: personID, companyID: id, monthlyWage: wage, data: data) == .ok
        case .regional(let cid, let city): return ManagerModel.hireExecutive(&s, level: .region, personID: personID, monthlyWage: wage, chainID: cid, city: city, data: data) == .ok
        case .chainManager(let cid): return ManagerModel.hireExecutive(&s, level: .chainmgr, personID: personID, monthlyWage: wage, chainID: cid, city: nil, data: data) == .ok
        }
    }

    /// The recruiting fee for an appointment, paid by the company the post belongs to.
    static func payFee(_ s: inout GameState, post: Post, wage: Double, data: GameData) {
        guard let id = describe(s, post, data: data)?.companyID else { return }
        Payments.companyPays(&s, companyID: id, amount: jsRound(wage * feeMonths), category: "oth", label: "Recruiting: manager")
    }

    static func post(from key: String) -> Post? {
        guard let first = key.first else { return nil }
        let rest = String(key.dropFirst())
        switch first {
        case "m": return Int(rest).map { .storeManager(companyID: $0) }
        case "c": return Int(rest).map { .chainManager(chainID: $0) }
        case "r":
            let parts = rest.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let cid = Int(parts[0]) else { return nil }
            return .regional(chainID: cid, cityID: parts[1])
        default: return nil
        }
    }

    /// The owner's answer to a request: option 0 appoints the person named, anything else makes the appointer look again in eight weeks.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        let d = m.value("data")
        let key = d["key"].string
        guard let post = post(from: key) else { return }
        guard idx == 0 else { setNext(&s, key, s.week + declineWeeks); return }
        guard stillOpen(s, post, data: data), let n = s.people[d["npc"].int], n.employerID == 0, execute(&s, post: post, personID: n.id, wage: max(1, d["wage"].double), data: data) else {
            if let n = s.people[d["npc"].int] {
                s.addMessage(kind: "info", from: n.name, title: "Changed my mind", body: "Sorry, the post is no longer open or I took another job.", companyID: m.companyID, tone: "bad", status: "done")
            }
            return
        }
        payFee(&s, post: post, wage: max(1, d["wage"].double), data: data)
    }
}
