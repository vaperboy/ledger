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

    // What a line needs a week, in the units suppliers count capacity in. The player never sets it.
    func playerSupplyNeed(companyID: Int, lineID: String) -> Int {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return 1 }
        return SupplyCatalogue.needUnits(co, bd, line: lineID, costIndex: World(state: state, data: data).country(co).costIndex)
    }

    // Whether a player's listing can meet this company's need on its line.
    func playerSupplyFit(companyID: Int, listing l: SupplyListing, today: Int) -> SupplyFit {
        let need = playerSupplyNeed(companyID: companyID, lineID: l.lineID)
        let mine = PlayerSupply.contract(state, buyer: companyID, line: l.lineID).map { $0.base.listingID == l.id ? $0.base.unitsPerWeek : 0 } ?? 0
        let open = !l.stopped && !l.paused && l.stopsDay == nil && (l.expiresDay.map { today <= $0 } ?? true)
        let free = SupplyGuards.effectiveCapacity(l) - l.committedUnits + mine
        return SupplyFit.of(free: Double(max(0, free)), need: Double(max(need, l.minOrder)), open: open)
    }

    private func ownUnits(_ c: SupplyContract, _ l: SupplyListing) -> Int {
        PlayerSupply.contract(state, buyer: c.buyerCompanyID, line: c.lineID).map { $0.base.listingID == l.id ? $0.base.unitsPerWeek : 0 } ?? 0
    }

    mutating func endPlayerSupplier(companyID: Int, lineID: String) {
        update { s, _, _ in PlayerSupply.end(&s, buyer: companyID, line: lineID) }
    }

    func playerSupplyCancelFee(companyID: Int, lineID: String) -> Double {
        PlayerSupply.contract(state, buyer: companyID, line: lineID).map { PlayerSupply.cancelFee($0) } ?? 0
    }

    @discardableResult
    mutating func cancelPlayerSupplier(companyID: Int, lineID: String, bySupplier: Bool = false) -> SettingResult {
        var why: String?
        update { s, _, _ in why = PlayerSupply.cancel(&s, buyer: companyID, line: lineID, bySupplier: bySupplier) }
        if let why { return .refused(why) }
        return .applied
    }

    func physicalSupplyCapacity(companyID: Int) -> Int? {
        guard let co = state.company(companyID), co.status == .open, let bd = data.catalog[co.type] else { return nil }
        let capacity = CapacityModel.compute(co, bd, World(state: state, data: data)).capacity
        let own = co.value("lastW")["units"].double
        return max(0, Int(saturating: (capacity - own).rounded(.down)))
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
        let capped: [SupplyListing] = listings.map { (l: SupplyListing) -> SupplyListing in
            guard let id = l.companyID, let room = physicalSupplyCapacity(companyID: id) else { return l }
            var x = l
            x.capacityPerWeek = min(l.capacityPerWeek, room)
            x.logoID = companyLogoID(companyID: id)
            return x
        }
        update { s, _, _ in PlayerSupply.saveListings(&s, listings: capped, orders: orders) }
    }

    // The units a one-off stock order brings the shelves back to what the company wants to hold.
    func stockOrderUnits(companyID: Int) -> Int {
        guard let b = stockOrderBasis(companyID: companyID) else { return 0 }
        let target: Double = b.target ?? b.held * 1.5
        return max(1, Int(saturating: (target - b.held).rounded(.up)))
    }

    func stockOrderBasis(companyID: Int) -> StockOrderBasis? {
        guard let co = state.company(companyID), co.status == .open, let bd = data.catalog[co.type], bd.hasTrait("stock"), Suppliers.hasGoods(bd, co) else { return nil }
        let lw = co.value("lastW")
        guard lw["cogs"].double > 0, lw["units"].double > 0 else { return nil }
        return StockOrderBasis(unitCost: lw["cogs"].double / lw["units"].double, held: co.inventory, target: StockHandling.policyTarget(co, bd))
    }

    @discardableResult
    mutating func orderFromSupplier(companyID: Int, listing l: SupplyListing, units: Int) -> Shipments.OrderResult {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], l.lineID == SupplyCatalogue.stockLine(co, bd)?.id, units > 0, !l.stopped, !l.paused,
              l.stopsDay == nil, playerSupplyAllowed(companyID: companyID, listing: l), let basis = stockOrderBasis(companyID: companyID) else { return .badOrder }
        let cargo: TransportCost.Cargo = SupplyLanded.cargo(lineID: l.lineID, supplierTrade: l.tradeID) ?? .standard
        let offer = TransportCost.Offer(id: l.id, country: l.country.isEmpty ? co.countryCode : l.country, unitPrice: basis.unitCost * l.priceFactor)
        var r = Shipments.OrderResult.badOrder
        update { s, d, _ in r = Shipments.order(&s, companyID: companyID, offer: offer, units: Double(units), cargo: cargo, supplierName: l.ownerName, data: d) }
        return r
    }

    func shipmentsOnTheWay(companyID: Int) -> [Shipments.Row] { Shipments.rows(state, companyID: companyID) }

    @discardableResult
    mutating func chooseSalesChannel(companyID: Int, channel: SalesChannel) -> ActionResult {
        var why: String?
        update { s, _, _ in why = SalesChannel.choose(&s, companyID: companyID, channel: channel) }
        return why.map { ActionResult.refused($0) } ?? .done
    }

    mutating func savePlayerDemand(_ posts: [DemandPost]) {
        update { s, _, _ in SalesChannel.saveDemandPosts(&s, posts) }
    }

    var playerDemandPosts: [DemandPost] { SalesChannel.demandPosts(state) }
}
