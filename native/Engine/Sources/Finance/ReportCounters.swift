import Foundation
import GameCore

/// Running totals that the weekly, monthly and yearly reports take their differences from. Native addition.
///
/// Every movement on the player's private account passes through `Ledger.move` with a label; the label decides which total it
/// is added to. The totals only ever grow (they are never reset), so a report for any period is "total now minus total at the
/// start of the period" and can be checked against the ledger. They live in `GameState.rest["rptCum"]` and travel with the save.
public enum ReportCounters {
    static let storeKey = "rptCum"

    /// Keys of the player's own account. Amounts have the sign they have on the account (money in is positive).
    public enum Key {
        public static let invested = "p.invested"       // money put into your companies
        public static let dividends = "p.dividends"     // dividends from your companies
        public static let salary = "p.salary"           // salary from your companies
        public static let drawings = "p.drawings"       // drawings from a sole trader business
        public static let markets = "p.markets"         // shares, crypto and funds bought and sold, and their dividends
        public static let savings = "p.savings"         // savings and fixed deposits (transfers to and from the account)
        public static let tax = "p.tax"                 // personal income, advance and wealth tax
        public static let loans = "p.loans"             // loans drawn and instalments paid
        public static let interest = "p.interest"       // overdraft interest
        public static let companies = "p.companies"     // founding, selling and winding up companies
        public static let other = "p.other"
        public static let answered = "n.answered"       // decisions the player answered (a count)
    }

    public static let personalKeys: [String] = [Key.invested, Key.dividends, Key.salary, Key.drawings, Key.markets, Key.savings, Key.tax, Key.loans, Key.interest, Key.companies, Key.other]

    /// Which total a statement label belongs to.
    public static func key(forLabel label: String) -> String {
        func has(_ p: String) -> Bool { label.hasPrefix(p) }
        if has("Invested in") { return Key.invested }
        if has("Dividend from") { return Key.dividends }
        if has("Salary from") { return Key.salary }
        if has("Drawing from") { return Key.drawings }
        if has("Bought ") || has("Sold ") || has("Dividend ") { return Key.markets }
        if has("To savings") || has("From savings") || has("Fixed deposit") || has("Deposit matured") || has("Savings emptied") { return Key.savings }
        if has("Annual tax") || has("Advance tax") { return Key.tax }
        if has("Loan ") { return Key.loans }
        if has("Overdraft interest") { return Key.interest }
        if has("Registration of") || has("Share capital") || has("Forced sale") || has("Remaining value") || has("Debts of failed") { return Key.companies }
        return Key.other
    }

    public static func totals(_ s: GameState) -> [String: Double] {
        (s.rest[storeKey] ?? .null).object.mapValues { $0.double }
    }

    public static func add(_ s: inout GameState, _ key: String, _ amount: Double) {
        guard amount != 0 else { return }
        var o = (s.rest[storeKey] ?? .null).object
        o[key] = .number((o[key]?.double ?? 0) + amount)
        s.rest[storeKey] = .object(o)
    }

    /// Called by `Ledger.move` for every line on the player's account.
    static func recordPersonal(_ s: inout GameState, label: String?, amount: Double) {
        add(&s, key(forLabel: label ?? "Other"), amount)
    }
}
