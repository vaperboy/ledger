import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Who you buy from: suppliers per company, the relationship with each owner, and board agreements.
/// Originals: `CT.supply`, `ACT.srcv`, `srcc`, `fixv`, `vmeet`, `boarddeal` (ui/company/deals.js, ui/screens/group.js).
public extension GameEngine {
    /// Candidates for goods (scope "goods") or repairs (scope "fix").
    func supplierCandidates(companyID: Int, scope: String) -> [Suppliers.Vendor] { state.company(companyID).map { Suppliers.candidates(state, company: $0, scope: scope, data: data) } ?? [] }
    func currentGoodsSupplier(companyID: Int) -> Suppliers.Vendor? { state.company(companyID).flatMap { Suppliers.goodsVendor(state, company: $0, data: data) } }
    func currentRepairSupplier(companyID: Int) -> Suppliers.Vendor? { state.company(companyID).flatMap { Suppliers.repairVendor(state, company: $0, data: data) } }
    /// What the goods cost compared with the market price (1 is the market price) with the chosen class and supplier; nil if the trade buys no goods.
    func goodsCostFactor(companyID: Int) -> Double? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], Suppliers.hasGoods(bd, co) else { return nil }
        return Suppliers.goodsEffect(state, company: co, bd, data: data, classes: marketing.goodsClasses).m
    }
    var knownSuppliers: [Suppliers.Vendor] { Suppliers.known(state, data: data) }
    func boardAgreement(scope: String) -> String? { Suppliers.agreement(state, scope: scope) }

    /// 0 Basic, 1 Standard, 2 Premium.
    mutating func chooseGoodsClass(companyID: Int, goodsClass: Int) { update { s, _, _ in Suppliers.chooseGoodsClass(&s, companyID: companyID, goodsClass: goodsClass) } }
    @discardableResult mutating func lunchWithSupplier(vendorID: String) -> Suppliers.MeetResult {
        var r = Suppliers.MeetResult.unknown
        update { s, d, _ in r = Suppliers.meet(&s, vendorID: vendorID, data: d) }
        return r
    }
    /// Agree with the board to buy through one supplier for every company (vendorID nil ends the agreement). Scope: "goods", "eq" or "fix".
    @discardableResult mutating func agreeSupplierDeal(scope: String, vendorID: String?) -> Suppliers.AgreeResult {
        var r = Suppliers.AgreeResult.unknown
        update { s, d, _ in r = Suppliers.agree(&s, scope: scope, vendorID: vendorID, data: d) }
        return r
    }
}
