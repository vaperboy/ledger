import Foundation
import GameCore
import Countries
import Finance

/// The sourcing picture of a company, on top of `Suppliers` (who supplies goods and repairs, relationships, discounts, board
/// agreements: actions `srcv`, `srcc`, `fixv` live there). This file adds what was still missing:
///
///  * the repair supplier's discount (`fixDisc`) reaches the weekly upkeep bill and the "service all" bill (hooks in
///    `CompanyCosts.equipmentWeek` and `EquipmentMarket.serviceAll`);
///  * supply from inside protects against outside supplier trouble: a company that gets goods from one of your own companies
///    (`IntercompanySupply`, an input that counts as cost of sales) is not hit by the supplier events below
///    (`EventEngine.spawn` asks `shields`). Original: step `fireEvent.before` of features/company/intercompany_supply.js;
///  * a comparison of the suppliers on offer for each quality class (what the goods would cost and how they change quality),
///    which is what the Suppliers tab shows next to the chips.
public enum Sourcing {
    /// Events about an outside supplier raising prices, failing or cutting delivery. Original: the list in `fireEvent.before`.
    public static let outsideSupplierEvents: Set<String> = ["g_supply", "g_supbust", "pr_raw", "p_matprice", "pr_flour", "l_fuel", "r_carrier"]

    /// Does one of your own companies supply an input of this company that counts as cost of sales (food, materials, freight)?
    public static func suppliedFromInside(_ s: GameState, companyID: Int) -> Bool {
        IntercompanySupply.links(s).contains { l in
            l.buyerID == companyID && IntercompanySupply.kind(l.kindID)?.category == "cogs" && s.company(l.supplierID)?.status == .open
        }
    }

    /// True when the event must not happen to this company because its supplier is inside the group.
    public static func shields(_ s: GameState, companyID: Int, eventID: String) -> Bool {
        outsideSupplierEvents.contains(eventID) && suppliedFromInside(s, companyID: companyID)
    }

    /// One supplier on offer for one quality class.
    public struct Offer: Equatable, Sendable {
        public var vendor: Suppliers.Vendor
        public var goodsClass: Int
        /// What the goods cost compared with the market price (1 = market price).
        public var costFactor: Double
        /// Points added to the quality of the goods.
        public var qualityShift: Double
        /// The one the company uses now.
        public var current: Bool
    }

    /// Every candidate supplier, for the company's chosen class (or `goodsClass`), cheapest first. Original: `goodsEff` per vendor.
    public static func offers(_ s: GameState, company co: Company, goodsClass: Int? = nil, data: GameData, classes: [(cost: Double, quality: Double)]) -> [Offer] {
        guard let bd = data.catalog[co.type], Suppliers.hasGoods(bd, co), !classes.isEmpty else { return [] }
        let chosen = co.value("src")["c"].isNull ? 1 : co.value("src")["c"].int
        let cls = min(classes.count - 1, max(0, goodsClass ?? chosen))
        let c = classes[cls]
        let current = Suppliers.goodsVendor(s, company: co, data: data)?.id
        return Suppliers.candidates(s, company: co, scope: "goods", data: data).map { v in
            Offer(vendor: v, goodsClass: cls, costFactor: clamp(c.cost * (1 + v.quality * 0.3) * (1 - v.discount), 0.7, 1.4),
                  qualityShift: c.quality + v.quality * 10, current: v.id == current)
        }.sorted { $0.costFactor < $1.costFactor }
    }

    /// What the Suppliers tab says about a company.
    public struct Summary: Equatable, Sendable {
        public var buysGoods: Bool
        public var goodsSupplier: Suppliers.Vendor?
        public var goodsClass: Int
        public var goodsCostFactor: Double
        public var goodsQualityShift: Double
        public var repairSupplier: Suppliers.Vendor?
        /// Share cut from repair and upkeep bills.
        public var repairDiscount: Double
        /// The board has agreed one supplier for every company: scope -> supplier id
        public var boardAgreements: [String: String]
        public var suppliedFromInside: Bool
        /// A manager picks the supplier and is not always good at finding the best deal.
        public var managerMayOverpay: Bool
    }

    public static func summary(_ s: GameState, company co: Company, data: GameData, classes: [(cost: Double, quality: Double)]) -> Summary? {
        guard let bd = data.catalog[co.type] else { return nil }
        let buys = Suppliers.hasGoods(bd, co)
        let eff = Suppliers.goodsEffect(s, company: co, bd, data: data, classes: classes)
        var agreements: [String: String] = [:]
        for scope in ["goods", "eq", "fix"] { if let a = Suppliers.agreement(s, scope: scope) { agreements[scope] = a } }
        let src = co.value("src")
        let auto = src["v"].isNull || src["v"].string == "auto"
        let repair = Suppliers.repairVendor(s, company: co, data: data)
        return Summary(buysGoods: buys, goodsSupplier: eff.vendor, goodsClass: src["c"].isNull ? 1 : src["c"].int, goodsCostFactor: eff.m, goodsQualityShift: eff.q,
                       repairSupplier: repair, repairDiscount: repair?.discount ?? 0, boardAgreements: agreements,
                       suppliedFromInside: suppliedFromInside(s, companyID: co.id),
                       managerMayOverpay: buys && auto && co.managerID != nil && !s.hasHeadOffice("proc") && Suppliers.buyerSkill(s, co, bd) < 0.55)
    }
}
