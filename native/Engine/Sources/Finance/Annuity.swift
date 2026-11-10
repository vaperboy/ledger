import Foundation

public enum Loans {
    public static func annuity(principal P: Double, yearlyRate r: Double, months n: Double) -> Double {
        let i = r / 12
        return i <= 0 ? P / n : P * i / (1 - pow(1 + i, -n))
    }
}
