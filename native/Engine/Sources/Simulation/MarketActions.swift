import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// What the player can do on the equipment market, with premises, and in the Aurum luxury shop; and what those screens read.
/// Originals: the shop actions of features/company/realistic_buying.js (`shopbuy`, `subpick`, `sellunit`, `sellveh`, `selleq`,
/// `repaireq`, `premsheet`), and the Aurum actions (`luxbuygo`, `luxsell`, `lx56*`, `est56*`).
public extension GameEngine {
    // MARK: Premises

    func premisesListings(companyID: Int) -> [CompanySetup.Listing] {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return [] }
        return CompanySetup.listings(for: co, bd, World(state: state, data: data))
    }

    func premisesTerms(companyID: Int, listing: CompanySetup.Listing) -> CompanySetup.PremisesTerms? {
        guard let co = state.company(companyID) else { return nil }
        return CompanySetup.premisesTerms(co, listing, data: data, world: World(state: state, data: data))
    }

    /// Rent (or buy with a commercial mortgage) the listing, leaving the place the company is in now.
    @discardableResult
    mutating func takePremises(companyID: Int, listing: CompanySetup.Listing, buy: Bool = false) -> CompanySetup.PremisesResult {
        var r = CompanySetup.PremisesResult.bad
        update { s, d, _ in r = CompanySetup.setPremises(&s, companyID: companyID, listing: listing, buy: buy, data: d) }
        return r
    }

    // MARK: Equipment market

    func equipmentNeeds(companyID: Int) -> [EquipmentMarket.Need] { EquipmentMarket.needs(state, companyID: companyID, data: data) }
    func equipmentOffers(companyID: Int, equipmentID: String) -> [EquipmentMarket.Offer] { EquipmentMarket.offers(state, companyID: companyID, equipmentID: equipmentID, data: data) }
    func vehicleOffers(companyID: Int, equipmentID: String) -> [EquipmentMarket.VehicleOffer] { EquipmentMarket.vehicleOffers(state, companyID: companyID, equipmentID: equipmentID, data: data) }
    func usedListings(companyID: Int, equipmentID: String) -> [EquipmentMarket.UsedOffer] {
        let veh = state.company(companyID).flatMap { data.catalog[$0.type] }?.equipment.first { $0.id == equipmentID }?.vehicleModels != nil
        return veh ? EquipmentMarket.usedVehicles(state, companyID: companyID, equipmentID: equipmentID, data: data)
                   : EquipmentMarket.usedEquipment(state, companyID: companyID, equipmentID: equipmentID, data: data)
    }
    func ownedEquipment(companyID: Int) -> [EquipmentMarket.Owned] { EquipmentMarket.owned(state, companyID: companyID, data: data) }
    func equipmentHealth(companyID: Int) -> Double? { state.company(companyID).flatMap { EquipmentMarket.health($0) } }

    /// Price of one item of the offer, today (a vehicle: of the make and model).
    func equipmentPrice(companyID: Int, equipmentID: String, factor: Double, vendorID: String? = nil) -> Double {
        guard let co = state.company(companyID), let e = data.catalog[co.type]?.equipment.first(where: { $0.id == equipmentID }) else { return 0 }
        return EquipmentMarket.price(e, company: co, World(state: state, data: data), factor: factor, vendor: vendorID)
    }
    func vehiclePrice(modelID: String, factor: Double) -> Double {
        data.catalog.tables.vehicles[modelID].map { EquipmentMarket.vehiclePrice($0, factor: factor, World(state: state, data: data)) } ?? 0
    }
    func subscriptionPlans(companyID: Int, equipmentID: String, offer: EquipmentMarket.Offer) -> [EquipmentMarket.Plan] {
        guard let co = state.company(companyID), let e = data.catalog[co.type]?.equipment.first(where: { $0.id == equipmentID }) else { return [] }
        return EquipmentMarket.plans(e, company: co, World(state: state, data: data), factor: offer.priceFactor)
    }
    func softwareMode(companyID: Int, equipmentID: String) -> EquipmentMarket.SoftwareMode {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], let e = bd.equipment.first(where: { $0.id == equipmentID }) else { return .once }
        return EquipmentMarket.softwareMode(e, tradeID: bd.id, company: co, World(state: state, data: data))
    }
    func canFinance(companyID: Int, equipmentID: String, total: Double) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], let e = bd.equipment.first(where: { $0.id == equipmentID }) else { return false }
        return EquipmentMarket.canFinance(e, tradeID: bd.id, total: total, company: co, World(state: state, data: data), tables: data.catalog.tables)
    }

    @discardableResult
    mutating func buyEquipmentItem(companyID: Int, equipmentID: String, offer: EquipmentMarket.Offer, quantity: Int, payment: EquipmentMarket.Payment) -> EquipmentMarket.Result {
        var r = EquipmentMarket.Result.notPossible
        update { s, d, _ in r = EquipmentMarket.buyNew(&s, companyID: companyID, equipmentID: equipmentID, offer: offer, quantity: quantity, payment: payment, data: d) }
        return r
    }
    @discardableResult
    mutating func buyVehicleItem(companyID: Int, equipmentID: String, offer: EquipmentMarket.VehicleOffer, payment: EquipmentMarket.Payment) -> EquipmentMarket.Result {
        var r = EquipmentMarket.Result.notPossible
        update { s, d, _ in r = EquipmentMarket.buyNewVehicle(&s, companyID: companyID, equipmentID: equipmentID, offer: offer, payment: payment, data: d) }
        return r
    }
    @discardableResult
    mutating func buyUsedItem(companyID: Int, equipmentID: String, listing: EquipmentMarket.UsedOffer, payment: EquipmentMarket.Payment) -> EquipmentMarket.Result {
        var r = EquipmentMarket.Result.notPossible
        update { s, d, _ in r = EquipmentMarket.buyUsed(&s, companyID: companyID, equipmentID: equipmentID, listing: listing, payment: payment, data: d) }
        return r
    }
    @discardableResult
    mutating func subscribeSoftware(companyID: Int, equipmentID: String, plan: Int, offer: EquipmentMarket.Offer?) -> EquipmentMarket.Result {
        var r = EquipmentMarket.Result.notPossible
        update { s, d, _ in r = EquipmentMarket.subscribe(&s, companyID: companyID, equipmentID: equipmentID, plan: plan, offer: offer, data: d) }
        return r
    }
    mutating func cancelSubscription(companyID: Int, equipmentID: String) { update { s, _, _ in EquipmentMarket.cancelSubscription(&s, companyID: companyID, equipmentID: equipmentID) } }
    @discardableResult
    mutating func sellEquipmentUnit(companyID: Int, equipmentID: String, unitID: Int) -> Double {
        var v = 0.0
        update { s, _, _ in v = EquipmentMarket.sellUnit(&s, companyID: companyID, equipmentID: equipmentID, unitID: unitID) }
        return v
    }
    @discardableResult
    mutating func sellAllEquipment(companyID: Int, equipmentID: String) -> Double {
        var v = 0.0
        update { s, _, _ in v = EquipmentMarket.sellAll(&s, companyID: companyID, equipmentID: equipmentID) }
        return v
    }
    @discardableResult
    mutating func sellVehicle(companyID: Int, vehicleID: Int) -> Double {
        var v = 0.0
        update { s, _, _ in v = EquipmentMarket.sellVehicle(&s, companyID: companyID, vehicleID: vehicleID) }
        return v
    }
    mutating func endEquipmentLease(companyID: Int, equipmentID: String) { update { s, _, _ in EquipmentMarket.endLease(&s, companyID: companyID, equipmentID: equipmentID) } }
    @discardableResult
    mutating func serviceEquipment(companyID: Int, equipmentID: String) -> EquipmentMarket.Result {
        var r = EquipmentMarket.Result.notPossible
        update { s, d, _ in r = EquipmentMarket.serviceAll(&s, companyID: companyID, equipmentID: equipmentID, data: d) }
        return r
    }

    // MARK: Luxury

    var luxuryPieces: [Luxury.Piece] { Luxury.pieces(state) }
    var luxuryValue: Double { Luxury.personalValue(state) }
    func luxuryCompanies(itemID: String) -> [Company] { Luxury.companiesThatCanBuy(state, itemID: itemID) }

    @discardableResult
    mutating func buyLuxury(itemID: String) -> Luxury.Result {
        var r = Luxury.Result.unknownItem
        update { s, _, _ in r = Luxury.buy(&s, itemID: itemID) }
        return r
    }
    @discardableResult
    mutating func buyLuxury(itemID: String, throughCompany companyID: Int) -> Luxury.Result {
        var r = Luxury.Result.notPossible
        update { s, _, _ in r = Luxury.buyThroughCompany(&s, itemID: itemID, companyID: companyID) }
        return r
    }
    @discardableResult
    mutating func sellLuxury(pieceID: Int) -> Double {
        var v = 0.0
        update { s, _, _ in v = Luxury.sell(&s, pieceID: pieceID) }
        return v
    }
    mutating func setLuxuryUse(pieceID: Int, use: String?) { update { s, _, _ in Luxury.setUse(&s, pieceID: pieceID, use: use) } }
    mutating func setCastleOpen(pieceID: Int, open: Bool) { update { s, _, _ in Luxury.setCastleMode(&s, pieceID: pieceID, open: open) } }
    @discardableResult
    mutating func hostIslandRetreat() -> Luxury.EstateResult {
        var r = Luxury.EstateResult.none
        update { s, _, ctx in r = Luxury.hostRetreat(&s, currency: ctx.homeCurrency(s)) }
        return r
    }
    @discardableResult
    mutating func takeWeekOffOnIsland() -> Luxury.EstateResult {
        var r = Luxury.EstateResult.none
        update { s, _, _ in r = Luxury.takeWeekOff(&s) }
        return r
    }
}
