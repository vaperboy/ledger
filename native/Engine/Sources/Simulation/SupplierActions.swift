import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    func supplierCandidates(companyID: Int, scope: String) -> [Suppliers.Vendor] { state.company(companyID).map { Suppliers.candidates(state, company: $0, scope: scope, data: data) } ?? [] }
    func currentGoodsSupplier(companyID: Int) -> Suppliers.Vendor? { state.company(companyID).flatMap { Suppliers.goodsVendor(state, company: $0, data: data) } }
    func currentRepairSupplier(companyID: Int) -> Suppliers.Vendor? { state.company(companyID).flatMap { Suppliers.repairVendor(state, company: $0, data: data) } }
    func goodsCostFactor(companyID: Int) -> Double? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], Suppliers.hasGoods(bd, co) else { return nil }
        return Suppliers.goodsEffect(state, company: co, bd, data: data, classes: marketing.goodsClasses).m
    }
    var knownSuppliers: [Suppliers.Vendor] { Suppliers.known(state, data: data) }
    func boardAgreement(scope: String) -> String? { Suppliers.agreement(state, scope: scope) }

    mutating func chooseGoodsClass(companyID: Int, goodsClass: Int) { update { s, _, _ in Suppliers.chooseGoodsClass(&s, companyID: companyID, goodsClass: goodsClass) } }
    @discardableResult mutating func lunchWithSupplier(vendorID: String) -> Suppliers.MeetResult {
        var r = Suppliers.MeetResult.unknown
        update { s, d, _ in r = Suppliers.meet(&s, vendorID: vendorID, data: d) }
        return r
    }
    @discardableResult mutating func agreeSupplierDeal(scope: String, vendorID: String?) -> Suppliers.AgreeResult {
        var r = Suppliers.AgreeResult.unknown
        update { s, d, _ in r = Suppliers.agree(&s, scope: scope, vendorID: vendorID, data: d) }
        return r
    }
}
