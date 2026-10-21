import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Chains: several stores of one trade under one name, with shared rules, a known brand and cheaper buying. A chain is
/// registered first (a lawyer writes the operations manual), then you open or add stores. Original:
/// features/company/chain_registration_and_boards.js (registration, new stores), features/company/shelf_stock_chains_boards.js
/// (`makeChain`, `joinChain`, `applyRules`, `chainWeek`, the rules tab), engine/company/chain.js (`reachOf`, `chainWeek`, `rebate`),
/// engine/suppliers/own_group.js (`ownSupply`) and features/company/branches_and_addresses.js (stores under one name).
/// The chains are saved in `rest["chains"]`; a store carries `chain` (the chain's id) and `off` (its own rules).
/// Boards, chiefs, group loans and price requests are in `ManagerBoards`, `ManagerTeam`, `ChainHierarchy`.
public enum Chains {
    // MARK: Registry

    static func list(_ s: GameState) -> [JSONValue] { s.rest["chains"]?.array ?? [] }
    public static func all(_ s: GameState) -> [JSONValue] { list(s) }
    public static func chain(_ s: GameState, id: Int) -> JSONValue? { list(s).first { $0["id"].int == id } }
    public static func chain(_ s: GameState, of co: Company) -> JSONValue? {
        let id = co.value("chain")
        return id.isNull ? nil : chain(s, id: id.int)
    }
    /// The live stores of a chain, oldest first.
    public static func stores(_ s: GameState, _ ch: JSONValue) -> [Company] {
        s.companies.filter { $0.status.isLive && !$0.value("chain").isNull && $0.value("chain").int == ch["id"].int }
    }
    static func save(_ s: inout GameState, _ ch: JSONValue) {
        var L = list(s)
        if let k = L.firstIndex(where: { $0["id"].int == ch["id"].int }) { L[k] = ch } else { L.append(ch) }
        s.rest["chains"] = .array(L)
    }

    /// Someone who looks after the chain above the store managers: a chain chief, a managing director, a group CEO, or (here) a manager in every store of a chain of three. Original: `chiefs`, `S.org56.md`, `ch.ceo56`.
    static func hasChainBoss(_ s: GameState, _ ch: JSONValue, stores L: [Company]) -> Bool {
        let key = "chain:\(ch["id"].int)"
        if (s.rest["group"]?["regional"].array ?? []).contains(where: { $0["scope"].string.hasPrefix(key) }) { return true }
        if let md = s.rest["org56"]?["md"], !md.isNull, s.people[md["npc"].int] != nil { return true }
        if !ch["ceo56"].isNull { return true }
        if let ceo = s.rest["group"]?["ceo"], !ceo.isNull { return true }
        let open = L.filter { $0.status == .open }
        return open.count >= 3 && open.allSatisfy { $0.managerID != nil }
    }

    // MARK: Documents the chain and franchise features add

    /// Original: `DOCS.chain`, `DOCS.fran`, `DOCS.fran_op`.
    static let extraDocuments: [String: JSONValue] = [
        "chain": .array(["Chain registration and operations manual", "Business lawyer", 18000, 4, 0, "Registers the brand for more stores and writes the manual every store follows."]),
        "fran": .array(["Franchise disclosure document and concept manual", "Franchise lawyer", 25000, 6, 0, "Describes the concept, fees, support and obligations."]),
        "fran_op": .array(["Franchise operating agreement", "Franchisor", 0, 0, 0, "Your signed agreement with the brand."]),
    ]

    // MARK: Registration

