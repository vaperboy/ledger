import Foundation

public enum Loans {
    /// Monthly payment that repays `principal` in `months` equal payments at yearly interest `yearlyRate`.
    /// Interest-free loans repay principal / months. Original: `annuity(P, r, n)`.
    public static func annuity(principal P: Double, yearlyRate r: Double, months n: Double) -> Double {
        let i = r / 12
        return i <= 0 ? P / n : P * i / (1 - pow(1 + i, -n))
    }
}
