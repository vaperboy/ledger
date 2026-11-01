import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Volume contracts with business customers (the "Contracts and bookings" list and the contract page of the original, `ct56`).
/// New offers arrive in the inbox (action `ctv`, answered with `answer(messageID:option:)`); a manager decides by himself.
public extension GameEngine {
    func volumeContracts(companyID: Int) -> [VolumeContracts.Contract] {
        state.company(companyID).map { VolumeContracts.contracts($0, week: state.week) } ?? []
    }
    /// Units a week the contracts take, and their share of last week's capacity.
    func contractLoad(companyID: Int) -> (units: Double, capacityShare: Double) {
        guard let co = state.company(companyID) else { return (0, 0) }
        return (VolumeContracts.committedUnits(co), VolumeContracts.capacityShare(co))
    }
    func contractDetail(companyID: Int, contractID: Int) -> VolumeContracts.Detail? {
        VolumeContracts.detail(state, companyID: companyID, contractID: contractID, data: data)
    }
    /// One-off orders from companies that are booked from this week on.
    func bookedOrders(companyID: Int) -> [(customer: String, units: Double, week: Int)] {
        state.company(companyID).map { VolumeContracts.bookedOrders($0, week: state.week) } ?? []
    }
    /// End a contract early (a penalty of 10 % of four weeks' business and a small blow to the name).
    @discardableResult
    mutating func endContract(companyID: Int, contractID: Int) -> Bool {
        var ok = false
        update { s, d, _ in ok = VolumeContracts.terminate(&s, companyID: companyID, contractID: contractID, data: d) }
        return ok
    }
    /// Sign a contract directly (for example one won in a tender). Returns its id.
    @discardableResult
    mutating func signContract(companyID: Int, terms: VolumeContracts.Terms) -> Int? {
        var id: Int?
        update { s, _, _ in id = VolumeContracts.sign(&s, companyID: companyID, terms: terms) }
        return id
    }
}
