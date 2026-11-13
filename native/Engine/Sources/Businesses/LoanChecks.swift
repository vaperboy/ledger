import Foundation
import GameCore
import Finance

/// The bank rules every company loan made outside the bank screen goes through: nothing new during a bankruptcy ban,
/// nothing on a poor credit score, nothing above the bank's limit, and a personal guarantee for a young or thinly capitalised company.
public enum LoanChecks {
    /// True while banks lend nothing new: during a bankruptcy ban or on a poor credit score.
    public static func lendingBlocked(_ s: GameState) -> Bool { Banking.loanBanUntil(s) != nil || Banking.creditBand(s.credit) == "E" }

    /// Whether a bank lends `amount` to this company. `security` is the resale value of an asset pledged against the loan, which raises the limit.
    public static func approves(_ s: GameState, companyID: Int, amount: Double, security: Double = 0, data: GameData) -> Bool {
        guard amount > 0 else { return true }
        guard !lendingBlocked(s), let co = s.company(companyID), !co.flag("loanFrozen") else { return false }
        let off = Banking.offer(kind: "biz", amount: amount, company: co, state: s, netWorth: Valuation.netWorth(s, trades: data.catalog).total,
                                companyValue: Valuation.companyValue(co, state: s, trades: data.catalog),
                                context: FinanceContext(countries: data.countries, trades: data.catalog))
        return amount <= max(0, off.maximum) + max(0, security)
    }

    /// Whether the owner must personally guarantee a loan of `amount` to this company (same rule as the bank screen).
    public static func needsGuarantee(_ s: GameState, companyID: Int, amount: Double) -> Bool {
        guard let co = s.company(companyID) else { return false }
        return Banking.needsGuarantee(company: co, amount: amount, week: s.week)
    }
}