    public struct Requirement: Equatable, Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var ok: Bool
        public var detail: String
    }

    /// A chain comes when the first store has proven itself. Original: `R12.chainReq`.
    public static func requirements(_ s: GameState, _ co: Company) -> [Requirement] {
        let age = s.week - (co.openedWeek ?? s.week)
        let H = Array(co.monthlyHistory.suffix(12))
        let good = H.filter { $0.profit > 0 }.count
        func months(_ w: Int) -> Int { Int((Double(max(0, w)) / 4.33).rounded(.up)) }
        return [
            Requirement(title: "Open for two years", ok: age >= 104, detail: age >= 104 ? "Open \(age / 52) years" : "\(months(104 - age)) months to go"),
            Requirement(title: "Money made in 9 of the last 12 months", ok: H.count >= 12 && good >= 9, detail: "\(good) of the last \(H.count) months"),
            Requirement(title: "Customers like it", ok: co.reputation >= 50, detail: "reputation \(Int(co.reputation))"),
            Requirement(title: "Someone runs it while you are away", ok: co.managerID != nil || !co.value("asst").isNull, detail: co.managerID != nil ? "A manager runs it" : "Hire a manager"),
        ]
    }

    public enum ChainDocResult: Equatable, Sendable { case ok, notYet(String), alreadyHeld, notEnoughCash, notFound }

    /// Apply for the chain registration (`doc` "chain") or the franchise documents ("fran"); the requirements must be met first.
    /// Original: `applyDoc` with the `applyDoc.check` steps of chain_registration_and_boards.js and deals.js.
    public static func applyDocument(_ s: inout GameState, companyID: Int, doc: String, data: GameData) -> ChainDocResult {
        guard let i = s.companyIndex(companyID), doc == "chain" || doc == "fran" else { return .notFound }
        let co = s.companies[i]
        if doc == "chain" && !co.value("chain").isNull { return .alreadyHeld }
        if doc == "chain", let miss = requirements(s, co).first(where: { !$0.ok }) { return .notYet("Not yet: \(miss.title.lowercased()) (\(miss.detail.lowercased())).") }
        if doc == "fran" {
            if co.value("fr")["on"].bool { return .alreadyHeld }
            if let miss = Franchising.requirements(s, co).first(where: { !$0.ok }) { return .notYet("Not yet: \(miss.title.lowercased()) (\(miss.detail.lowercased())).") }
        }
        switch Documents.apply(doc, companyID: companyID, state: &s, data: data) {
        case .ok: return .ok
        case .alreadyHeld: return .alreadyHeld
        case .notEnoughCash: return .notEnoughCash
        case .pickAccountant: return .notFound
        }
    }

    /// Name the chain: every store carries it. Original: `makeChain` (`ACT.ch12make`).
    @discardableResult
    public static func make(_ s: inout GameState, companyID: Int, name: String) -> Int? {
        guard let i = s.companyIndex(companyID) else { return nil }
        let co = s.companies[i]
        if let existing = chain(s, of: co) { return existing["id"].int }
        guard co.value("docs")["chain"]["st"].string == "ok" else { return nil }
        let nm = name.trimmingCharacters(in: .whitespaces).isEmpty ? co.name : name.trimmingCharacters(in: .whitespaces)
        let id = s.makeID()
        let rules: JSONValue = .object(["price": .number(co.priceLevel), "knob": co.value("knob").isNull ? .object([:]) : co.value("knob"), "stockPol": .number(co.num("stockPol", 1)), "pay": 0, "mkt": "own"])
        let ch: JSONValue = .object(["id": .number(Double(id)), "name": .string(nm), "type": .string(co.type), "w0": .number(Double(s.week)), "rules": rules])
        save(&s, ch)
        join(&s, chainID: id, companyID: companyID, rename: false)
        return id
    }

    static func storeName(_ s: GameState, chain ch: JSONValue, _ co: Company, data: GameData) -> String {
        let city = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? ""
        let taken: (String) -> Bool = { n in s.companies.contains { $0.id != co.id && $0.name == n } }
        let base = ch["name"].string + " " + city
        if !taken(base) { return base }
        for i in 2..<40 where !taken("\(base) \(i)") { return "\(base) \(i)" }
        return "\(ch["name"].string) \(s.nextID)"
    }

    /// A store joins a chain and follows its rules. Original: `joinChain`.
    public static func join(_ s: inout GameState, chainID: Int, companyID: Int, rename: Bool, data: GameData? = nil) {
        guard let ch = chain(s, id: chainID), let i = s.companyIndex(companyID) else { return }
        s.companies[i].set("chain", chainID)
        if s.companies[i].value("off").isNull { s.companies[i].set("off", .object(["price": 0, "mkt": 0, "pay": 0, "stock": .null])) }
        if rename, let d = data, !s.companies[i].name.hasPrefix(ch["name"].string) {
            s.companies[i].name = storeName(s, chain: ch, s.companies[i], data: d)
        }
        applyRules(&s, chain: ch, companyIndex: i)
    }

    /// A place in a chain that is short of a role, and a sister store that has one more than it needs. Original: the "Short of staff" list.
    public struct Shortage: Equatable, Sendable { public var storeID: Int; public var role: String; public var spareAtStoreID: Int? }

    public static func staffShortages(_ s: GameState, chainID: Int, data: GameData) -> [Shortage] {
        guard let ch = chain(s, id: chainID) else { return [] }
        let stores = stores(s, ch)
        func std(_ c: Company, _ role: String) -> Int {
            guard let bd = data.catalog[c.type] else { return 0 }
            return CompanySetup.standardStaff(bd, size: c.size).filter { $0.role == role }.reduce(0) { $0 + $1.count }
        }
        func have(_ c: Company, _ role: String) -> Int { c.staff.filter { $0.role == role }.count }
        var out: [Shortage] = []
        for c in stores {
            guard let bd = data.catalog[c.type] else { continue }
            for r in CompanySetup.standardStaff(bd, size: c.size) where have(c, r.role) < r.count {
                out.append(Shortage(storeID: c.id, role: r.role, spareAtStoreID: stores.first { $0.id != c.id && have($0, r.role) > std($0, r.role) }?.id))
            }
        }
        return out
    }

    /// Lend the least skilled person of a role from one store of a chain to another. Original: `ACT.ch12lend`.
    @discardableResult
    public static func lendWorker(_ s: inout GameState, from fromID: Int, to toID: Int, role: String, data: GameData) -> Bool {
        guard let a = s.companyIndex(fromID), let b = s.companyIndex(toID), a != b,
              let ca = chain(s, of: s.companies[a]), let cb = chain(s, of: s.companies[b]), ca["id"].int == cb["id"].int else { return false }
        let tables = data.catalog.tables
        let pick = s.companies[a].staff.filter { $0.role == role }
            .min { StaffModel.skill($0, person: s.people[$0.id], salesRoles: tables.salesRoles) < StaffModel.skill($1, person: s.people[$1.id], salesRoles: tables.salesRoles) }
        guard let m = pick else { return false }
        s.companies[a].staff = s.companies[a].staff.filter { $0.id != m.id }
        s.companies[b].staff = s.companies[b].staff + [m]
        if var p = s.people[m.id] { p.employerID = toID; s.people[m.id] = p }
        s.note("\(s.people[m.id]?.name ?? "A worker") moves to \(s.companies[b].name).", companyID: toID)
        return true
    }

    /// The chain's rules on a store: price (plus its own step), the business choices, ordering. Original: `applyRules`.
    static func applyRules(_ s: inout GameState, chain ch: JSONValue, companyIndex i: Int) {
        let R = ch["rules"], o = s.companies[i].value("off")
        s.companies[i].priceLevel = clamp(R["price"].double + o["price"].double, -3, 3)
        var knob = s.companies[i].value("knob")
        for (k, v) in R["knob"].object { knob[k] = v }
        s.companies[i].set("knob", knob)
        s.companies[i].set("stockPol", o["stock"].isNull ? R["stockPol"].double : o["stock"].double)
    }

    static func applyAll(_ s: inout GameState, chain ch: JSONValue) {
        for c in stores(s, ch) { if let i = s.companyIndex(c.id) { applyRules(&s, chain: ch, companyIndex: i) } }
    }

    public enum Rule: Equatable, Sendable { case price(Double), knob(id: String, option: Int), stockPolicy(Int), pay(Double), marketing(String) }

    /// Set one chain rule for every store. Original: `ACT.ch12rule`.
    public static func setRule(_ s: inout GameState, chainID: Int, rule: Rule) {
        guard var ch = chain(s, id: chainID) else { return }
        switch rule {
        case .price(let v): ch["rules"]["price"] = .number(clamp(v, -3, 3))
        case .knob(let id, let o): ch["rules"]["knob"][id] = .number(Double(o))
        case .stockPolicy(let v): ch["rules"]["stockPol"] = .number(Double(min(2, max(0, v))))
        case .pay(let v): ch["rules"]["pay"] = .number(v)
        case .marketing(let m): ch["rules"]["mkt"] = .string(m)
        }
        save(&s, ch)
        applyAll(&s, chain: ch)
    }

    public enum StoreRule: Equatable, Sendable { case priceSteps(Double), marketing(Double), pay(Double), ordering(Int?) }

    /// One store's own rule on top of the chain's. Original: `ACT.ch12off`.
    public static func setStoreRule(_ s: inout GameState, companyID: Int, rule: StoreRule) {
        guard let i = s.companyIndex(companyID), let ch = chain(s, of: s.companies[i]) else { return }
        var o = s.companies[i].value("off")
        if o.isNull { o = .object(["price": 0, "mkt": 0, "pay": 0, "stock": .null]) }
        switch rule {
        case .priceSteps(let v): o["price"] = .number(v)
        case .marketing(let v): o["mkt"] = .number(v)
        case .pay(let v): o["pay"] = .number(v)
        case .ordering(let v): o["stock"] = v.map { .number(Double($0)) } ?? .null
        }
        s.companies[i].set("off", o)
        applyRules(&s, chain: ch, companyIndex: i)
    }

    // MARK: Opening another store

    /// What a new store costs: the start-up estimate plus 15%. Original: `nsEst`.
    public static func newStoreCost(_ s: GameState, chainID: Int, cityID: String, size: Double, data: GameData) -> Double? {
        guard let ch = chain(s, id: chainID), let first = stores(s, ch).first,
              let est = CompanySetup.estimate(tradeID: ch["type"].string, cityID: cityID, form: first.form, size: size, countryCode: first.countryCode, state: s, data: data) else { return nil }
        return (est.total * 1.15 / 1000).rounded() * 1000
    }

    /// Open a new store: premises, equipment and people to the chain's standard, running on the chain's rules from day one.
    /// Original: `ACT.ns13go`.
    /// `fundedBy` (store id: amount): a chain that pays for the store from its own stores' spare cash instead of you. The store opens three weeks later.
    public static func openStore(_ s: inout GameState, chainID: Int, cityID: String, size: Double, data: GameData, context fc: FinanceContext, fundedBy parts: [Int: Double]? = nil) -> Result<Int, CompanySetup.StartError> {
        guard let ch = chain(s, id: chainID), let first = stores(s, ch).first, let cost = newStoreCost(s, chainID: chainID, cityID: cityID, size: size, data: data) else { return .failure(.notAllowedHere) }
        if parts == nil && Payments.liquid(s) < cost { return .failure(.notEnoughCash) }
        let r = CompanySetup.create(&s, tradeID: ch["type"].string, cityID: cityID, form: first.form, size: size, name: "New store \(s.nextID + 1)", countryCode: first.countryCode, data: data, context: fc)
        guard case .success(let id) = r, let i = s.companyIndex(id) else { return r }
        if let parts = parts {
            for (sid, x) in parts.sorted(by: { $0.key < $1.key }) {
                Payments.companyPays(&s, companyID: sid, amount: x, category: nil, label: "Funding a new store")
                Payments.companyReceives(&s, companyID: id, amount: x, category: nil, label: "Funding from sister stores")
            }
        } else { Payments.injectCash(&s, companyID: id, amount: cost) }
        // The paperwork the first store already has is the chain's: copy what is approved.
        var docs = s.companies[i].value("docs")
        for (k, d) in first.value("docs").object where d["st"].string == "ok" && k != "chain" && k != "accountant_agreement" && docs[k].isNull { docs[k] = d }
        s.companies[i].set("docs", docs)
        s.companies[i].ownerHours = 0
        _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        join(&s, chainID: chainID, companyID: id, rename: true, data: data)
        if let k = s.companyIndex(id) { s.companies[k].set("open13", s.week + 3) }   // a new store opens three weeks after it is set up (ManagerModel.openingWait)
        s.note("\(s.company(id)?.name ?? "A new store") is being set up for \(ch["name"].string).", tone: "good", companyID: id)
        return .success(id)
    }

    // MARK: Stores under one name, not yet a chain

    public struct LooseGroup: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var tradeID: String
        public var companyIDs: [Int]
    }

    static func baseName(_ co: Company, data: GameData) -> String {
        var n = co.name.trimmingCharacters(in: .whitespaces)
        let city = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? ""
        while let r = n.range(of: #"\s+\d+$"#, options: .regularExpression) { n.removeSubrange(r) }
        if !city.isEmpty && n.hasSuffix(" " + city) { n.removeLast(city.count + 1) }
        while let r = n.range(of: #"\s+\d+$"#, options: .regularExpression) { n.removeSubrange(r) }
        return n.lowercased()
    }

    /// Two or more companies of one trade under the same name that are not a registered chain. Original: `BR56.groupOf`.
    public static func looseGroups(_ s: GameState, data: GameData) -> [LooseGroup] {
        var by: [String: [Company]] = [:]
        for c in s.companies where c.status.isLive && c.value("chain").isNull && c.type != "hold" { by["\(c.type)|\(c.countryCode)|\(baseName(c, data: data))", default: []].append(c) }
        return by.keys.sorted().compactMap { k in
            guard let L = by[k], L.count >= 2 else { return nil }
            let nm = L.sorted { $0.name.count < $1.name.count }[0].name
            return LooseGroup(id: k, name: nm, tradeID: L[0].type, companyIDs: L.map { $0.id })
        }
    }

    // MARK: Reach

    public struct Reach: Equatable, Sendable {
        public var outlets: Int
        public var countries: Int
        public var label: String
        /// Most people who can know the name: one shop is a local name
        public var awarenessCap: Double
        /// Outlets needed for the next step, 0 at the top
        public var nextAt: Int
        public var demandFactor: Double
        public var rebate: Double
    }

    /// One shop is a local name; many outlets build a known brand. Original: `reachOf`.
    public static func reach(_ s: GameState, _ co: Company, data: GameData) -> Reach {
        let w = World(state: s, data: data)
        let n = Competition.chainOutlets(co, w)
        var cs = Set<String>()
        for c in s.companies where c.type == co.type && c.status.isLive { cs.insert(c.countryCode) }
        for c in s.companies where c.type == co.type && c.status.isLive { for m in c.value("fr")["masters"].array { cs.insert(m["c"].string) } }
        let k = cs.count
        let label = n >= 60 && k >= 3 ? "Worldwide" : n >= 25 && k >= 2 ? "International" : n >= 10 ? "National" : n >= 3 ? "Regional" : "Local"
        let next = ["Local": 3, "Regional": 10, "National": 25, "International": 60, "Worldwide": 0][label] ?? 0
        let l2 = log2(Double(n))
        return Reach(outlets: n, countries: k, label: label, awarenessCap: clamp(36 + 17 * l2, 36, 100), nextAt: next, demandFactor: 1 + 0.03 * l2, rebate: n > 1 ? min(0.035, 0.008 * l2) : 0)
    }

    // MARK: Read models for the screens

    public struct StoreLine: Equatable, Identifiable, Sendable {
        public var id: Int
        public var name: String
        public var cityName: String
        public var status: CompanyStatus
        public var revenue: Double
        public var profit: Double
        public var staff: Int
        public var managerName: String?
        public var ownRules: Int
    }

    public struct Summary: Equatable, Identifiable, Sendable {
        public var id: Int
        public var name: String
        public var tradeID: String
        public var stores: [StoreLine]
        public var revenue: Double
        public var profit: Double
        public var staff: Int
        public var franchiseUnits: Int
        public var reach: Reach
        public var franchisingCompanyID: Int?
    }

    public static func summaries(_ s: GameState, data: GameData) -> [Summary] {
        list(s).compactMap { ch -> Summary? in
            let L = stores(s, ch)
            guard let first = L.first else { return nil }
            let lines = L.map { c -> StoreLine in
                let m = c.monthlyHistory.last
                let o = c.value("off")
                let own = (o["price"].double != 0 ? 1 : 0) + (o["mkt"].double != 0 ? 1 : 0) + (o["pay"].double != 0 ? 1 : 0) + (o["stock"].isNull ? 0 : 1)
                return StoreLine(id: c.id, name: c.name, cityName: data.countries.city(c.cityID, preferring: c.countryCode)?.city.name ?? "", status: c.status,
                                 revenue: m?.revenue ?? 0, profit: m?.profit ?? 0, staff: c.staff.count + (c.managerID != nil ? 1 : 0),
                                 managerName: c.managerID.flatMap { s.people[$0]?.name }, ownRules: own)
            }
            let flag = L.first { $0.value("fr")["on"].bool } ?? first
            return Summary(id: ch["id"].int, name: ch["name"].string, tradeID: ch["type"].string, stores: lines, revenue: lines.reduce(0) { $0 + $1.revenue },
                           profit: lines.reduce(0) { $0 + $1.profit }, staff: lines.reduce(0) { $0 + $1.staff },
                           franchiseUnits: L.reduce(0) { $0 + $1.value("fr")["units"].array.count }, reach: reach(s, first, data: data),
                           franchisingCompanyID: FranchiseBrands.isFranchisable(ch["type"].string) ? flag.id : nil)
        }
    }

    // MARK: The week

    static func rebate(_ s: inout GameState, _ id: Int, _ amount: Double) {
        let a = amount.rounded()
        if a <= 0 { return }
        Payments.companyReceives(&s, companyID: id, amount: a, category: nil, label: nil)
        Payments.book(&s, companyID: id, category: "cogs", amount: -a)
    }

    /// Brand marketing, volume discounts, shared awareness and pay for every chain. Original: `chainWeek` (shelf_stock_chains_boards.js).
    static func chainsWeek(_ s: inout GameState, data: GameData, marketing: MarketingTables) {
        let share: [String: Double] = ["own": 0, "light": 0.015, "normal": 0.03, "heavy": 0.05]
        for ch in list(s) {
            let L = stores(s, ch)
            if L.isEmpty { continue }
            guard let bd = data.catalog[ch["type"].string] else { continue }
            let n = L.count
            let R = ch["rules"]
            let own = R["mkt"].string == "own"
            let lvl = share[R["mkt"].string] ?? 0
            for c0 in L {
                guard let i = s.companyIndex(c0.id) else { continue }
                applyRules(&s, chain: ch, companyIndex: i)
                if s.companies[i].status != .open { continue }
                let co = s.companies[i]
                let offMkt = co.value("off")["mkt"].double
                if !own || offMkt != 0 {
                    let rev = co.lastWeekRevenue
                    let sh = (own ? 0 : lvl) + offMkt
                    let fit: (String) -> Double = { k in
                        guard let c = marketing.channels[k] else { return 0 }
                        return Marketing.channelAffinity(bd, k, marketing.affinityByFamily, marketing.affinityByTrade) * ((1 - bd.audience) * c.localShare + bd.audience * c.businessShare) * c.efficiency
                    }
                    let ks = marketing.channels.keys.filter { k in let c = marketing.channels[k]!; return !c.isPrimeTime && !c.isNational && !c.isHighVariance }
                        .sorted { fit($0) != fit($1) ? fit($0) > fit($1) : $0 < $1 }.prefix(2)
                    let b = (max(rev * sh, sh > 0 ? Currency(country: data.countries.resolve(co.countryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values)).scaledPrice(300) : 0) / Double(max(1, ks.count))).rounded()
                    var mkt = co.value("mkt")
                    for old in co.value("mk12").array where !ks.contains(old.string) { mkt = Marketing.removing(mkt, old.string) }
                    for k in ks {
                        if b > 0 { mkt[k] = .object(["b": .number(b), "since": mkt[k]["since"].isNull ? .number(Double(s.week)) : mkt[k]["since"]]) } else { mkt = Marketing.removing(mkt, k) }
                    }
                    s.companies[i].set("mkt", mkt)
                    s.companies[i].set("mk12", .array(ks.map { .string($0) }))
                }
                let lw = s.companies[i].value("lastW")
                if n >= 2 && lw["cogs"].double > 0 { rebate(&s, co.id, lw["cogs"].double * min(0.05, 0.01 * Double(n - 1))) }
                let acc = s.companies[i].books.week["acc"] ?? 0
                if n >= 2 && acc > 0 {
                    let x = (acc * 0.15).rounded()
                    Payments.companyReceives(&s, companyID: co.id, amount: x, category: nil, label: nil)
                    Payments.book(&s, companyID: co.id, category: "acc", amount: -x)
                }
            }
            // one brand: the name is as well known in a city as its best-known store
            var byCity: [String: Double] = [:]
            for c in stores(s, ch) { byCity[c.cityID] = max(byCity[c.cityID] ?? 0, c.awareness) }
            for c in stores(s, ch) { if let i = s.companyIndex(c.id) { s.companies[i].awareness = max(s.companies[i].awareness, (byCity[c.cityID] ?? 0) * 0.85) } }
            if GameCalendar.isMonthEnd(week: s.week) { chainPay(&s, ch, data: data) }
        }
    }

    /// Anyone paid below the chain's level gets a raise at month end.
    static func chainPay(_ s: inout GameState, _ ch: JSONValue, data: GameData) {
        for c in stores(s, ch) {
            guard let i = s.companyIndex(c.id), let country = data.countries[c.countryCode], let city = country.city(c.cityID) ?? country.cities.first else { continue }
            let rates = ExchangeRates(drift: s.exchangeRates.values)
            var staff = s.companies[i].staff
            var changed = false
            for k in staff.indices {
                guard let base = data.catalog.tables.roles[staff[k].role]?.baseMonthlyWage, let person = s.people[staff[k].id] else { continue }
                let market = Wages.market(baseMonthlyWage: base, country: country, city: city, economy: s.economy, week: s.week, rates: rates)
                let tgt = market * staff[k].partTimeShare * (0.7 + person.skill / 160) * (1 + ch["rules"]["pay"].double + c.value("off")["pay"].double)
                if staff[k].monthlyWage < tgt * 0.97 { staff[k].monthlyWage = (tgt / 100).rounded() * 100; changed = true }
            }
            if changed { s.companies[i].staff = staff }
        }
    }

    /// Reach discounts for every open company, and the car dealer's own vehicle plant. Original: `chainWeek(co)` in chain.js, `ownSupply`.
    static func reachWeek(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices {
            let co = s.companies[i]
            guard co.status == .open, co.type != "club" else { continue }
            let lw = co.value("lastW")
            if co.type == "cardealer", lw["rev"].double > 0, let pl = s.companies.first(where: { $0.type == "factory" && $0.status == .open && $0.id != co.id && $0.value("knob")["line"].int >= 1 }) {
                let rev = lw["rev"].double
                rebate(&s, co.id, min(rev * 0.06, lw["cogs"].double * 0.12))
                Payments.companyReceives(&s, companyID: pl.id, amount: rev * 0.04, category: "rev", label: "Wholesale to \(co.name)")
                let cap = clamp(36 + 17 * log2(Double(max(1, Competition.chainOutlets(co, World(state: s, data: data))))), 36, 100)
                s.companies[i].awareness = max(s.companies[i].awareness, min(cap, pl.awareness * 0.5))
            }
            let r = reach(s, s.companies[i], data: data)
            let lw2 = s.companies[i].value("lastW")
            if r.rebate > 0 && lw2["rev"].double > 0 && lw2["cogs"].double > 0 {
                rebate(&s, co.id, min(lw2["rev"].double * r.rebate, lw2["cogs"].double * 0.15))
            }
        }
    }

    /// Chains, reach and franchising, once a week after the companies' own weeks.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext, marketing: MarketingTables) {
        chainsWeek(&s, data: data, marketing: marketing)
        reachWeek(&s, data: data)
        Franchising.weekly(&s, data: data, context: fc)
        IntercompanySupply.weekly(&s, data: data)
        ManagerModel.groupWeekly(&s, data: data, context: fc, marketing: marketing)   // management team, boards, chain bosses, group loans, the office
    }
}
