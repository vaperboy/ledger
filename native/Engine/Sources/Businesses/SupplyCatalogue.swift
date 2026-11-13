import Foundation
import GameCore
import Countries
import Finance

public enum SupplyCatalogue {

    public struct Line: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        public var group: String
        public var category: String
        public var share: Double
        public var input: String?
        public var leadDays: Int
        public var termsDays: Int
        public var critical: Bool
        public var variable: Bool
        public var tiers: Bool
        public var automatic: Bool
        public var isStock: Bool = false
        public var isCogs: Bool { category == "cogs" }
    }

    public static var groups: [String] { SupplyMap.groups }

    static func ownCostModel(_ bd: Trade) -> Bool {
        ["usedcar", "cardealer", "salmon", "startup", "travel", "insbroker", "finbroker", "wholesale"].contains(bd.id) || !["venue", "retail", "prod", "logi", "svc"].contains(bd.family)
    }

    // What the role of a line is for this company: stock (goods), equipment upkeep (repair), an own-company supply kind, or none.
    static func input(_ need: SupplyMap.Need, _ spec: SupplyMap.LineSpec, _ co: Company, _ bd: Trade) -> String? {
        if need.isStock && Suppliers.hasGoods(bd, co) { return "goods" }
        if !bd.equipment.isEmpty, need.line == Suppliers.upkeepLine(bd) { return "repair" }
        if !spec.automatic, need.salesShare != nil, IntercompanySupply.kind(need.line) != nil { return need.line }
        return nil
    }

    public static func lines(_ co: Company, _ bd: Trade) -> [Line] {
        let hasGoods = Suppliers.hasGoods(bd, co)
        var out: [Line] = []
        for n in SupplyMap.needs(bd.id) {
            guard let share = n.costShare, let spec = SupplyMap.line(n.line) else { continue }
            let category = n.category ?? spec.category
            if category == "cogs" {
                if n.isStock { guard hasGoods || (bd.costOfSales >= 0.03 && !ownCostModel(bd)) else { continue } }
                else { guard bd.costOfSales >= 0.03, !ownCostModel(bd) else { continue } }
            }
            out.append(Line(id: n.line, name: n.label ?? spec.name, kind: spec.name, group: spec.group, category: category, share: share, input: input(n, spec, co, bd),
                            leadDays: spec.lead, termsDays: spec.terms, critical: spec.critical, variable: spec.variable, tiers: !spec.automatic,
                            automatic: spec.automatic, isStock: n.isStock))
        }
        let others = out.filter { $0.isCogs && !$0.isStock }.reduce(0) { $0 + $1.share }
        if let g = out.firstIndex(where: { $0.isStock && $0.isCogs && $0.share == 0 }) { out[g].share = max(0.3, 1 - others) }
        return out
    }

    public static func stockLine(_ co: Company, _ bd: Trade) -> Line? { lines(co, bd).first { $0.isStock } }

    public struct Offer: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var owner: String
        public var tier: Int
        public var priceFactor: Double
        public var reliability: Double
        public var termsDays: Int
        public var leadDays: Int
        public var relationshipWord: String?
        public var tradeID: String = ""
        public var ownerCode: String = ""
        public var city: String = ""
        public var logoID: String = ""
        public var quality: Double = 0
        public var capacityFactor: Double = 4
        public var load: Double = 0.3
        public var staff: Int = 0
        public var weeksTrading: Int = 0
        public var isStandard: Bool = false
    }

    static let tierPrice: [Double] = [0.90, 1.0, 1.14]
    static let tierQuality: [Double] = [-4, 0, 4]
    static let qualityWords = ["Basic", "Solid", "Top grade"]

    public static func qualityWord(tier: Int) -> String { qualityWords[min(2, max(0, tier))] }
    public static func reliabilityWord(_ r: Double) -> String { r < 0.9 ? "Patchy" : r < 0.96 ? "Steady" : "Dependable" }

    static func offer(_ p: SupplyPlayers.Supplier, line: Line, _ s: GameState) -> Offer {
        let r = Suppliers.relationship(s, p.id)
        let disc = Suppliers.relationshipDiscount(r)
        return Offer(id: p.id, name: p.name, owner: p.owner, tier: p.tier, priceFactor: tierPrice[min(2, max(0, p.tier))] * (1 - disc), reliability: p.reliability,
                     termsDays: [0, line.termsDays, line.termsDays * 2][min(2, max(0, p.tier))], leadDays: line.leadDays + (p.tier == 0 ? 1 : 0),
                     relationshipWord: Suppliers.relationshipWord(r), tradeID: p.tradeID, ownerCode: p.ownerCode, city: p.city, logoID: p.logoID, quality: p.quality,
                     capacityFactor: p.capacityFactor, load: p.load, staff: p.staff, weeksTrading: p.weeksTrading, isStandard: p.isStandard)
    }

    // The player companies that supply this line: the standard one first, then the others, then a signed player contract.
    public static func offers(_ s: GameState, _ co: Company, _ bd: Trade, line: Line, data: GameData) -> [Offer] {
        guard !line.automatic else { return [] }
        var out = Suppliers.lineSuppliers(s, company: co, line: line.id, data: data).map { offer($0, line: line, s) }
        if let c = PlayerSupply.contract(s, buyer: co.id, line: line.id) { out.append(PlayerSupply.offer(c, line: line)) }
        return out
    }

    public static func chosenID(_ co: Company, line: String) -> String? {
        let v = co.value("sc")[line]
        return v.isNull ? nil : v.string
    }

    public static func current(_ s: GameState, _ co: Company, _ bd: Trade, line: Line, data: GameData) -> Offer? {
        let all = offers(s, co, bd, line: line, data: data)
        if let id = chosenID(co, line: line.id), let o = all.first(where: { $0.id == id }) { return o }
        return all.first
    }

    // Lines whose supplier is picked here (stock and upkeep follow their own supplier rules; own-company links override).
    static func folded(_ s: GameState, _ co: Company, _ line: Line) -> Bool {
        guard line.tiers, !line.automatic, line.input != "goods", line.input != "repair" else { return false }
        if let k = line.input, IntercompanySupply.link(s, buyer: co.id, kind: k) != nil || AccountSupply.link(s, buyer: co.id, kind: k) != nil { return false }
        return true
    }

    @discardableResult
    public static func choose(_ s: inout GameState, companyID: Int, line id: String, offer: String?, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type],
              let line = lines(s.companies[i], bd).first(where: { $0.id == id }), line.tiers, !line.automatic else { return false }
        let all = offers(s, s.companies[i], bd, line: line, data: data)
        var o = s.companies[i].value("sc").object
        if let offer, let picked = all.first(where: { $0.id == offer }), !picked.isStandard { o[id] = .string(picked.id) }
        else if offer == nil || all.contains(where: { $0.id == offer && $0.isStandard }) { o.removeValue(forKey: id) }
        else { return false }
        s.companies[i].set("sc", .object(o))
        return true
    }

    public static func cogsEffect(_ s: GameState, _ co: Company, _ bd: Trade, data: GameData) -> (m: Double, q: Double) {
        var m = 1.0, q = 0.0
        for line in lines(co, bd) where folded(s, co, line) {
            guard let o = current(s, co, bd, line: line, data: data) else { continue }
            let w = line.isCogs ? line.share : line.share * 0.5
            if line.isCogs { m += line.share * (o.priceFactor - 1) }
            q += w * tierQuality[min(2, max(0, o.tier))]
        }
        return (m, q)
    }

    static func activity(_ line: Line, util: Double) -> Double {
        line.variable ? min(1.2, max(0.85, 1 + 0.3 * (util / 0.6 - 1))) : 1
    }

    public static func availability(_ s: GameState, _ co: Company, _ bd: Trade, week: Int, data: GameData) -> Double {
        var f = 1.0
        for line in lines(co, bd) where line.critical {
            if PlayerSupply.contract(s, buyer: co.id, line: line.id) != nil {
                if PlayerSupply.missed(s, buyer: co.id, line: line.id, week: week) { f *= line.share >= 0.5 ? 0.75 : 0.88 }
                continue
            }
            guard let rel = reliability(s, co, bd, line: line, data: data) else { continue }
            var r = HashedRandom("\(s.seed):short:\(co.id):\(line.id):\(week)")
            if r.next() < (1 - rel) * (0.6 + Double(line.leadDays) / 10) { f *= line.share >= 0.5 ? 0.75 : 0.88 }
        }
        return f
    }

    public static func missedRecently(_ s: GameState, _ co: Company, _ bd: Trade, line: Line, data: GameData) -> Bool {
        guard line.critical else { return false }
        if PlayerSupply.contract(s, buyer: co.id, line: line.id) != nil {
            return (0..<4).contains { n in PlayerSupply.missed(s, buyer: co.id, line: line.id, week: s.week - n) }
        }
        guard let rel = reliability(s, co, bd, line: line, data: data) else { return false }
        return (0..<4).contains { n in
            var r = HashedRandom("\(s.seed):short:\(co.id):\(line.id):\(s.week - 1 - n)")
            return r.next() < (1 - rel) * (0.6 + Double(line.leadDays) / 10)
        }
    }

    // How often a picked supplier falls short. The standard supplier of a line never misses, as the market did before.
    static func reliability(_ s: GameState, _ co: Company, _ bd: Trade, line: Line, data: GameData) -> Double? {
        if let c = PlayerSupply.contract(s, buyer: co.id, line: line.id) { return c.reliability }
        if line.input == "goods" {
            guard let v = Suppliers.goodsVendor(s, company: co, data: data), !v.isStandard else { return nil }
            return v.reliability
        }
        guard folded(s, co, line), let o = current(s, co, bd, line: line, data: data), !o.isStandard else { return nil }
        return o.reliability
    }

    static func settleOverhead(_ s: inout GameState, _ i: Int, _ bd: Trade, base: Double, util: Double, data: GameData) -> Double {
        let co = s.companies[i]
        let all = lines(co, bd)
        var share = 0.0, immediate = 0.0, invoiced = 0.0
        var spend: [String: Double] = [:]
        var bought: [(vendor: String, amount: Double)] = []
        for line in all where !line.isCogs {
            let o = folded(s, co, line) ? current(s, co, bd, line: line, data: data) : nil
            let part = base * line.share * (o?.priceFactor ?? 1) * activity(line, util: util) * (line.id == "power" ? EnergyMarket.costFactor(s) : 1)
            share += line.share
            spend[line.id] = part
            guard let o, !o.isStandard else { continue }
            if !o.id.hasPrefix("P:") { bought.append((o.id, part)) }
            if o.termsDays == 0 { immediate += part } else { invoiced += part }
        }
        let named = all.filter { !$0.isCogs }.reduce(0.0) { $0 + spend[$1.id, default: 0] }
        let total = base * max(0, 1 - share) + named
        let plain = total - immediate - invoiced
        if plain > 0 { Payments.companyPays(&s, companyID: co.id, amount: plain, category: "oth") }
        if immediate > 0 { Payments.companyPays(&s, companyID: co.id, amount: immediate, category: "oth", label: "Supplies paid on delivery") }
        if invoiced > 0 {
            let a = jsRound(invoiced)
            var c = s.companies[i]
            c.addPayable("other", a)
            var b = c.books; b.add("oth", a); c.books = b
            var f30 = c.value("f30"); f30["oth"] = .number(f30["oth"].double + a); c.set("f30", f30)
            s.companies[i] = c
        }
        let cogsWeek = s.companies[i].value("lastW")["cogs"].double
        let cl = all.filter { $0.isCogs }
        var picked: [String: Offer] = [:]
        for l in cl where folded(s, co, l) { if let o = current(s, co, bd, line: l, data: data) { picked[l.id] = o } }
        let weights: [String: Double] = Dictionary(uniqueKeysWithValues: cl.map { l in (l.id, l.share * (picked[l.id]?.priceFactor ?? 1)) })
        // Summed in line order: a dictionary's order changes between runs and would change the rounding.
        let wsum = cl.reduce(0.0) { $0 + (weights[$1.id] ?? 0) }
        if wsum > 0 {
            for l in cl {
                spend[l.id] = cogsWeek * (weights[l.id] ?? 0) / wsum
                if let o = picked[l.id], !o.isStandard, !o.id.hasPrefix("P:") { bought.append((o.id, spend[l.id] ?? 0)) }
            }
        }
        let rec = s.companies[i].value("scw")
        var next: [String: JSONValue] = [:]
        for (k, v) in spend { next[k] = .array([.number(v), .number(rec[k].array.first?.double ?? v)]) }
        s.companies[i].set("scw", .object(next))
        let index = data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode).costIndex
        for b in bought where b.amount > 0 { Suppliers.recordPurchase(&s, vendorID: b.vendor, amount: b.amount, priceIndex: index) }
        return total
    }

    public static func weeklySpend(_ co: Company, line: String) -> (now: Double, before: Double)? {
        let v = co.value("scw")[line].array
        guard v.count == 2 else { return nil }
        return (v[0].double, v[1].double)
    }

    // What a line needs a week, in supplier units, from last week's spend (or the share of sales when it has not run yet).
    public static func needUnits(_ co: Company, _ bd: Trade, line: String, costIndex: Double) -> Int {
        var weekly = weeklySpend(co, line: line)?.now ?? 0
        if weekly <= 0, let n = SupplyMap.need(bd.id, line: line), let share = n.salesShare { weekly = co.lastWeekRevenue * share }
        if weekly <= 0 { weekly = co.lastWeekRevenue * 0.02 }
        return SupplyNeed.units(weekly: weekly, costIndex: costIndex)
    }
}
