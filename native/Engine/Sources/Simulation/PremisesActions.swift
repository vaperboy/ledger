import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Premises and fleet extras: a home trade moving into a place of its own, space in your own buildings for a franchise unit,
/// a car per person, own car with mileage.
/// Originals: `ACT.home37`, `fbFreeProps`, `ACT.carallow`, `carOffer`.
public extension GameEngine {
    // MARK: Home trades

    func isHomeTrade(companyID: Int) -> Bool { state.company(companyID).flatMap { data.catalog[$0.type] }.map { PremisesExtras.isHomeTrade($0) } ?? false }
    /// "office", "workshop", ... : what the trade moves into.
    func homeTradePlaceWord(companyID: Int) -> String? { state.company(companyID).flatMap { data.catalog[$0.type] }.map { PremisesExtras.placeWord($0) } }
    func isWorkingFromHome(companyID: Int) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return false }
        return PremisesExtras.isAtHome(co, bd)
    }
    /// Four or more people working out of the kitchen table.
    func hasOutgrownHome(companyID: Int) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return false }
        return PremisesExtras.hasOutgrownHome(co, bd)
    }
    @discardableResult mutating func moveBackHome(companyID: Int) -> Bool {
        var r = false
        update { s, d, _ in r = PremisesExtras.moveBackHome(&s, companyID: companyID, data: d) }
        return r
    }

    // MARK: Your own buildings as the franchise unit's place

    func freeSpaceInYourBuildings(cityID: String, squareMetres: Double) -> [PremisesExtras.FreeSpace] {
        PremisesExtras.freeSpace(state, cityID: cityID, squareMetres: squareMetres)
    }

    // MARK: Cars

    /// Equipment each person needs: the rule and how many the company needs now (nil if the item is not tied to people).
    func personalEquipmentNeed(companyID: Int, equipmentID: String) -> (perText: String, needed: Double)? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], let e = bd.equipment.first(where: { $0.id == equipmentID }),
              let rule = PersonalEquipment.rule(bd, e, tables: data.catalog.tables) else { return nil }
        return (PersonalEquipment.perText(rule, tables: data.catalog.tables), PersonalEquipment.needed(co, bd, e, tables: data.catalog.tables))
    }
    /// Average class of a taxi fleet: 0 economy, 1 comfort, 2 premium.
    func taxiFleetClass(companyID: Int) -> Double { state.company(companyID).map { PersonalEquipment.taxiClass($0) } ?? 0 }
    /// Does this trade let a person use their own car (the hiring screen's work car choice)?
    func offersOwnCar(companyID: Int) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return false }
        return PersonalEquipment.offersOwnCar(co, bd, tables: data.catalog.tables)
    }
    /// Does this job in this trade use a car for work, so the person can use their own car with mileage?
    func offersOwnCar(companyID: Int, role: String) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return false }
        return PersonalEquipment.canUseOwnCar(role: role, bd, tables: data.catalog.tables)
    }
    /// Mileage a month for one person on their own car (country rate times the trade's kilometres, else the game's flat figure).
    func ownCarMileagePerMonth(companyID: Int) -> Double {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return 0 }
        let w = World(state: state, data: data)
        return PersonalEquipment.mileagePerMonth(w.currency(co), country: w.country(co), bd, tables: data.catalog.tables)
    }
}
