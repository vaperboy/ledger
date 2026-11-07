import Foundation
import GameCore
import Businesses

/// The new-car dealership (trade `cardealer`): showroom stock, ordering, prices and the brand contract. The rules are in `CarDealer` and `CarBrandContract`.
public extension GameEngine {
    /// The cars in the showroom and on order.
    func carDealerRows(companyID: Int) -> [CarDealerRow] {
        state.company(companyID).map { CarDealer.rows($0, week: state.week) } ?? []
    }

    /// Car spaces the premises hold, and how many are taken (cars and orders).
    func carDealerSpaces(companyID: Int) -> (total: Int, used: Int) {
        guard let co = state.company(companyID), let bd = data.catalog[CarDealer.tradeID] else { return (0, 0) }
        return (CarDealer.spaces(co, bd), CarDealer.carsInShowroom(co) + CarDealer.carsOnOrder(co))
    }

    /// What can be ordered now from the current supplier (the distributor, or the contract brand).
    func carDealerOffers(companyID: Int) -> [CarDealerOffer] {
        state.company(companyID).map { CarDealer.offers($0, state, data) } ?? []
    }

    func carDealerSupplier(companyID: Int) -> String { state.company(companyID).map { CarDealer.supplierName($0) } ?? "" }
    func carDealerHasBuyer(companyID: Int) -> Bool { state.company(companyID).map { CarDealer.hasBuyer($0) } ?? false }

    @discardableResult
    mutating func carDealerOrder(companyID: Int, brandID: String, modelID: String) -> SettingResult {
        var why: String?
        update { s, d, _ in why = CarDealer.order(&s, companyID: companyID, brandID: brandID, modelID: modelID, data: d) }
        return why.map { .refused($0) } ?? .applied
    }

    @discardableResult
    mutating func carDealerSetPrice(companyID: Int, carID: Int, price: Double) -> SettingResult {
        var ok = false
        update { s, _, _ in ok = CarDealer.setAsk(&s, companyID: companyID, carID: carID, price: price) }
        return ok ? .applied : .refused("That car cannot be priced like that.")
    }

    // MARK: Brand contract

    /// The brands that sell in the company's country with the terms each would give today.
    func carBrandTerms(companyID: Int) -> [CarBrandContract.Terms] {
        guard let co = state.company(companyID) else { return [] }
        return CarBrands.forCountry(co.countryCode).compactMap { CarBrandContract.terms(brandID: $0.id, co, state, data) }
    }

    func carBrandContract(companyID: Int) -> CarBrandContract.Active? {
        state.company(companyID).flatMap { CarBrandContract.active($0, state, data) }
    }

    @discardableResult
    mutating func carBrandSign(companyID: Int, brandID: String) -> SettingResult {
        var why: String?
        update { s, d, _ in why = CarBrandContract.sign(&s, companyID: companyID, brandID: brandID, data: d) }
        return why.map { .refused($0) } ?? .applied
    }

    @discardableResult
    mutating func carBrandLeave(companyID: Int) -> SettingResult {
        var paid: Double?
        update { s, d, _ in paid = CarBrandContract.exitEarly(&s, companyID: companyID, data: d) }
        return paid == nil ? .refused("There is no contract to leave, or the company cannot pay the penalty.") : .applied
    }

    @discardableResult
    mutating func carBrandRenew(companyID: Int) -> SettingResult {
        var why: String?
        update { s, d, _ in why = CarBrandContract.renew(&s, companyID: companyID, data: d) }
        return why.map { .refused($0) } ?? .applied
    }

    mutating func carBrandDeclineRenewal(companyID: Int) {
        update { s, _, _ in CarBrandContract.declineRenewal(&s, companyID: companyID) }
    }
}
