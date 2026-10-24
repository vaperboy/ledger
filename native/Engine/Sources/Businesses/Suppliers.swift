import Foundation
import GameCore
import Countries
import Finance

/// Suppliers you buy from: the person behind each supplier company, how well you know them, the discount that brings, board
/// agreements, and the choice of who supplies goods and repairs. Originals: `vendors`, `vpoolAll`, `vendorsFor`, `vrel`, `vbump`,
/// `vbuy`, `vmeet`, `vendMonth`, `vdisc`, `goodsPick`, `goodsEff`, `fixPick`, `fixDisc`, `boardDeal`, `buyerSkill`
/// (engine/suppliers/vendors.js), `vendRating` (reviews.js), the tab `CT.supply` and the actions `srcv`, `srcc`, `fixv`, `vmeet`,
/// `boarddeal` (ui/company/deals.js, ui/screens/group.js).
public enum Suppliers {
    static let words: [(below: Double, word: String)] = [(8, "Stranger"), (22, "Acquaintance"), (36, "Familiar"), (50, "Friendly"), (64, "Close"), (78, "Good friend"), (92, "Close friend"), (101, "Best friend")]
    static let discounts: [Double] = [0, 0, 0.01, 0.03, 0.05, 0.08, 0.12, 0.17]

    static func index(_ r: Double) -> Int { words.firstIndex { r < $0.below } ?? 7 }
    public static func relationshipWord(_ r: Double) -> String { words[index(r)].word }
    /// The discount a relationship brings on every order. Original: `relDisc`.
    public static func relationshipDiscount(_ r: Double) -> Double { discounts[index(r)] }
    public static let goodsClassNames = ["Basic", "Standard", "Premium"]

    public struct Vendor: Equatable, Sendable {
        public var id: String
        public var name: String
        public var owner: String
        public var quality: Double
        /// Stars. Original: `vendRating`.
        public var rating: Double
        public var relationship: Double
        public var relationshipWord: String
        /// Discount on every order: the relationship, plus 3 % if a board agreement names them for this scope.
        public var discount: Double
    }

    // MARK: Finding suppliers

    static func homeCurrency(_ s: GameState, _ data: GameData) -> Currency {
        Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
    }

    static func nouns(_ data: GameData) -> JSONValue { data.catalog.tables.raw["FAM_NOUN"] }

    static func make(_ v: EquipmentMarket.Vendor, scope: String, _ s: GameState) -> Vendor {
        let r = relationship(s, v.id)
        return Vendor(id: v.id, name: v.name, owner: v.owner, quality: v.quality, rating: jsRound(clamp(3.6 + v.quality * 2.2, 2.6, 4.8) * 10) / 10,
                      relationship: r, relationshipWord: relationshipWord(r), discount: discount(s, scope: scope, vendorID: v.id))
    }

    /// Who could supply this company with goods (scope "goods") or repairs ("fix"): a few of its country's suppliers for the trade. Original: `vendorsFor`.
    public static func candidates(_ s: GameState, company co: Company, scope: String, data: GameData) -> [Vendor] {
        guard let bd = data.catalog[co.type] else { return [] }
        let n = EquipmentMarket.brandCount(co, state: s)
        return EquipmentMarket.vendors(for: scope + ":" + co.type, count: n, family: bd.family, seed: s.seed, countryCode: co.countryCode,
                                       countries: data.countries, nouns: nouns(data)).map { make($0, scope: scope, s) }
    }

    /// A supplier by id ("V-UK-12"). Original: `vendById`.
    public static func vendor(_ s: GameState, id: String, scope: String = "goods", data: GameData) -> Vendor? {
        let p = id.split(separator: "-").map(String.init)
        guard p.count == 3, p[0] == "V", let i = Int(p[2]) else { return nil }
        let pool = EquipmentMarket.vendorPool(seed: s.seed, countryCode: p[1], countries: data.countries, nouns: nouns(data))
        return pool.indices.contains(i) ? make(pool[i].vendor, scope: scope, s) : nil
    }

    /// Suppliers you have dealt with, best known first. Original: `knownVendors`.
    public static func known(_ s: GameState, data: GameData) -> [Vendor] {
        (s.rest["vr"]?.object.keys.sorted() ?? []).compactMap { vendor(s, id: $0, data: data) }.sorted { $0.relationship > $1.relationship }
    }

    // MARK: Relationship

    public static func relationship(_ s: GameState, _ id: String) -> Double { s.rest["vr"]?[id]["r"].double ?? 0 }

    /// Original: `vbump`. A good procurement manager at the head office warms relationships faster.
    static func bump(_ s: inout GameState, _ id: String, by d: Double) {
        var vr = s.rest["vr"] ?? .object([:])
        var o = vr[id].isNull ? JSONValue.object(["r": 0, "w": .number(Double(s.week)), "meet": -99]) : vr[id]
        let r = o["r"].double
        o["r"] = .number(min(100, r + d * (1 - pow(r / 100, 1.6)) * (s.hasHeadOffice("proc") ? 1.4 : 1)))
        o["w"] = .number(Double(s.week))
        vr[id] = o
        s.rest["vr"] = vr
    }

