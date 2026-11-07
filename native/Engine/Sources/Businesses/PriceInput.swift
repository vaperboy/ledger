import Foundation
import GameCore
import Countries

/// A price typed in the trade's own unit (an hour, a piece, a night) in the country's currency, turned into the accounting unit and held
/// inside the range the page allows. The sliders use the same range, so typing and sliding always agree.
public enum PriceInput {
    public struct Result: Equatable, Sendable {
        public var value: Double
        /// The typed number was outside the range and was moved to its edge.
        public var clamped: Bool
        public init(value: Double, clamped: Bool) { self.value = value; self.clamped = clamped }
    }

    /// nil when the text is not a positive number. Accepts "12.50", "12,50" and spaces as thousands separators.
    public static func parse(_ text: String, currency cur: Currency, range: ClosedRange<Double>) -> Result? {
        let t = text.filter { !$0.isWhitespace && $0 != "\u{00A0}" }.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite, v > 0 else { return nil }
        let units = v * cur.rate
        let c = clamp(units, range.lowerBound, range.upperBound)
        return Result(value: c, clamped: abs(c - units) > 1e-9)
    }

    /// The number to show in the field: the price in the country's currency, two decimals only when it has cents.
    public static func text(_ price: Double, currency cur: Currency) -> String {
        let v = price / cur.rate
        return abs(v - v.rounded()) < 0.005 ? String(Int(v.rounded())) : String(format: "%.2f", v)
    }
}
