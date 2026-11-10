import Foundation
import GameCore
import Countries
import Finance

public enum Sourcing {
    public static let outsideSupplierEvents: Set<String> = ["g_supply", "g_supbust", "pr_raw", "p_matprice", "pr_flour", "l_fuel", "r_carrier"]

    public static func suppliedFromInside(_ s: GameState, companyID: Int) -> Bool {
        IntercompanySupply.links(s).contains { l in
            l.buyerID == companyID && IntercompanySupply.kind(l.kindID)?.category == "cogs" && s.company(l.supplierID)?.status == .open
        }
    }

    public static func shields(_ s: GameState, companyID: Int, eventID: String) -> Bool {
        outsideSupplierEvents.contains(eventID) && suppliedFromInside(s, companyID: companyID)
    }

    public struct Offer: Equatable, Sendable {
        public var vendor: Suppliers.Vendor
        public var goodsClass: Int
        public var costFactor: Double
        public var qualityShift: Double
        public var current: Bool
    }

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

    public struct Summary: Equatable, Sendable {
        public var buysGoods: Bool
        public var goodsSupplier: Suppliers.Vendor?
        public var goodsClass: Int
        public var goodsCostFactor: Double
        public var goodsQualityShift: Double
        public var repairSupplier: Suppliers.Vendor?
        public var repairDiscount: Double
        public var boardAgreements: [String: String]
        public var suppliedFromInside: Bool
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
