import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    func volumeContracts(companyID: Int) -> [VolumeContracts.Contract] {
        state.company(companyID).map { VolumeContracts.contracts($0, week: state.week) } ?? []
    }
    func contractLoad(companyID: Int) -> (units: Double, capacityShare: Double) {
        guard let co = state.company(companyID) else { return (0, 0) }
        return (VolumeContracts.committedUnits(co), VolumeContracts.capacityShare(co))
    }
    func contractDetail(companyID: Int, contractID: Int) -> VolumeContracts.Detail? {
        VolumeContracts.detail(state, companyID: companyID, contractID: contractID, data: data)
    }
    func bookedOrders(companyID: Int) -> [(customer: String, units: Double, week: Int)] {
        state.company(companyID).map { VolumeContracts.bookedOrders($0, week: state.week) } ?? []
    }
    @discardableResult
    mutating func endContract(companyID: Int, contractID: Int) -> Bool {
        var ok = false
        update { s, d, _ in ok = VolumeContracts.terminate(&s, companyID: companyID, contractID: contractID, data: d) }
        return ok
    }
    @discardableResult
    mutating func signContract(companyID: Int, terms: VolumeContracts.Terms) -> Int? {
        var id: Int?
        update { s, _, _ in id = VolumeContracts.sign(&s, companyID: companyID, terms: terms) }
        return id
    }
}
