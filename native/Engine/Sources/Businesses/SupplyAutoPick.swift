import Foundation
import GameCore

/// Stock, upkeep and servicing need no decision from the player: a company gets its suppliers when it opens.
/// An own company that supplies the line comes first; otherwise the most reliable player supplier at a fair price.
/// Services (cleaning, security, temp staff, marketing, laundry) stay the player's choice. Every pick can be changed later.
public enum SupplyAutoPick {
    /// Supply-map groups whose lines are filled without asking.
    public static let automaticGroups: Set<String> = ["Stock", "Upkeep"]
    static let flag = "asup"

    public static func isAutomatic(group: String) -> Bool { automaticGroups.contains(group) }

    /// Whether this company's suppliers are kept filled for it (companies opened before this rule keep what they had).
    public static func applies(_ co: Company) -> Bool { co.flag(flag) }

    /// Called when a company opens: links own suppliers and fills every stocked product's supplier.
    public static func assign(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return }
        s.companies[i].set(flag, true)
        linkOwnSuppliers(&s, companyID: companyID, bd, data: data)
        fillItems(&s, i, data: data)
    }

    /// The most reliable supplier that does not charge above the usual price; ties go to the line's standard supplier.
    public static func fairest(_ list: [SupplyPlayers.Supplier]) -> SupplyPlayers.Supplier? {
        let fair: [SupplyPlayers.Supplier] = list.filter { (p: SupplyPlayers.Supplier) -> Bool in p.tier <= 1 }
        return (fair.isEmpty ? list : fair).max { (a: SupplyPlayers.Supplier, b: SupplyPlayers.Supplier) -> Bool in
            a.reliability != b.reliability ? a.reliability < b.reliability : a.slot > b.slot
        }
    }

    /// The supplier a stocked product buys from when none was picked: the company's chosen or agreed goods supplier, else the fairest one.
    public static func goodsSupplierID(_ s: GameState, _ co: Company, data: GameData) -> String? {
        guard let bd = data.catalog[co.type], Suppliers.hasGoods(bd, co) else { return nil }
        let src: JSONValue = co.value("src")
        let explicit: Bool = !src["v"].isNull && src["v"].string != "auto"
        if explicit || Suppliers.agreement(s, scope: "goods") != nil { return Suppliers.goodsVendor(s, company: co, data: data)?.id }
        guard let line = SupplyMap.stockLine(bd.id)?.line else { return nil }
        let open: [SupplyPlayers.Supplier] = Suppliers.lineSuppliers(s, company: co, line: line, data: data)
            .filter { (p: SupplyPlayers.Supplier) -> Bool in !Sourcing.lapsed(co, vendorID: p.id, week: s.week) }
        return fairest(open)?.id ?? Suppliers.goodsVendor(s, company: co, data: data)?.id
    }

    /// Stocked or made products without a supplier get the goods supplier. The pick is free to change: no cooldown starts.
    public static func fillItems(_ s: inout GameState, _ i: Int, data: GameData) {
        guard s.companies.indices.contains(i), applies(s.companies[i]) else { return }
        let co: Company = s.companies[i]
        let open: [ItemModels.Record] = ItemModels.records(co).filter { (r: ItemModels.Record) -> Bool in (r.model == .stk || r.model == .made) && r.supplierID == nil }
        guard !open.isEmpty, let vendor = goodsSupplierID(s, co, data: data) else { return }
        for r in open {
            let want: Int = ItemModels.monthlyNeed(s, companyID: co.id, itemID: r.id, data: data)
            ItemModels.mutate(&s, companyID: co.id, itemID: r.id) { (x: inout ItemModels.Record) in
                x.supplierID = vendor
                x.monthlyUnits = want
            }
        }
    }

    /// Stock and upkeep lines an own company can supply are linked to it at full price, the busiest such company first.
    static func linkOwnSuppliers(_ s: inout GameState, companyID: Int, _ bd: Trade, data: GameData) {
        guard let co = s.company(companyID) else { return }
        let kinds: [IntercompanySupply.Kind] = IntercompanySupply.kindsFor(co)
        for line in SupplyCatalogue.lines(co, bd) where isAutomatic(group: line.group) && !line.automatic {
            guard let k = kinds.first(where: { (x: IntercompanySupply.Kind) -> Bool in x.id == line.id }),
                  IntercompanySupply.link(s, buyer: companyID, kind: k.id) == nil,
                  SupplyDeals.governedBy(s, co, input: k.id, data: data) == nil else { continue }
            let own: [Company] = IntercompanySupply.suppliers(s, for: co, kind: k)
            guard let best = own.max(by: { (a: Company, b: Company) -> Bool in a.staff.count != b.staff.count ? a.staff.count < b.staff.count : a.id > b.id }) else { continue }
            IntercompanySupply.setSupplier(&s, buyer: companyID, kind: k.id, supplier: best.id, mode: "mkt")
        }
    }
}
