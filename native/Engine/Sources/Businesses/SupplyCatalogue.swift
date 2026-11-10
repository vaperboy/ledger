import Foundation
import GameCore
import Countries
import Finance

/// What a trade buys from suppliers, and how the choice of supplier reaches its books. The lists come from `Resources/supply_catalogue.json`
/// (one list per trade family, adjusted per trade; a trade that buys nothing, such as a holding company, has an empty list).
///
/// Rules, all small:
///  - A cost-of-sales line (stock, ingredients, materials, packaging) is a share of the week's cost of sales, so it follows sales. An overhead
///    line (cleaning, laundry, power, software, upkeep) is a share of the weekly fixed overhead; lines marked variable follow how busy the place is.
///  - Each line can be bought from the market (list price, the way every company bought before) or from one of up to three named suppliers: a
///    basic, a solid and a premium one. Price tier trades cost against quality: the quality of what is bought moves the company's quality target
///    a little, and premium suppliers are more reliable.
///  - A named supplier who misses a delivery on a line the trade cannot sell without (stock, materials) cuts that week's customers served.
///  - Payment terms: a named supplier of an overhead line is paid on delivery (basic) or on invoice (the rest). What is invoiced is booked as
///    an expense and owed as a payable until the month-end bills. The market is paid as before.
///  - Stock and repair lines use the existing goods and repair suppliers; kinds your own companies can supply use that existing switch.
public enum SupplyCatalogue {
    // MARK: Data

