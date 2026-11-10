import GameCore
import Finance

extension Payments {
    @discardableResult
    static func injectCash(_ s: inout GameState, companyID: Int, amount: Double) -> Bool {
        guard s.companyIndex(companyID) != nil else { return false }
        Ledger.move(&s, .me, amount, why: "Test funds")
        return true
    }
}