    /// A supplier thinks less of you (late payment, walking out of a talk). The relationship falls by `d` points and stays at zero or above.
    static func dock(_ s: inout GameState, _ id: String, by d: Double) {
        guard var vr = s.rest["vr"], !vr[id].isNull else { return }
        var o = vr[id]
        o["r"] = .number(max(0, o["r"].double - d))
        vr[id] = o
        s.rest["vr"] = vr
    }

    public static func bumpPublic(_ s: inout GameState, _ id: String, by d: Double) { bump(&s, id, by: d) }

    /// Buying something makes the relationship grow a little. Original: `vbuy`.
    static func recordPurchase(_ s: inout GameState, vendorID id: String?, amount local: Double, priceIndex: Double = 1, big: Bool = false) {
        guard let id = id, local > 0 else { return }
        // The thresholds are at the reference price level: the same order is as big a deal in any country.
        let amount = local / max(0.01, priceIndex)
        bump(&s, id, by: big ? min(3.5, max(0.3, amount / 120000)) : min(0.15, max(0.01, amount.squareRoot() / 4000)))
    }

    public enum MeetResult: Equatable, Sendable { case ok, wait, cash, unknown }

    /// Take the owner to lunch. Original: `vmeet`.
    public static func meet(_ s: inout GameState, vendorID id: String, data: GameData) -> MeetResult {
        guard let v = vendor(s, id: id, data: data) else { return .unknown }
        var vr = s.rest["vr"] ?? .object([:])
        let o = vr[id].isNull ? JSONValue.object(["r": 0, "w": .number(Double(s.week)), "meet": -99]) : vr[id]
        let cost = homeCurrency(s, data).scaledPrice(5000)
        let r = CounterpartMeeting.meet(&s, lastWeek: o["meet"].double, cost: cost, label: "Lunch with \(v.owner) of \(v.name)") { t in
            var o2 = o; o2["meet"] = .number(Double(t.week))
            vr[id] = o2; t.rest["vr"] = vr
            bump(&t, id, by: Double(t.random.int(5, 9)))
        }
        return r == .ok ? .ok : r == .wait ? .wait : .cash
    }

    /// Relationships fade when you do not buy. Original: `vendMonth`.
    public static func monthly(_ s: inout GameState) {
        guard var vr = s.rest["vr"], !vr.isNull else { return }
        for (id, o) in vr.object {
            if Double(s.week) - o["w"].double > 10 { var n = o; n["r"] = .number(max(0, o["r"].double - 0.8)); vr[id] = n }
        }
        s.rest["vr"] = vr
    }

    // MARK: Discounts and agreements

    /// Original: `vdisc(scope, id)`; scope is "goods", "eq" or "fix".
    public static func discount(_ s: GameState, scope: String, vendorID id: String?) -> Double {
        guard let id = id, !id.isEmpty else { return 0 }
        return relationshipDiscount(relationship(s, id)) + (s.rest["agree"]?[scope].string == id ? 0.03 : 0)
    }

    public enum AgreeResult: Equatable, Sendable { case ok, fewCompanies, cash, unknown }

    /// Call the board together and agree to buy through one supplier for every company (nil ends the agreement). Original: `boardDeal`.
    public static func agree(_ s: inout GameState, scope: String, vendorID: String?, data: GameData) -> AgreeResult {
        guard ["goods", "eq", "fix"].contains(scope) else { return .unknown }
        if s.liveCompanies.count < 2 { return .fewCompanies }
        let cost = homeCurrency(s, data).scaledPrice(9000)
        if s.cash < cost { return .cash }
        Payments.playerPays(&s, cost, label: "Board meeting and dinner")
        var a = s.rest["agree"] ?? .object([:])
        a[scope] = vendorID.map { .string($0) } ?? .null
        s.rest["agree"] = a
        if let id = vendorID { bump(&s, id, by: 2) }
        return .ok
    }

    public static func agreement(_ s: GameState, scope: String) -> String? {
        let v = s.rest["agree"]?[scope] ?? .null
        return v.isNull ? nil : v.string
    }

    // MARK: Goods

