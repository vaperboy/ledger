import Foundation
import GameCore
import Finance
import Businesses

/// The finance manager screens. Original: `ACT.fmhire`, `fmmand`, `fmgo`, `fmadd`, `fmwd`, `fmfire` (ui/phone/invest.js) and
/// `ACT.hfin` (features/world/rivals_holdings_software.js). `fmhire` and `fmmand` only open and fill the hire sheet: the mandate
/// is a choice of the screen and arrives with `fmgo` (`hireFinManager`). The crisis centre's `rfset` and `loset` are likewise only
/// the chip choices of the staff screen (`layOffStaff`, `warnStaff`, `layoffPreview` do the work); `layoffCount` turns the layoff chip into a number.
public extension GameEngine {
    /// Your own fund manager, if hired.
    var fundManager: FinanceManager.Account? { FinanceManager.account(state) }

    /// The three candidates (made when first asked for). Original: `genFinManagers`.
    @discardableResult mutating func fundManagerCandidates() -> [FinanceManager.Candidate] {
        var r: [FinanceManager.Candidate] = []
        update { s, d, _ in r = FinanceManager.pool(&s, data: d) }
        return r
    }

    /// Original: `ACT.fmgo` (`hireFinManager`).
    @discardableResult mutating func hireFundManager(personID: Int, mandate: FinanceManager.Mandate, amount: Double) -> FinanceManager.HireResult {
        var r = FinanceManager.HireResult.unknown
        update { s, _, _ in r = FinanceManager.hire(&s, personID: personID, mandate: mandate, amount: amount) }
        return r
    }
    /// Original: `ACT.fmadd`.
    @discardableResult mutating func addToFundManager(_ amount: Double) -> Bool {
        var r = false
        update { s, _, _ in r = FinanceManager.add(&s, amount: amount) }
        return r
    }
    /// Original: `ACT.fmwd`.
    @discardableResult mutating func withdrawFromFundManager(_ amount: Double) -> Bool {
        var r = false
        update { s, _, _ in r = FinanceManager.withdraw(&s, amount: amount) }
        return r
    }
    /// Original: `ACT.fmfire`. A new set of candidates is made next time.
    mutating func dismissFundManager() { update { s, _, _ in FinanceManager.fire(&s) } }

    /// Holdings run by the office finance manager. Original: `finSt().holds`.
    var holdingsRunByFinanceManager: [Int] { FinanceManager.managedHoldings(state) }

    /// Original: `ACT.hfin`. Returns the new state (nil: no finance manager in the main office).
    @discardableResult mutating func toggleHoldingFinanceManager(holdingID: Int) -> Bool? {
        var r: Bool?
        update { s, _, _ in r = FinanceManager.toggleHolding(&s, holdingID: holdingID) }
        return r
    }

    /// The layoff chip of the staff screen: "1", "3" or "10" (10% of the staff, at least one). Original: `layoffCard`, `ACT.loset`.
    func layoffCount(companyID: Int, preset: String) -> Int {
        let n = state.company(companyID)?.staff.count ?? 0
        return preset == "10" ? max(1, Int((Double(n) * 0.1).rounded())) : min(n, Int(preset) ?? 1)
    }
}
