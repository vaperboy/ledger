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
        if let input = line.input, supplierInputs(companyID: companyID).first(where: { $0.id == input })?.governedBy != nil { return false }
        return SupplyNeeds.uses(buyerTrade: co.type, buyerFamily: bd.family, line: l.lineID, supplierTrade: l.tradeID)
    }

    /// Sign a contract with a player's listing for one line. An own-company link on that kind of purchase ends first, as for any other switch.
    @discardableResult
    mutating func signPlayerSupplier(contract: SupplyContract, listing l: SupplyListing, weeklyMarketSpend: Double) -> Bool {
        guard playerSupplyAllowed(companyID: contract.buyerCompanyID, listing: l), let co = state.company(contract.buyerCompanyID), let bd = data.catalog[co.type],
              let line = SupplyCatalogue.lines(co, bd).first(where: { $0.id == contract.lineID }) else { return false }
        if let k = line.input, k != "goods", k != "repair", IntercompanySupply.kind(k) != nil,
           IntercompanySupply.link(state, buyer: co.id, kind: k) != nil || AccountSupply.link(state, buyer: co.id, kind: k) != nil {
            if switchSupplier(companyID: co.id, input: k, to: .outside) != .ok { return false }
        }
        var ok = false
        update { s, d, _ in ok = PlayerSupply.sign(&s, contract: contract, listing: l, weeklyMarketSpend: weeklyMarketSpend, data: d) }
        return ok
    }

    /// The line goes back to the House supplier.
    mutating func endPlayerSupplier(companyID: Int, lineID: String) {
        update { s, _, _ in PlayerSupply.end(&s, buyer: companyID, line: lineID) }
    }

    /// A short delivery the market reported on this listing; the buyers' customers are affected and they are told.
    mutating func reportShortDelivery(listingID: String) {
        update { s, _, _ in _ = PlayerSupply.recordMiss(&s, listingID: listingID) }
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
        guard l.lineID == "goods", units > 0, playerSupplyAllowed(companyID: companyID, listing: l), let basis = stockOrderBasis(companyID: companyID),
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
