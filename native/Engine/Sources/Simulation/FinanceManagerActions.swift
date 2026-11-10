import Foundation
import GameCore
import Finance
import Businesses

public extension GameEngine {
    var fundManager: FinanceManager.Account? { FinanceManager.account(state) }

    @discardableResult mutating func fundManagerCandidates() -> [FinanceManager.Candidate] {
        var r: [FinanceManager.Candidate] = []
        update { s, d, _ in r = FinanceManager.pool(&s, data: d) }
        return r
    }

    @discardableResult mutating func hireFundManager(personID: Int, mandate: FinanceManager.Mandate, amount: Double) -> FinanceManager.HireResult {
        var r = FinanceManager.HireResult.unknown
        update { s, _, _ in r = FinanceManager.hire(&s, personID: personID, mandate: mandate, amount: amount) }
        return r
    }
    @discardableResult mutating func addToFundManager(_ amount: Double) -> Bool {
        var r = false
        update { s, _, _ in r = FinanceManager.add(&s, amount: amount) }
        return r
    }
    @discardableResult mutating func withdrawFromFundManager(_ amount: Double) -> Bool {
        var r = false
        update { s, _, _ in r = FinanceManager.withdraw(&s, amount: amount) }
        return r
    }
    @discardableResult
    mutating func dismissFundManager() -> Bool { var ok = false; update { s, _, _ in ok = FinanceManager.fire(&s) }; return ok }

    func layoffCount(companyID: Int, preset: String) -> Int {
        let n = state.company(companyID)?.staff.count ?? 0
        return preset == "10" ? max(1, Int(saturating: (Double(n) * 0.1).rounded())) : min(n, Int(preset) ?? 1)
    }
}
