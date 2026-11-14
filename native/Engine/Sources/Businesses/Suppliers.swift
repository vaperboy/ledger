import Foundation
import GameCore
import Countries
import Finance

public enum Suppliers {
    static let words: [(below: Double, word: String)] = [(8, "Stranger"), (22, "Acquaintance"), (36, "Familiar"), (50, "Friendly"), (64, "Close"), (78, "Good friend"), (92, "Close friend"), (101, "Best friend")]
    static let discounts: [Double] = [0, 0, 0.01, 0.03, 0.05, 0.08, 0.12, 0.17]

    static func index(_ r: Double) -> Int { words.firstIndex { r < $0.below } ?? 7 }
    public static func relationshipWord(_ r: Double) -> String { words[index(r)].word }
    public static func relationshipDiscount(_ r: Double) -> Double { discounts[index(r)] }
    public static let goodsClassNames = ["Basic", "Standard", "Premium"]

    public struct Vendor: Equatable, Sendable {
        public var id: String
        public var name: String
        public var owner: String
        public var quality: Double
        public var rating: Double
        public var relationship: Double
        public var relationshipWord: String
        public var discount: Double
        public var tradeID: String = ""
        public var ownerCode: String = ""
        public var city: String = ""
        public var logoID: String = ""
        public var reliability: Double = 0.95
        public var lineID: String = ""
        public var isStandard: Bool = false
    }

    static func homeCurrency(_ s: GameState, _ data: GameData) -> Currency {
        Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
    }

    static func nouns(_ data: GameData) -> JSONValue { data.catalog.tables.raw["FAM_NOUN"] }

    static func make(_ v: EquipmentMarket.Vendor, scope: String, _ s: GameState) -> Vendor {
        let r = relationship(s, v.id)
        let rating = jsRound(clamp(3.6 + v.quality * 2.2, 2.6, 4.8) * 10) / 10
        return Vendor(id: v.id, name: v.name, owner: v.owner, quality: v.quality, rating: rating,
                      relationship: r, relationshipWord: relationshipWord(r), discount: discount(s, scope: scope, vendorID: v.id),
                      reliability: min(0.995, max(0.8, 0.85 + (rating - 2.6) / 2.2 * 0.14)))
    }

    // A supplier company seen through the relationship, deal and terms rules every supplier shares.
    static func make(_ p: SupplyPlayers.Supplier, scope: String, _ s: GameState) -> Vendor {
        let r = relationship(s, p.id)
        let rating = jsRound(clamp(2.6 + (p.reliability - 0.85) / 0.14 * 2.2, 2.6, 4.9) * 10) / 10
        return Vendor(id: p.id, name: p.name, owner: p.owner, quality: p.quality, rating: rating, relationship: r, relationshipWord: relationshipWord(r),
                      discount: discount(s, scope: scope, vendorID: p.id), tradeID: p.tradeID, ownerCode: p.ownerCode, city: p.city, logoID: p.logoID,
                      reliability: p.reliability, lineID: p.lineID, isStandard: p.isStandard)
    }

    public static func fakesOff(_ s: GameState) -> Bool { (s.rest["fake"] ?? .null)["off"].bool }
    public static func realSuppliers(_ s: GameState) -> Int { max(0, (s.rest["fake"] ?? .null)["real"].int) }

    // Every line keeps at least two suppliers: real players take the other places first.
    public static let minimumSuppliers = 2
    public static func fakeSlots(needed: Int, real: Int, off: Bool) -> Int { max(minimumSuppliers, needed - max(0, real)) }

    // The line a scope buys on: goods is the stock line, fix the building or machine upkeep line.
    public static func scopeLine(_ co: Company, _ bd: Trade, scope: String) -> String? {
        switch scope {
        case "goods": return SupplyMap.stockLine(bd.id)?.line
        case "fix": return upkeepLine(bd)
        default: return SupplyMap.need(bd.id, line: scope) != nil ? scope : nil
        }
    }

    public static func upkeepLine(_ bd: Trade) -> String? {
        SupplyMap.needs(bd.id).first { $0.line == "upkeep" || $0.line == "machines" }?.line
    }

    public static func lineSuppliers(_ s: GameState, company co: Company, line: String, data: GameData) -> [SupplyPlayers.Supplier] {
        let trades = SupplyMap.suppliers(line: line, buyer: co.type)
        let n = fakeSlots(needed: EquipmentMarket.brandCount(co, state: s), real: realSuppliers(s), off: fakesOff(s))
        return SupplyPlayers.list(seed: s.seed, countryCode: co.countryCode, line: line, trades: trades, count: n, countries: data.countries)
    }

