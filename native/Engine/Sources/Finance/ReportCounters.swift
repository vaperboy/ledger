import Foundation
import GameCore

public enum ReportCounters {
    static let storeKey = "rptCum"

    public enum Key {
        public static let invested = "p.invested"
        public static let dividends = "p.dividends"
        public static let salary = "p.salary"
        public static let markets = "p.markets"
        public static let deposits = "p.deposits"
        public static let tax = "p.tax"
        public static let loans = "p.loans"
        public static let interest = "p.interest"
        public static let companies = "p.companies"
        public static let other = "p.other"
        public static let answered = "n.answered"
    }

    public static let personalKeys: [String] = [Key.invested, Key.dividends, Key.salary, Key.markets, Key.deposits, Key.tax, Key.loans, Key.interest, Key.companies, Key.other]

    public static func key(forLabel label: String) -> String {
        func has(_ p: String) -> Bool { label.hasPrefix(p) }
        if has("Invested in") { return Key.invested }
        if has("Dividend from") { return Key.dividends }
        if has("Salary from") { return Key.salary }
        if has("Dividend tax") || has("Tax on ") || has("Wealth tax") { return Key.tax }
        if has("Bought ") || has("Sold ") || has("Dividend ") { return Key.markets }
        if has("Fixed deposit") || has("Deposit matured") { return Key.deposits }
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

    static func recordPersonal(_ s: inout GameState, label: String?, amount: Double) {
        add(&s, key(forLabel: label ?? "Other"), amount)
    }
}
