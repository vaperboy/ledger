import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {

    func isHomeTrade(companyID: Int) -> Bool { state.company(companyID).flatMap { data.catalog[$0.type] }.map { PremisesExtras.isHomeTrade($0) } ?? false }
    func homeTradePlaceWord(companyID: Int) -> String? { state.company(companyID).flatMap { data.catalog[$0.type] }.map { PremisesExtras.placeWord($0) } }
    func isWorkingFromHome(companyID: Int) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return false }
        return PremisesExtras.isAtHome(co, bd)
    }
    func hasOutgrownHome(companyID: Int) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return false }
        return PremisesExtras.hasOutgrownHome(co, bd)
    }

    func freeSpaceInYourBuildings(cityID: String, squareMetres: Double) -> [PremisesExtras.FreeSpace] {
        PremisesExtras.freeSpace(state, cityID: cityID, squareMetres: squareMetres)
    }

    func personalEquipmentNeed(companyID: Int, equipmentID: String) -> (perText: String, needed: Double)? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], let e = bd.allEquipment.first(where: { $0.id == equipmentID }),
              let rule = PersonalEquipment.rule(bd, e, tables: data.catalog.tables) else { return nil }
        return (PersonalEquipment.perText(rule, tables: data.catalog.tables), PersonalEquipment.needed(co, bd, e, tables: data.catalog.tables))
    }
    func taxiFleetClass(companyID: Int) -> Double { state.company(companyID).map { PersonalEquipment.taxiClass($0) } ?? 0 }
    func offersOwnCar(companyID: Int) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return false }
        return PersonalEquipment.offersOwnCar(co, bd, tables: data.catalog.tables)
    }
    func offersOwnCar(companyID: Int, role: String) -> Bool {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return false }
        return PersonalEquipment.canUseOwnCar(role: role, bd, tables: data.catalog.tables)
    }
    func ownCarMileagePerMonth(companyID: Int) -> Double {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return 0 }
        let w = World(state: state, data: data)
        return PersonalEquipment.mileagePerMonth(w.currency(co), country: w.country(co), bd, tables: data.catalog.tables)
    }
}
