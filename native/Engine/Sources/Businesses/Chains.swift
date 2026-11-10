import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum Chains {

    static func list(_ s: GameState) -> [JSONValue] { s.rest["chains"]?.array ?? [] }
    public static func all(_ s: GameState) -> [JSONValue] { list(s) }
    public static func chain(_ s: GameState, id: Int) -> JSONValue? { list(s).first { $0["id"].int == id } }
    public static func chain(_ s: GameState, of co: Company) -> JSONValue? {
        let id = co.value("chain")
        return id.isNull ? nil : chain(s, id: id.int)
    }
    public static func stores(_ s: GameState, _ ch: JSONValue) -> [Company] {
        s.companies.filter { $0.status.isLive && !$0.value("chain").isNull && $0.value("chain").int == ch["id"].int }
    }
    public static func save(_ s: inout GameState, _ ch: JSONValue) {
        var L = list(s)
        if let k = L.firstIndex(where: { $0["id"].int == ch["id"].int }) { L[k] = ch } else { L.append(ch) }
        s.rest["chains"] = .array(L)
    }

    static let extraDocuments: [String: JSONValue] = [
        "trademark": .array(["Trademark registration", "Intellectual property office", 4200, 6, 0, "Registers the brand name so nobody else can use it. The office reviews it for 4 to 8 weeks."]),
        "ops_manual": .array(["Operations manual", "Written by your own team", 900, 3, 0, "How every store is run, written by you or your manager over a few weeks. No authority reviews it."]),
        "chain": .array(["Chain registration", "Business lawyer", 6000, 2, 0, "Puts the stores under one name and one set of rules."]),
        "fran": .array(["Franchise disclosure document", "Franchise lawyer", 25000, 6, 0, "Prepared with a lawyer: describes the concept, fees, support and obligations. It must be signed and reviewed."]),
        "fran_op": .array(["Franchise operating agreement", "Franchisor", 0, 0, 0, "Your signed agreement with the brand."]),
    ]

    public enum RequirementStatus: String, Equatable, Sendable { case done, waiting, missing }

    public struct Requirement: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String
        public var title: String
        public var ok: Bool
        public var detail: String
        public var status: RequirementStatus
        public init(title: String, ok: Bool, detail: String, key: String? = nil, status: RequirementStatus? = nil) {
            self.title = title; self.ok = ok; self.detail = detail; self.key = key ?? title
            self.status = status ?? (ok ? .done : .missing)
        }
    }

    static func grantPapers(_ s: inout GameState, _ i: Int, _ ids: [String]) {
        var docs = s.companies[i].value("docs")
        for id in ids where docs[id]["st"].string != "ok" {
            docs[id] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week)), "w0": .number(Double(s.week))])
        }
        s.companies[i].set("docs", docs)
    }

    @discardableResult
    public static func make(_ s: inout GameState, companyID: Int, name: String, data: GameData? = nil) -> Int? {
        guard let i = s.companyIndex(companyID) else { return nil }
        let co = s.companies[i]
        if let existing = chain(s, of: co) { return existing["id"].int }
        grantPapers(&s, i, ["trademark", "ops_manual", "chain"])
        let nm = name.trimmingCharacters(in: .whitespaces).isEmpty ? co.name : name.trimmingCharacters(in: .whitespaces)
        let id = s.makeID()
        let rules: JSONValue = .object(["price": .number(co.priceLevel), "knob": co.value("knob").isNull ? .object([:]) : co.value("knob"), "stockPol": .number(co.num("stockPol", 1)), "pay": 0, "mkt": "own"])
        let ch: JSONValue = .object(["id": .number(Double(id)), "name": .string(nm), "type": .string(co.type), "w0": .number(Double(s.week)), "rules": rules, "hq": .object(["w0": .number(Double(s.week))])])
        save(&s, ch)
        join(&s, chainID: id, companyID: companyID, rename: false)
        if let d = data, let i = s.companyIndex(companyID) { s.companies[i].name = storeName(s, chain: ch, s.companies[i], data: d) }
        return id
    }

    public static func storeName(_ s: GameState, chain ch: JSONValue, _ co: Company, data: GameData) -> String {
        let city = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? ""
        return LocationNames.locationName(s, brand: ch["name"].string, countryCode: co.countryCode, cityID: co.cityID, cityName: city, excluding: co.id, data: data)
    }

    public static func join(_ s: inout GameState, chainID: Int, companyID: Int, rename: Bool, data: GameData? = nil) {
        guard let ch = chain(s, id: chainID), let i = s.companyIndex(companyID) else { return }
        s.companies[i].set("chain", chainID)
        if s.companies[i].value("off").isNull { s.companies[i].set("off", .object(["price": 0, "mkt": 0, "pay": 0, "stock": .null])) }
        if rename, let d = data, !s.companies[i].name.hasPrefix(ch["name"].string) {
            s.companies[i].name = storeName(s, chain: ch, s.companies[i], data: d)
        }
        applyRules(&s, chain: ch, companyIndex: i)
        if let d = data, s.companies[i].status == .open {
            for (k, v) in ch["rules"]["knob"].object.sorted(by: { $0.key < $1.key }) where s.companies[i].value("knob")[k].int != v.int {
                if case .refused(let why) = KnobChange.apply(&s, d, companyID: companyID, knob: k, value: v.int, byChain: true) {
                    s.note("\(s.companies[i].name) joined \(ch["name"].string) but keeps its own way of selling: \(why)", tone: "warn", companyID: companyID)
                }
            }
        }
        if let d = data { SupplyDeals.applyChainRules(&s, d, storeID: companyID) }
    }

    public struct KnobStandardLine: Equatable, Sendable {
        public var storeID: Int
        public var storeName: String
        public var changes: Bool
        public var cost: Double
        public var weeks: Int
        public var reason: String?
    }

    public struct KnobStandardPlan: Equatable, Sendable {
        public var lines: [KnobStandardLine]
        public init(lines: [KnobStandardLine]) { self.lines = lines }
        public var totalCost: Double { lines.filter { $0.changes && $0.reason == nil }.reduce(0) { $0 + $1.cost } }
        public var exceptions: Int { lines.filter { $0.changes && $0.reason != nil }.count }
        public var changing: Int { lines.filter { $0.changes && $0.reason == nil }.count }
    }

    public static func knobStandardPlan(_ s: GameState, chainID: Int, knob: String, value: Int, data: GameData) -> KnobStandardPlan? {
        guard let ch = chain(s, id: chainID), data.catalog[ch["type"].string]?.knobs.contains(where: { $0.id == knob }) == true else { return nil }
        var lines: [KnobStandardLine] = []
        for c in stores(s, ch) {
            guard let q = KnobChange.quote(s, data, companyID: c.id, knob: knob, value: value, byChain: true) else { continue }
            let same = (c.value("knob")[knob].isNull ? (data.catalog[c.type]?.knobs.first { $0.id == knob }?.defaultIndex ?? 0) : c.value("knob")[knob].int) == value
            lines.append(KnobStandardLine(storeID: c.id, storeName: c.name, changes: !same, cost: q.totalCost, weeks: q.transitionWeeks, reason: same ? nil : q.blocked))
        }
        return KnobStandardPlan(lines: lines)
    }

    @discardableResult
    public static func setKnobStandard(_ s: inout GameState, chainID: Int, knob: String, value: Int, data: GameData) -> KnobStandardPlan {
        guard var ch = chain(s, id: chainID), let plan0 = knobStandardPlan(s, chainID: chainID, knob: knob, value: value, data: data) else { return KnobStandardPlan(lines: []) }
        ch["rules"]["knob"][knob] = .number(Double(value))
        save(&s, ch)
        var lines = plan0.lines
        for n in lines.indices where lines[n].changes {
            let id = lines[n].storeID
            guard let i = s.companyIndex(id) else { continue }
            if s.companies[i].status != .open {
                var k = s.companies[i].value("knob"); k[knob] = .number(Double(value)); s.companies[i].set("knob", k)
                lines[n].reason = nil
                continue
            }
            if case .refused(let why) = KnobChange.apply(&s, data, companyID: id, knob: knob, value: value, byChain: true) {
                lines[n].reason = why
                s.note("\(lines[n].storeName) keeps its way of selling: \(why)", tone: "warn", companyID: id)
            } else { lines[n].reason = nil }
        }
        return KnobStandardPlan(lines: lines)
    }

    public static func knobStandard(_ s: GameState, chainID: Int, knob: String) -> Int? {
        guard let ch = chain(s, id: chainID), !ch["rules"]["knob"][knob].isNull else { return nil }
        return ch["rules"]["knob"][knob].int
    }

    public static func knobExceptions(_ s: GameState, chainID: Int, knob: String, data: GameData) -> [(storeID: Int, storeName: String, value: Int)] {
        guard let std = knobStandard(s, chainID: chainID, knob: knob), let ch = chain(s, id: chainID),
              let k = data.catalog[ch["type"].string]?.knobs.first(where: { $0.id == knob }) else { return [] }
        return stores(s, ch).compactMap { c in
            let v = KnobChange.currentValue(c, k)
            return v == std ? nil : (storeID: c.id, storeName: c.name, value: v)
        }
    }

    public static func releaseKnobStandard(_ s: inout GameState, chainID: Int, knob: String) {
        guard var ch = chain(s, id: chainID) else { return }
        var k = ch["rules"]["knob"].object
        k.removeValue(forKey: knob)
        ch["rules"]["knob"] = .object(k)
        save(&s, ch)
    }

    public struct Shortage: Equatable, Sendable { public var storeID: Int; public var role: String; public var spareAtStoreID: Int? }

    public static func staffShortages(_ s: GameState, chainID: Int, data: GameData) -> [Shortage] {
        guard let ch = chain(s, id: chainID) else { return [] }
        let chainStores = stores(s, ch)
        func std(_ c: Company, _ role: String) -> Int {
            guard let bd = data.catalog[c.type] else { return 0 }
            return CompanySetup.standardStaff(bd, size: c.size).filter { $0.role == role }.reduce(0) { $0 + $1.count }
        }
        func have(_ c: Company, _ role: String) -> Int { c.staff.filter { $0.role == role }.count }
        var out: [Shortage] = []
        for c in chainStores {
            guard let bd = data.catalog[c.type] else { continue }
            for r in CompanySetup.standardStaff(bd, size: c.size) where have(c, r.role) < r.count {
                out.append(Shortage(storeID: c.id, role: r.role, spareAtStoreID: chainStores.first { $0.id != c.id && have($0, r.role) > std($0, r.role) }?.id))
            }
        }
        return out
    }

    @discardableResult
    public static func lendWorker(_ s: inout GameState, from fromID: Int, to toID: Int, role: String, staffID: Int? = nil, data: GameData) -> Bool {
        guard let a = s.companyIndex(fromID), let b = s.companyIndex(toID), a != b,
              let ca = chain(s, of: s.companies[a]), let cb = chain(s, of: s.companies[b]), ca["id"].int == cb["id"].int else { return false }
        let tables = data.catalog.tables
        let pick = s.companies[a].staff.filter { staffID == nil ? $0.role == role : $0.id == staffID }
            .min { StaffModel.skill($0, person: s.people[$0.id], salesRoles: tables.salesRoles) < StaffModel.skill($1, person: s.people[$1.id], salesRoles: tables.salesRoles) }
        guard let m = pick else { return false }
        s.companies[a].staff = s.companies[a].staff.filter { $0.id != m.id }
        s.companies[b].staff = s.companies[b].staff + [m]
        if var p = s.people[m.id] { p.employerID = toID; s.people[m.id] = p }
        s.note("\(s.people[m.id]?.name ?? "A worker") moves to \(s.companies[b].name).", companyID: toID)
        return true
    }

    public struct StoreStandards: Equatable, Sendable {
        public var priceLow: Double
        public var priceHigh: Double
        public var headcountFloor: Int
        public var ordering: Int
        public init(priceLow: Double, priceHigh: Double, headcountFloor: Int, ordering: Int) {
            self.priceLow = priceLow; self.priceHigh = priceHigh; self.headcountFloor = headcountFloor; self.ordering = ordering
        }
        public func price(_ wanted: Double) -> Double { min(priceHigh, max(priceLow, wanted)) }
    }

    public static func chainStandards(_ s: GameState, chainID: Int) -> StoreStandards? {
        guard let ch = chain(s, id: chainID) else { return nil }
        return standards(of: ch)
    }
    public static func chainStandards(_ s: GameState, of co: Company) -> StoreStandards? { chain(s, of: co).map { standards(of: $0) } }

    static func standards(of ch: JSONValue) -> StoreStandards {
        let st = ch["std"]
        let lo = st["lo"].isNull ? -3 : clamp(st["lo"].double, -3, 3), hi = st["hi"].isNull ? 3 : clamp(st["hi"].double, -3, 3)
        return StoreStandards(priceLow: min(lo, hi), priceHigh: max(lo, hi), headcountFloor: max(0, st["floor"].int),
                              ordering: ch["rules"]["stockPol"].isNull ? 1 : min(2, max(0, ch["rules"]["stockPol"].int)))
    }

    public static func setStandards(_ s: inout GameState, chainID: Int, priceLow: Double? = nil, priceHigh: Double? = nil, headcountFloor: Int? = nil, ordering: Int? = nil) {
        guard var ch = chain(s, id: chainID) else { return }
        var st = ch["std"].isNull ? JSONValue.object([:]) : ch["std"]
        if let v = priceLow { st["lo"] = .number(clamp(v, -3, 3)) }
        if let v = priceHigh { st["hi"] = .number(clamp(v, -3, 3)) }
        if let v = headcountFloor { st["floor"] = .number(Double(max(0, v))) }
        ch["std"] = st
        save(&s, ch)
        if let o = ordering { setRule(&s, chainID: chainID, rule: .stockPolicy(o)) } else { applyAll(&s, chain: ch) }
    }

    static func applyRules(_ s: inout GameState, chain ch: JSONValue, companyIndex i: Int) {
        let R = ch["rules"], o = s.companies[i].value("off")
        s.companies[i].priceLevel = clamp(R["price"].double + standards(of: ch).price(o["price"].double), -3, 3)
        if s.companies[i].status != .open {
            var knob = s.companies[i].value("knob")
            for (k, v) in R["knob"].object { knob[k] = v }
            s.companies[i].set("knob", knob)
        }
        s.companies[i].set("stockPol", o["stock"].isNull ? R["stockPol"].double : o["stock"].double)
    }

    static func applyAll(_ s: inout GameState, chain ch: JSONValue) {
        for c in stores(s, ch) { if let i = s.companyIndex(c.id) { applyRules(&s, chain: ch, companyIndex: i) } }
    }

    public enum Rule: Equatable, Sendable { case price(Double), knob(id: String, option: Int), stockPolicy(Int), pay(Double), marketing(String) }

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

    public static func newStoreCost(_ s: GameState, chainID: Int, cityID: String, size: Double, data: GameData) -> Double? {
        guard let ch = chain(s, id: chainID), let first = stores(s, ch).first,
              let est = CompanySetup.estimate(tradeID: ch["type"].string, cityID: cityID, size: size, countryCode: first.countryCode, state: s, data: data) else { return nil }
        return (est.total * 1.15 / 1000).rounded() * 1000
    }

    public static func openStore(_ s: inout GameState, chainID: Int, cityID: String, size: Double, data: GameData, context fc: FinanceContext) -> Result<Int, CompanySetup.StartError> {
        guard let ch = chain(s, id: chainID), let first = stores(s, ch).first, let cost = newStoreCost(s, chainID: chainID, cityID: cityID, size: size, data: data) else { return .failure(.notAllowedHere) }
        if Payments.liquid(s) < cost { return .failure(.notEnoughCash) }
        let r = CompanySetup.create(&s, tradeID: ch["type"].string, cityID: cityID, size: size, name: "New store \(s.nextID + 1)", countryCode: first.countryCode, data: data, context: fc)
        guard case .success(let id) = r, let i = s.companyIndex(id) else { return r }
        var docs = s.companies[i].value("docs")
        for (k, d) in first.value("docs").object where d["st"].string == "ok" && k != "chain" && docs[k].isNull { docs[k] = d }
        s.companies[i].set("docs", docs)
        s.companies[i].ownerHours = 0
        _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        join(&s, chainID: chainID, companyID: id, rename: true, data: data)
        if let k = s.companyIndex(id) {
            s.companies[k].awareness = max(s.companies[k].awareness, BrandValues.openingAwareness(flagshipAwareness: first.awareness, score: BrandValues.company(s, first).score))
        }
        if let k = s.companyIndex(id) { s.companies[k].set("open13", s.week + 3) }
        s.note("\(s.company(id)?.name ?? "A new store") is being set up for \(ch["name"].string).", tone: "good", companyID: id)
        return .success(id)
    }

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

    public static func looseGroups(_ s: GameState, data: GameData) -> [LooseGroup] {
        var by: [String: [Company]] = [:]
        for c in s.companies where c.status.isLive && c.value("chain").isNull { by["\(c.type)|\(c.countryCode)|\(baseName(c, data: data))", default: []].append(c) }
        return by.keys.sorted().compactMap { k in
            guard let L = by[k], L.count >= 2 else { return nil }
            let nm = L.sorted { $0.name.count < $1.name.count }[0].name
            return LooseGroup(id: k, name: nm, tradeID: L[0].type, companyIDs: L.map { $0.id })
        }
    }

    public struct Reach: Equatable, Sendable {
        public var outlets: Int
        public var countries: Int
        public var label: String
        public var awarenessCap: Double
        public var nextAt: Int
        public var demandFactor: Double
        public var rebate: Double
    }

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

    static func rebate(_ s: inout GameState, _ id: Int, _ amount: Double) {
        let a = amount.rounded()
        if a <= 0 { return }
        Payments.companyReceives(&s, companyID: id, amount: a, category: nil, label: nil)
        Payments.book(&s, companyID: id, category: "cogs", amount: -a)
    }

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
                    let ks = marketing.channels.keys.filter { k in let c = marketing.channels[k]!; return !c.isPrimeTime && !c.isNational && !c.isHighVariance && FranchiseStandards.campaignRefusal(co, channel: k) == nil }
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
            var byCity: [String: Double] = [:]
            for c in stores(s, ch) { byCity[c.cityID] = max(byCity[c.cityID] ?? 0, c.awareness) }
            for c in stores(s, ch) { if let i = s.companyIndex(c.id) { s.companies[i].awareness = max(s.companies[i].awareness, (byCity[c.cityID] ?? 0) * 0.85) } }
            if GameCalendar.isMonthEnd(week: s.week) { chainPay(&s, ch, data: data) }
        }
    }

    static func chainPay(_ s: inout GameState, _ ch: JSONValue, data: GameData) {
        for c in stores(s, ch) {
            guard let i = s.companyIndex(c.id), let country = data.countries[c.countryCode], let city = country.city(c.cityID) ?? country.cities.first else { continue }
            let rates = ExchangeRates(drift: s.exchangeRates.values)
            var staff = s.companies[i].staff
            var changed = false
            for k in staff.indices {
                guard let base = data.catalog.tables.roles[staff[k].role]?.baseMonthlyWage, let person = s.people[staff[k].id] else { continue }
                let market = Wages.market(baseMonthlyWage: base, country: country, city: city, economy: s.economy, rates: rates)
                let tgt = market * staff[k].partTimeShare * (0.7 + person.skill / 160) * (1 + ch["rules"]["pay"].double + c.value("off")["pay"].double)
                if staff[k].monthlyWage < tgt * 0.97 { staff[k].monthlyWage = (tgt / 100).rounded() * 100; changed = true }
            }
            if changed { s.companies[i].staff = staff }
        }
    }

    static func reachWeek(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices {
            let co = s.companies[i]
            guard co.status == .open, co.type != "club" else { continue }
            let lw = co.value("lastW")
            if co.type == "cardealer", lw["rev"].double > 0, let pl = s.companies.first(where: { $0.type == "factory" && $0.status == .open && $0.id != co.id && $0.countryCode == co.countryCode && $0.value("knob")["line"].int >= 1 }) {
                let rev = lw["rev"].double
                let discount = min(rev * 0.06, lw["cogs"].double * 0.12).rounded()
                rebate(&s, co.id, discount)
                if discount > 0 { Payments.companyReceives(&s, companyID: pl.id, amount: discount, category: "rev", label: "Wholesale to \(co.name)") }
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

    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext, marketing: MarketingTables) {
        chainsWeek(&s, data: data, marketing: marketing)
        reachWeek(&s, data: data)
        Franchising.weekly(&s, data: data, context: fc)
        IntercompanySupply.weekly(&s, data: data)
        SupplyTerms.weekly(&s, data: data, context: fc)
        AccountSupply.weekly(&s)
        ManagerModel.groupWeekly(&s, data: data, context: fc, marketing: marketing)
    }
}
