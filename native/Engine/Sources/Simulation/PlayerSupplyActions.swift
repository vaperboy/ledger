import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

public struct StockOrderBasis: Equatable, Sendable {
    public var unitCost: Double
    public var held: Double
    public var target: Double?
}

public extension GameEngine {
    func playerSupplyLanded(companyID: Int, listings: [SupplyListing], weeklyMarketSpend: Double, units: Int) -> [SupplyLanded.Row] {
        guard let co = state.company(companyID) else { return [] }
        let level: Double = World(state: state, data: data).country(co).costIndex
        let n: Int = max(1, units)
        return SupplyLanded.compare(listings, buyerCountry: co.countryCode, marketUnitPrice: weeklyMarketSpend / Double(n), units: n, priceLevel: level)
    }

    func playerSupplyAllowed(companyID: Int, listing l: SupplyListing) -> Bool {
        guard let co = state.company(companyID), co.status == .open, let bd = data.catalog[co.type],
              let line = SupplyCatalogue.lines(co, bd).first(where: { $0.id == l.lineID }) else { return false }
        if PlayerSupply.isOwnListing(state, l) { return false }
        if let input = line.input, supplierInputs(companyID: companyID).first(where: { $0.id == input })?.governedBy != nil { return false }
        return SupplyNeeds.uses(buyerTrade: co.type, buyerFamily: bd.family, line: l.lineID, supplierTrade: l.tradeID)
    }

    @discardableResult
    mutating func signPlayerSupplier(contract: SupplyContract, listing l: SupplyListing, weeklyMarketSpend: Double) -> Bool {
        guard !l.stopped, !l.paused, l.stopsDay == nil, contract.unitsPerWeek > 0, contract.unitsPerWeek >= l.minOrder,
              contract.unitsPerWeek <= SupplyGuards.effectiveCapacity(l) - l.committedUnits + ownUnits(contract, l),
              playerSupplyAllowed(companyID: contract.buyerCompanyID, listing: l), let co = state.company(contract.buyerCompanyID), let bd = data.catalog[co.type],
              let line = SupplyCatalogue.lines(co, bd).first(where: { $0.id == contract.lineID }) else { return false }
        if let k = line.input, k != "goods", k != "repair", IntercompanySupply.kind(k) != nil,
           IntercompanySupply.link(state, buyer: co.id, kind: k) != nil || AccountSupply.link(state, buyer: co.id, kind: k) != nil {
            if switchSupplier(companyID: co.id, input: k, to: .outside) != .ok { return false }
        }
        var ok = false
        update { s, d, _ in ok = PlayerSupply.sign(&s, contract: contract, listing: l, weeklyMarketSpend: weeklyMarketSpend, data: d) }
        return ok
    }

    private func ownUnits(_ c: SupplyContract, _ l: SupplyListing) -> Int {
        PlayerSupply.contract(state, buyer: c.buyerCompanyID, line: c.lineID).map { $0.base.listingID == l.id ? $0.base.unitsPerWeek : 0 } ?? 0
    }

    mutating func endPlayerSupplier(companyID: Int, lineID: String) {
        update { s, _, _ in PlayerSupply.end(&s, buyer: companyID, line: lineID) }
    }

    mutating func reportShortDelivery(listingID: String) {
        update { s, _, _ in
            if PlayerSupply.recordDelivery(&s, listingID: listingID, promised: 100, delivered: 75, orders: 1, late: 0).isEmpty { return }
        }
    }

    func playerSupplyBlock(companyID: Int, listing l: SupplyListing) -> String? {
        if PlayerSupply.isOwnListing(state, l) { return "Not available: it is one of your own companies" }
        return playerSupplyAllowed(companyID: companyID, listing: l) ? nil : "Not available: this company cannot use it"
    }

    mutating func reportSupplyDelivery(listingID: String, promised: Int, delivered: Int, orders: Int = 1, late: Int = 0) {
        update { s, _, _ in _ = PlayerSupply.recordDelivery(&s, listingID: listingID, promised: promised, delivered: delivered, orders: orders, late: late) }
    }

    func playerSupplyDeliveryRecord(companyID: Int, lineID: String) -> DeliveryRecord? { PlayerSupply.deliveryRecord(state, buyer: companyID, line: lineID) }

    mutating func applySupplierFallback(_ f: SupplyFallback) {
        update { s, _, _ in PlayerSupply.applyFallback(&s, f) }
    }

    @discardableResult
    mutating func endSupplierContracts(listingID: String? = nil, ownerID: String? = nil, reason: SupplyEnd) -> [SupplyFallback] {
        var out: [SupplyFallback] = []
        update { s, _, _ in out = PlayerSupply.supplierEnded(&s, listingID: listingID, ownerID: ownerID, reason: reason) }
        return out
    }

    mutating func announceSupplierStop(listingID: String, endsDay: Int) {
        update { s, _, _ in PlayerSupply.noticeOfStop(&s, listingID: listingID, endsDay: endsDay) }
    }

    var playerSupplyContracts: [SupplyContract] { PlayerSupply.contracts(state).map { $0.base } }
    var playerSupplyListings: [SupplyListing] { PlayerSupply.listings(state) }
    var playerSupplyOrders: [String: [SupplyOrderRecord]] { PlayerSupply.orders(state) }

    mutating func savePlayerListings(_ listings: [SupplyListing], orders: [String: [SupplyOrderRecord]]) {
        update { s, _, _ in PlayerSupply.saveListings(&s, listings: listings, orders: orders) }
    }

    func stockOrderBasis(companyID: Int) -> StockOrderBasis? {
        guard let co = state.company(companyID), co.status == .open, let bd = data.catalog[co.type], bd.hasTrait("stock"), Suppliers.hasGoods(bd, co) else { return nil }
        let lw = co.value("lastW")
        guard lw["cogs"].double > 0, lw["units"].double > 0 else { return nil }
        return StockOrderBasis(unitCost: lw["cogs"].double / lw["units"].double, held: co.inventory, target: StockHandling.policyTarget(co, bd))
    }

    @discardableResult
    mutating func orderFromSupplier(companyID: Int, listing l: SupplyListing, units: Int) -> Shipments.OrderResult {
        guard l.lineID == "goods", units > 0, !l.stopped, !l.paused, l.stopsDay == nil, playerSupplyAllowed(companyID: companyID, listing: l), let basis = stockOrderBasis(companyID: companyID),
              let co = state.company(companyID) else { return .badOrder }
        let cargo: TransportCost.Cargo = SupplyLanded.cargo(lineID: l.lineID, supplierTrade: l.tradeID) ?? .standard
        let offer = TransportCost.Offer(id: l.id, country: l.country.isEmpty ? co.countryCode : l.country, unitPrice: basis.unitCost * l.priceFactor)
        var r = Shipments.OrderResult.badOrder
        update { s, d, _ in r = Shipments.order(&s, companyID: companyID, offer: offer, units: Double(units), cargo: cargo, supplierName: l.ownerName, data: d) }
        return r
    }

    func shipmentsOnTheWay(companyID: Int) -> [Shipments.Row] { Shipments.rows(state, companyID: companyID) }
}