    public static func candidates(_ s: GameState, company co: Company, scope: String, data: GameData) -> [Vendor] {
        guard let bd = data.catalog[co.type], let line = scopeLine(co, bd, scope: scope) else { return [] }
        return lineSuppliers(s, company: co, line: line, data: data).map { make($0, scope: scope, s) }
    }

    public static func setRealSuppliers(_ s: inout GameState, count: Int) {
        var f = s.rest["fake"] ?? .object([:])
        let n = Double(max(0, count))
        guard f["real"].double != n else { return }
        f["real"] = .number(n)
        s.rest["fake"] = f
    }

    // Computer-run players leave the boards; supply lines keep their suppliers so no line is left without one.
    @discardableResult
    public static func removeFakes(_ s: inout GameState) -> Int {
        var f = s.rest["fake"] ?? .object([:])
        let already = f["off"].bool
        f["off"] = .bool(true)
        s.rest["fake"] = f
        return already ? 0 : 1
    }

    public static func vendor(_ s: GameState, id: String, scope: String = "goods", data: GameData) -> Vendor? {
        if let p = SupplyPlayers.supplier(seed: s.seed, id: id, countries: data.countries) { return make(p, scope: scope, s) }
        let p = id.split(separator: "-").map(String.init)
        guard p.count == 3, p[0] == "V", let i = Int(p[2]) else { return nil }
        let pool = EquipmentMarket.vendorPool(seed: s.seed, countryCode: p[1], countries: data.countries, nouns: nouns(data))
        return pool.indices.contains(i) ? make(pool[i].vendor, scope: scope, s) : nil
    }

    public static func known(_ s: GameState, data: GameData) -> [Vendor] {
        (s.rest["vr"]?.object.keys.sorted() ?? []).compactMap { vendor(s, id: $0, data: data) }.sorted { $0.relationship > $1.relationship }
    }

    public static func relationship(_ s: GameState, _ id: String) -> Double { s.rest["vr"]?[id]["r"].double ?? 0 }

    static func bump(_ s: inout GameState, _ id: String, by d: Double) {
        var vr = s.rest["vr"] ?? .object([:])
        var o = vr[id].isNull ? JSONValue.object(["r": 0, "w": .number(Double(s.week)), "meet": -99]) : vr[id]
        let r = o["r"].double
        o["r"] = .number(min(100, r + d * (1 - pow(r / 100, 1.6)) * (s.hasHeadOffice("proc") ? 1.4 : 1)))
        o["w"] = .number(Double(s.week))
        vr[id] = o
        s.rest["vr"] = vr
    }

    static func dock(_ s: inout GameState, _ id: String, by d: Double) {
        guard var vr = s.rest["vr"], !vr[id].isNull else { return }
        var o = vr[id]
        o["r"] = .number(max(0, o["r"].double - d))
        vr[id] = o
        s.rest["vr"] = vr
    }

    public static func bumpPublic(_ s: inout GameState, _ id: String, by d: Double) { bump(&s, id, by: d) }

    static func recordPurchase(_ s: inout GameState, vendorID id: String?, amount local: Double, priceIndex: Double = 1, big: Bool = false) {
        guard let id = id, local > 0 else { return }
        let amount = local / max(0.01, priceIndex)
        bump(&s, id, by: big ? min(3.5, max(0.3, amount / 120000)) : min(0.15, max(0.01, amount.squareRoot() / 4000)))
    }

    public enum MeetResult: Equatable, Sendable { case ok, wait, cash, unknown }

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

    public static func monthly(_ s: inout GameState) {
        guard var vr = s.rest["vr"], !vr.isNull else { return }
        for (id, o) in vr.object {
            if Double(s.week) - o["w"].double > 10 { var n = o; n["r"] = .number(max(0, o["r"].double - 0.8)); vr[id] = n }
        }
        s.rest["vr"] = vr
    }

    public static func discount(_ s: GameState, scope: String, vendorID id: String?) -> Double {
        guard let id = id, !id.isEmpty else { return 0 }
        return relationshipDiscount(relationship(s, id)) + (s.rest["agree"]?[scope].string == id ? 0.03 : 0)
    }

    public enum AgreeResult: Equatable, Sendable { case ok, cash, unknown }

    public static func agree(_ s: inout GameState, scope: String, vendorID: String?, data: GameData) -> AgreeResult {
        guard ["goods", "eq", "fix"].contains(scope) else { return .unknown }
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

    static func buyerSkill(_ s: GameState, _ co: Company, _ bd: Trade) -> Double {
        s.hasHeadOffice("proc") ? 1 : co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) : 0.4
    }

