import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

/// Buying from other players' companies: the landed-cost comparison, contracts in the buyer's books, one-off orders that travel and the list of
/// what is on the way. The market itself (listings, records, who is online) is the app's service; the engine owns what it does to a company's books.

/// What one unit of stock costs a company at the market price, and what its shelves hold: the basis of a one-off order.
public struct StockOrderBasis: Equatable, Sendable {
    public var unitCost: Double
    public var held: Double
    /// What the stock policy wants on the shelves; nil when the trade has no policy.
    public var target: Double?
}

public extension GameEngine {
    /// The offers' landed cost for a company's line, cheapest first. `weeklyMarketSpend` is what the line costs a week from the market supplier; `units` the weekly order.
    func playerSupplyLanded(companyID: Int, listings: [SupplyListing], weeklyMarketSpend: Double, units: Int) -> [SupplyLanded.Row] {
        guard let co = state.company(companyID) else { return [] }
        let level: Double = World(state: state, data: data).country(co).costIndex
        let n: Int = max(1, units)
        return SupplyLanded.compare(listings, buyerCountry: co.countryCode, marketUnitPrice: weeklyMarketSpend / Double(n), units: n, priceLevel: level)
    }

    /// Whether a player supplier may take this line of the company: the line exists, no chain rule or franchise agreement fixes it, and the buyer's trade has a real need for it.
    func playerSupplyAllowed(companyID: Int, listing l: SupplyListing) -> Bool {
        guard let co = state.company(companyID), co.status == .open, let bd = data.catalog[co.type],
              let line = SupplyCatalogue.lines(co, bd).first(where: { $0.id == l.lineID }) else { return false }
        // Never your own company: the market is not a way to move money between your own companies (own supply has its own link).
        if PlayerSupply.isOwnListing(state, l) { return false }
        if let input = line.input, supplierInputs(companyID: companyID).first(where: { $0.id == input })?.governedBy != nil { return false }
        return SupplyNeeds.uses(buyerTrade: co.type, buyerFamily: bd.family, line: l.lineID, supplierTrade: l.tradeID)
    }

    /// Sign a contract with a player's listing for one line. An own-company link on that kind of purchase ends first, as for any other switch.
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

    /// The line goes back to the House supplier.
    mutating func endPlayerSupplier(companyID: Int, lineID: String) {
        update { s, _, _ in PlayerSupply.end(&s, buyer: companyID, line: lineID) }
    }

    /// A short delivery the market reported on this listing; the buyers' customers are affected and they are told.
    /// It only says the delivery was short, so the buyer's record counts it as a week when a quarter of the units did not arrive; use
    /// `reportSupplyDelivery` when the real numbers are known.
    mutating func reportShortDelivery(listingID: String) {
        update { s, _, _ in
            if PlayerSupply.recordDelivery(&s, listingID: listingID, promised: 100, delivered: 75, orders: 1, late: 0).isEmpty { return }
        }
    }

    /// Why a listing cannot be used by this company, in words; nil when it can. Own companies are refused first.
    func playerSupplyBlock(companyID: Int, listing l: SupplyListing) -> String? {
        if PlayerSupply.isOwnListing(state, l) { return "Not available: it is one of your own companies" }
        return playerSupplyAllowed(companyID: companyID, listing: l) ? nil : "Not available: this company cannot use it"
    }

    /// A week of a supplier's deliveries as the market reports them: units asked for and delivered, late orders. The buyer's record with that
    /// supplier moves, and a short delivery cuts the buyer's cover and tells the buyer.
    mutating func reportSupplyDelivery(listingID: String, promised: Int, delivered: Int, orders: Int = 1, late: Int = 0) {
        update { s, _, _ in _ = PlayerSupply.recordDelivery(&s, listingID: listingID, promised: promised, delivered: delivered, orders: orders, late: late) }
    }

    /// What this supplier has really delivered to this line, since the contract was signed (units, punctuality, complaints, and the word for it).
    func playerSupplyDeliveryRecord(companyID: Int, lineID: String) -> DeliveryRecord? { PlayerSupply.deliveryRecord(state, buyer: companyID, line: lineID) }

    /// The market ended a contract (the supplier went bankrupt, closed, stopped or left): the line goes back to the House supplier and the buyer is told.
    mutating func applySupplierFallback(_ f: SupplyFallback) {
        update { s, _, _ in PlayerSupply.applyFallback(&s, f) }
    }

    /// A supplier is gone: every contract on its listing (or of its owner) ends and the buyers are warned.
    @discardableResult
    mutating func endSupplierContracts(listingID: String? = nil, ownerID: String? = nil, reason: SupplyEnd) -> [SupplyFallback] {
        var out: [SupplyFallback] = []
        update { s, _, _ in out = PlayerSupply.supplierEnded(&s, listingID: listingID, ownerID: ownerID, reason: reason) }
        return out
    }

    /// A supplier announced it will stop on `endsDay`: its buyers are told the day.
    mutating func announceSupplierStop(listingID: String, endsDay: Int) {
        update { s, _, _ in PlayerSupply.noticeOfStop(&s, listingID: listingID, endsDay: endsDay) }
    }

    /// The contracts saved with the game, and the player's own listings and their recent orders.
    var playerSupplyContracts: [SupplyContract] { PlayerSupply.contracts(state).map { $0.base } }
    var playerSupplyListings: [SupplyListing] { PlayerSupply.listings(state) }
    var playerSupplyOrders: [String: [SupplyOrderRecord]] { PlayerSupply.orders(state) }

    mutating func savePlayerListings(_ listings: [SupplyListing], orders: [String: [SupplyOrderRecord]]) {
        update { s, _, _ in PlayerSupply.saveListings(&s, listings: listings, orders: orders) }
    }

    // MARK: One-off orders that travel

    /// What a unit of this company's stock costs at the market price. Nil for a company that holds no stock or has not traded a full week yet.
    func stockOrderBasis(companyID: Int) -> StockOrderBasis? {
        guard let co = state.company(companyID), co.status == .open, let bd = data.catalog[co.type], bd.hasTrait("stock"), Suppliers.hasGoods(bd, co) else { return nil }
        let lw = co.value("lastW")
        guard lw["cogs"].double > 0, lw["units"].double > 0 else { return nil }
        return StockOrderBasis(unitCost: lw["cogs"].double / lw["units"].double, held: co.inventory, target: StockHandling.policyTarget(co, bd))
    }

    /// Order stock from a player's listing: paid at once with freight and customs, it joins the shelves when it arrives (`Shipments`).
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

    /// What is on the way to a company, soonest first.
    func shipmentsOnTheWay(companyID: Int) -> [Shipments.Row] { Shipments.rows(state, companyID: companyID) }
}