    /// The person who buys: a manager with a poor eye does not always find the best deal. Original: `buyerSkill`.
    static func buyerSkill(_ s: GameState, _ co: Company, _ bd: Trade) -> Double {
        s.hasHeadOffice("proc") ? 1 : co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) : 0.4
    }

    public static func hasGoods(_ bd: Trade, _ co: Company) -> Bool {
        !(bd.costOfSales < 0.03 || ["fin", "energy", "rent", "club", "svc"].contains(bd.family) || co.type.hasPrefix("engcons") || co.type.hasPrefix("event"))
    }

    /// Who supplies this company's goods now. A manager (or you, with "auto") takes the best offer by discount and quality, or
    /// sometimes whoever comes first; the pick holds for 26 weeks. Original: `goodsPick`. The random choice is made from a seed made of
    /// the company and the half-year, not from the shared stream.
    public static func goodsVendor(_ s: GameState, company co: Company, data: GameData) -> Vendor? {
        guard let bd = data.catalog[co.type], hasGoods(bd, co) else { return nil }
        let src = co.value("src")
        if !src["v"].isNull, src["v"].string != "auto", let v = vendor(s, id: src["v"].string, scope: "goods", data: data) { return v }
        if let a = agreement(s, scope: "goods"), let v = vendor(s, id: a, scope: "goods", data: data) { return v }
        let list = candidates(s, company: co, scope: "goods", data: data)
        guard !list.isEmpty else { return nil }
        if let ac = co.raw["srcAuto"], !ac.isNull, Double(s.week) - ac["w"].double < 26, let v = list.first(where: { $0.id == ac["v"].string }) { return v }
        var r = HashedRandom("\(s.seed):gp:\(co.id):\(s.week / 26)")
        let best = list.max { ($0.discount - $0.quality * 0.06) < ($1.discount - $1.quality * 0.06) }!
        return r.next() < buyerSkill(s, co, bd) ? best : list[min(list.count - 1, Int(r.next() * Double(list.count)))]
    }

    /// Cost multiplier and quality shift of the goods. Original: `goodsEff`.
    public static func goodsEffect(_ s: GameState, company co: Company, _ bd: Trade, data: GameData, classes: [(cost: Double, quality: Double)]) -> (m: Double, q: Double, vendor: Vendor?) {
        guard hasGoods(bd, co) else { return (1, 0, nil) }
        let cls = co.value("src")["c"].isNull ? 1 : co.value("src")["c"].int
        let c = classes.indices.contains(cls) ? classes[cls] : classes[1]
        guard let v = goodsVendor(s, company: co, data: data) else { return (c.cost, c.quality, nil) }
        // A negotiated price (`SupplyDeals`) and the payment terms agreed (`SupplyTerms`) change the price; both exist only when the player set them.
        let deal = SupplyDeals.dealDiscount(co, scope: "goods", vendorID: v.id, week: s.week)
        let terms = SupplyTerms.goodsTerm(s, co, data: data)?.priceEffect ?? 0
        return (clamp(c.cost * (1 + v.quality * 0.3) * (1 - v.discount - deal) * (1 + terms), 0.7, 1.4), c.quality + v.quality * 10, v)
    }

    /// Who services the equipment, if anyone is chosen; the discount cuts repair bills. Original: `fixPick`, `fixDisc`.
    public static func repairVendor(_ s: GameState, company co: Company, data: GameData) -> Vendor? {
        let f = co.value("fixv")
        if !f.isNull, f.string != "auto", !f.string.isEmpty { return vendor(s, id: f.string, scope: "fix", data: data) }
        if let a = agreement(s, scope: "fix") { return vendor(s, id: a, scope: "fix", data: data) }
        return nil
    }
    public static func repairDiscount(_ s: GameState, company co: Company, data: GameData) -> Double {
        guard let v = repairVendor(s, company: co, data: data) else { return 0 }
        return v.discount + SupplyDeals.dealDiscount(co, scope: "fix", vendorID: v.id, week: s.week)
    }

    /// The company's weekly buying from its goods supplier warms the relationship. Original: `vbuy(ctx.gd.v.id, cogs)`.
    static func recordGoods(_ s: inout GameState, companyIndex i: Int, cogs: Double, data: GameData) {
        guard cogs > 0, let v = goodsVendor(s, company: s.companies[i], data: data) else { return }
        recordPurchase(&s, vendorID: v.id, amount: cogs, priceIndex: data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode).costIndex)
    }

    // MARK: Choosing (actions)

    /// `vendorID` "auto" lets the manager (or the market) decide. Original: `ACT.srcv`.
    public static func chooseGoodsVendor(_ s: inout GameState, companyID: Int, vendorID: String) {
        guard let i = s.companyIndex(companyID) else { return }
        var src = s.companies[i].value("src"); if src.isNull { src = .object(["c": 1]) }
        src["v"] = .string(vendorID); s.companies[i].set("src", src)
    }
    /// 0 Basic, 1 Standard, 2 Premium. Original: `ACT.srcc`.
    public static func chooseGoodsClass(_ s: inout GameState, companyID: Int, goodsClass: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var src = s.companies[i].value("src"); if src.isNull { src = .object(["v": "auto"]) }
        src["c"] = .number(Double(min(2, max(0, goodsClass)))); s.companies[i].set("src", src)
    }
    /// Original: `ACT.fixv`.
    public static func chooseRepairVendor(_ s: inout GameState, companyID: Int, vendorID: String) {
        guard let i = s.companyIndex(companyID) else { return }
        s.companies[i].set("fixv", vendorID)
    }
}