    public static func hasGoods(_ bd: Trade, _ co: Company) -> Bool {
        !(bd.costOfSales < 0.03 || ["fin", "energy", "rent", "club", "svc"].contains(bd.family) || co.type.hasPrefix("engcons") || co.type.hasPrefix("event"))
            && SupplyMap.stockLine(bd.id) != nil
    }

    // The chosen supplier, else the board agreement, else the line's standard supplier (one that has not just let the company down).
    public static func goodsVendor(_ s: GameState, company co: Company, data: GameData) -> Vendor? {
        guard let bd = data.catalog[co.type], hasGoods(bd, co) else { return nil }
        let all = candidates(s, company: co, scope: "goods", data: data)
        let src = co.value("src")
        if !src["v"].isNull, src["v"].string != "auto", let v = all.first(where: { $0.id == src["v"].string }) { return v }
        if let a = agreement(s, scope: "goods"), let v = all.first(where: { $0.id == a }) { return v }
        return all.first { !Sourcing.lapsed(co, vendorID: $0.id, week: s.week) } ?? all.first
    }

    public static func goodsEffect(_ s: GameState, company co: Company, _ bd: Trade, data: GameData, classes: [(cost: Double, quality: Double)]) -> (m: Double, q: Double, vendor: Vendor?) {
        guard hasGoods(bd, co) else { return (1, 0, nil) }
        let cls = co.value("src")["c"].isNull ? 1 : co.value("src")["c"].int
        let c = classes.indices.contains(cls) ? classes[cls] : classes[1]
        if let line = SupplyMap.stockLine(bd.id)?.line, let pc = PlayerSupply.contract(s, buyer: co.id, line: line) {
            let qc = classes.indices.contains(pc.qualityTier) ? classes[pc.qualityTier] : classes[1]
            return (clamp(qc.cost * PlayerSupply.priceFactor(pc), 0.7, 1.6), qc.quality, nil)
        }
        guard let v = goodsVendor(s, company: co, data: data) else { return (c.cost, c.quality, nil) }
        let deal = SupplyDeals.dealDiscount(co, scope: "goods", vendorID: v.id, week: s.week)
        let terms = SupplyTerms.goodsTerm(s, co, data: data)?.priceEffect ?? 0
        let disc = ItemModels.blendedDiscount(s, co, base: v.discount) ?? v.discount
        return (clamp(c.cost * (1 + v.quality * 0.3) * (1 - disc - deal) * (1 + terms), 0.7, 1.4), c.quality + v.quality * 10, v)
    }

    public static func repairVendor(_ s: GameState, company co: Company, data: GameData) -> Vendor? {
        let all = candidates(s, company: co, scope: "fix", data: data)
        let f = co.value("fixv")
        if !f.isNull, f.string != "auto", !f.string.isEmpty, let v = all.first(where: { $0.id == f.string }) { return v }
        if let a = agreement(s, scope: "fix"), let v = all.first(where: { $0.id == a }) { return v }
        return all.first
    }
    public static func repairDiscount(_ s: GameState, company co: Company, data: GameData) -> Double {
        if let bd = data.catalog[co.type], let line = upkeepLine(bd), let pc = PlayerSupply.contract(s, buyer: co.id, line: line) {
            return 1 - SupplyCatalogue.tierPrice[min(2, max(0, pc.priceTier))]
        }
        guard let v = repairVendor(s, company: co, data: data) else { return 0 }
        return v.discount + SupplyDeals.dealDiscount(co, scope: "fix", vendorID: v.id, week: s.week)
    }

    static func recordGoods(_ s: inout GameState, companyIndex i: Int, cogs: Double, data: GameData) {
        guard cogs > 0, let v = goodsVendor(s, company: s.companies[i], data: data) else { return }
        recordPurchase(&s, vendorID: v.id, amount: cogs, priceIndex: data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode).costIndex)
    }

    public static func chooseGoodsVendor(_ s: inout GameState, companyID: Int, vendorID: String) {
        guard let i = s.companyIndex(companyID) else { return }
        var src = s.companies[i].value("src"); if src.isNull { src = .object(["c": 1]) }
        src["v"] = .string(vendorID); s.companies[i].set("src", src)
    }
    public static func chooseGoodsClass(_ s: inout GameState, companyID: Int, goodsClass: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var src = s.companies[i].value("src"); if src.isNull { src = .object(["v": "auto"]) }
        src["c"] = .number(Double(min(2, max(0, goodsClass)))); s.companies[i].set("src", src)
    }
    public static func chooseRepairVendor(_ s: inout GameState, companyID: Int, vendorID: String) {
        guard let i = s.companyIndex(companyID) else { return }
        s.companies[i].set("fixv", vendorID)
    }
}