    public struct Line: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        /// What kind of purchase it is in general words ("Linen and laundry"), the same in every trade.
        public var kind: String
        public var group: String
        /// "cogs" (cost of sales) or "oth" (overheads).
        public var category: String
        /// The share of the cost of sales (cogs line) or of the weekly fixed overhead (overhead line) this line stands for.
        public var share: Double
        /// The id of an existing supplier switch ("goods", "repair", or a kind your own companies can supply).
        public var input: String?
        public var leadDays: Int
        public var termsDays: Int
        public var critical: Bool
        public var variable: Bool
        /// False when there is nothing to choose between outside suppliers (the price comes from your own companies or the project).
        public var tiers: Bool
        public var automatic: Bool
        public var isCogs: Bool { category == "cogs" }
    }

    struct Template { var name: String; var group: String; var category: String; var input: String?; var lead: Int; var terms: Int; var critical: Bool; var variable: Bool; var tiers: Bool; var automatic: Bool }
    struct Catalogue {
        var groups: [String] = []
        var templates: [String: Template] = [:]
        var families: [String: [(id: String, share: Double, name: String)]] = [:]
        var trades: [String: (drop: [String], set: [String: (share: Double?, name: String?)], add: [(id: String, share: Double, name: String)])] = [:]
    }

    static let catalogue: Catalogue = {
        var c = Catalogue()
        guard let url = Bundle.module.url(forResource: "supply_catalogue", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return c }
        c.groups = j["groups"].array.map { $0.string }
        for (k, v) in j["lines"].object {
            c.templates[k] = Template(name: v["name"].string, group: v["group"].string, category: v["category"].string, input: v["input"].isNull ? nil : v["input"].string,
                                      lead: v["lead"].int, terms: v["terms"].int, critical: v["critical"].bool, variable: v["variable"].bool, tiers: v["tiers"].isNull ? true : v["tiers"].bool, automatic: v["auto"].bool)
        }
        func entry(_ e: JSONValue) -> (id: String, share: Double, name: String) { (e.array[0].string, e.array[1].double, e.array[2].string) }
        for (k, v) in j["families"].object { c.families[k] = v.array.map(entry) }
        for (k, v) in j["trades"].object {
            var set: [String: (share: Double?, name: String?)] = [:]
            for (id, a) in v["set"].object { set[id] = (a.array[0].isNull ? nil : a.array[0].double, a.array[1].isNull ? nil : a.array[1].string) }
            c.trades[k] = (v["drop"].array.map { $0.string }, set, v["add"].array.map(entry))
        }
        return c
    }()

    /// The groups in the order they are shown.
    public static var groups: [String] { catalogue.groups }

    /// Trades whose week is worked out by their own model: only the overhead lines can change their books.
    static func ownCostModel(_ bd: Trade) -> Bool {
        ["usedcar", "cardealer", "salmon", "startup", "travel", "insbroker", "finbroker"].contains(bd.id) || !["venue", "retail", "prod", "logi", "svc"].contains(bd.family)
    }

    /// What this company buys, in the order of the catalogue. Empty for a trade that buys nothing.
    public static func lines(_ co: Company, _ bd: Trade) -> [Line] {
        let c = catalogue
        var entries = c.families[bd.family] ?? []
        if let o = c.trades[bd.id] {
            entries = entries.filter { !o.drop.contains($0.id) }
            entries = entries.map { e in
                guard let x = o.set[e.id] else { return e }
                return (e.id, x.share ?? e.share, x.name ?? e.name)
            }
            for a in o.add { entries.removeAll { $0.id == a.id }; entries.append(a) }
        }
        let hasGoods = Suppliers.hasGoods(bd, co)
        var out: [Line] = []
        for e in entries {
            guard let t = c.templates[e.id] else { continue }
            if t.category == "cogs" {
                if e.id == "goods" { guard hasGoods else { continue } }
                else { guard bd.costOfSales >= 0.03, !ownCostModel(bd) else { continue } }
            }
            out.append(Line(id: e.id, name: e.name, kind: t.name, group: t.group, category: t.category, share: e.share, input: t.input, leadDays: t.lead, termsDays: t.terms,
                            critical: t.critical, variable: t.variable, tiers: t.tiers, automatic: t.automatic))
        }
        // Stock takes what the other cost-of-sales lines leave.
        let others = out.filter { $0.isCogs && $0.id != "goods" }.reduce(0) { $0 + $1.share }
        if let g = out.firstIndex(where: { $0.id == "goods" }) { out[g].share = max(0.3, 1 - others) }
        return out
    }

    // MARK: Offers

    public struct Offer: Identifiable, Equatable, Sendable {
        /// "market" or the supplier id.
        public var id: String
        public var name: String
        public var owner: String
        /// 0 basic, 1 solid, 2 premium; 1 for the market.
        public var tier: Int
        public var priceFactor: Double
        /// Share of deliveries that arrive when they should.
        public var reliability: Double
        public var termsDays: Int
        public var leadDays: Int
        public var relationshipWord: String?
        public var isMarket: Bool { id == "market" }
    }

    static let tierPrice: [Double] = [0.90, 1.0, 1.14]
    /// Points of the company's quality target per share of spend: basic below, premium above.
    static let tierQuality: [Double] = [-4, 0, 4]
    static let tierReliability: [Double] = [0.89, 0.95, 0.985]
    static let qualityWords = ["Basic", "Solid", "Top grade"]

    public static func qualityWord(tier: Int) -> String { qualityWords[min(2, max(0, tier))] }
    public static func reliabilityWord(_ r: Double) -> String { r < 0.9 ? "Patchy" : r < 0.96 ? "Steady" : "Dependable" }

    /// The market plus up to three named suppliers of the line, cheapest and weakest first. Nothing named for a line with nothing to choose.
    public static func offers(_ s: GameState, _ co: Company, _ bd: Trade, line: Line, data: GameData) -> [Offer] {
        var out = [Offer(id: "market", name: "Market supplier", owner: "", tier: 1, priceFactor: 1, reliability: 0.97, termsDays: 0, leadDays: line.leadDays, relationshipWord: nil)]
        guard line.tiers, !line.automatic, line.input != "goods", line.input != "repair" else { return out }
        let vs = EquipmentMarket.vendors(for: "line:\(co.type):\(line.id)", count: 3, family: bd.family, seed: s.seed, countryCode: co.countryCode,
                                         countries: data.countries, nouns: Suppliers.nouns(data)).sorted { $0.quality < $1.quality }
        let tiers: [[Int]] = [[], [1], [0, 2], [0, 1, 2]]
        for (n, v) in vs.enumerated() {
            let t = tiers[vs.count][n]
            let made = Suppliers.make(v, scope: "line", s)
            let rel = min(0.995, max(0.85, tierReliability[t] + v.quality * 0.03))
            out.append(Offer(id: v.id, name: v.name, owner: v.owner, tier: t, priceFactor: tierPrice[t] * (1 - made.discount), reliability: rel,
                             termsDays: [0, line.termsDays, line.termsDays * 2][t], leadDays: line.leadDays + (t == 0 ? 1 : 0), relationshipWord: made.relationshipWord))
        }
        // A player supplier under contract prices, rates and pays like the named ones.
        if let c = PlayerSupply.contract(s, buyer: co.id, line: line.id) { out.append(PlayerSupply.offer(c, line: line)) }
        return out
    }

    /// The supplier chosen for a line ("market" when none).
    public static func chosenID(_ co: Company, line: String) -> String {
        let v = co.value("sc")[line]
        return v.isNull ? "market" : v.string
    }

    /// The offer in force for a line, found among its offers (the market if the chosen one is gone).
    public static func current(_ s: GameState, _ co: Company, _ bd: Trade, line: Line, data: GameData) -> Offer {
        let all = offers(s, co, bd, line: line, data: data)
        let id = chosenID(co, line: line.id)
        return all.first { $0.id == id } ?? all[0]
    }

    /// Whether a line's price and quality come from the catalogue's offers (and so reach the books). Stock and repairs use their own switch;
    /// a kind one of your own companies supplies uses the saving of that supply.
    static func folded(_ s: GameState, _ co: Company, _ line: Line) -> Bool {
        guard line.tiers, !line.automatic, line.input != "goods", line.input != "repair" else { return false }
        if let k = line.input, IntercompanySupply.link(s, buyer: co.id, kind: k) != nil || AccountSupply.link(s, buyer: co.id, kind: k) != nil { return false }
        return true
    }

    /// Choose the supplier of a catalogue line ("market" or a supplier id). False when the line cannot be chosen this way.
    @discardableResult
    public static func choose(_ s: inout GameState, companyID: Int, line id: String, offer: String, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type],
              let line = lines(s.companies[i], bd).first(where: { $0.id == id }), folded(s, s.companies[i], line),
              offers(s, s.companies[i], bd, line: line, data: data).contains(where: { $0.id == offer }) else { return false }
        var sc = s.companies[i].value("sc"); if sc.isNull { sc = .object([:]) }
        var o = sc.object
        if offer == "market" { o.removeValue(forKey: id) } else { o[id] = .string(offer) }
        sc = .object(o)
        s.companies[i].set("sc", sc)
        return true
    }

    // MARK: Effects on the books

    /// What the chosen suppliers do to the cost of sales (a multiplier on top of the stock supplier's) and to the company's quality target.
    public static func cogsEffect(_ s: GameState, _ co: Company, _ bd: Trade, data: GameData) -> (m: Double, q: Double) {
        var m = 1.0, q = 0.0
        for line in lines(co, bd) where folded(s, co, line) {
            let o = current(s, co, bd, line: line, data: data)
            let w = line.isCogs ? line.share : line.share * 0.5
            if line.isCogs { m += line.share * (o.priceFactor - 1) }
            q += w * tierQuality[o.tier]
        }
        return (m, q)
    }

    /// How busy the place is moves its variable overheads: 1 at a 60 % load, 15 % less when empty, 20 % more when full.
    static func activity(_ line: Line, util: Double) -> Double {
        line.variable ? min(1.2, max(0.85, 1 + 0.3 * (util / 0.6 - 1))) : 1
    }

    /// The share of the week's customers the stock suppliers delivered for: a named supplier misses some deliveries, and a miss on a line the
    /// trade cannot sell without costs that week's sales. Only suppliers the owner chose can miss. Same answer for the same company and week.
    public static func availability(_ s: GameState, _ co: Company, _ bd: Trade, week: Int, data: GameData) -> Double {
        var f = 1.0
        for line in lines(co, bd) where line.critical {
            // A player supplier misses exactly when the market reports a short delivery.
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

    /// Whether a delivery was missed in the last four weeks on this line.
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

    /// The reliability of the supplier the owner chose for a critical line; nil when none was chosen (the market never misses).
    static func reliability(_ s: GameState, _ co: Company, _ bd: Trade, line: Line, data: GameData) -> Double? {
        if let c = PlayerSupply.contract(s, buyer: co.id, line: line.id) { return c.reliability }
        if line.input == "goods" {
            let src = co.value("src")["v"]
            guard !src.isNull, src.string != "auto", let v = Suppliers.vendor(s, id: src.string, data: data) else { return nil }
            return 0.85 + (v.rating - 2.6) / 2.2 * 0.14
        }
        guard folded(s, co, line) else { return nil }
        let o = current(s, co, bd, line: line, data: data)
        return o.isMarket ? nil : o.reliability
    }

    /// Pays the week's fixed overhead with the chosen suppliers' prices and terms, records what each line cost, and returns the net amount
    /// (for the input VAT). `base` is the overhead before the catalogue. With nothing chosen and a place at a 60 % load this pays exactly `base`.
    static func settleOverhead(_ s: inout GameState, _ i: Int, _ bd: Trade, base: Double, util: Double, data: GameData) -> Double {
        let co = s.companies[i]
        let all = lines(co, bd)
        var share = 0.0, immediate = 0.0, invoiced = 0.0
        var spend: [String: Double] = [:]
        var bought: [(vendor: String, amount: Double)] = []
        for line in all where !line.isCogs {
            let folded = folded(s, co, line)
            let o = folded ? current(s, co, bd, line: line, data: data) : nil
            // Electricity is bought at the global market price, whoever the supplier is.
            let part = base * line.share * (o?.priceFactor ?? 1) * activity(line, util: util) * (line.id == "power" ? EnergyMarket.costFactor(s) : 1)
            share += line.share
            spend[line.id] = part
            guard let o, !o.isMarket else { continue }
            if !o.id.hasPrefix("P:") { bought.append((o.id, part)) }
            if o.termsDays == 0 { immediate += part } else { invoiced += part }
        }
        // What the catalogue does not name goes on as before; the named lines' own factor and load are in `spend`.
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
        // Cost-of-sales lines: this week's cost of sales shared by weight.
        let cogsWeek = s.companies[i].value("lastW")["cogs"].double
        let cl = all.filter { $0.isCogs }
        let weights: [String: Double] = Dictionary(uniqueKeysWithValues: cl.map { l in
            (l.id, l.share * (folded(s, co, l) ? current(s, co, bd, line: l, data: data).priceFactor : 1))
        })
        let wsum = weights.values.reduce(0, +)
        if wsum > 0 { for l in cl { spend[l.id] = cogsWeek * (weights[l.id] ?? 0) / wsum; if let o = folded(s, co, l) ? current(s, co, bd, line: l, data: data) : nil, !o.isMarket, !o.id.hasPrefix("P:") { bought.append((o.id, spend[l.id] ?? 0)) } } }
        let rec = s.companies[i].value("scw")
        var next: [String: JSONValue] = [:]
        for (k, v) in spend { next[k] = .array([.number(v), .number(rec[k].array.first?.double ?? v)]) }
        s.companies[i].set("scw", .object(next))
        let index = data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode).costIndex
        for b in bought where b.amount > 0 { Suppliers.recordPurchase(&s, vendorID: b.vendor, amount: b.amount, priceIndex: index) }
        return total
    }

    /// What one line cost this week and the week before (in the company's currency); nil until the first week has been booked.
    public static func weeklySpend(_ co: Company, line: String) -> (now: Double, before: Double)? {
        let v = co.value("scw")[line].array
        guard v.count == 2 else { return nil }
        return (v[0].double, v[1].double)
    }
}
