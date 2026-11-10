import Foundation
import GameCore
import Countries

public enum PriceInput {
    public struct Result: Equatable, Sendable {
        public var value: Double
        public var clamped: Bool
        public init(value: Double, clamped: Bool) { self.value = value; self.clamped = clamped }
    }

    public static func parse(_ text: String, currency cur: Currency, range: ClosedRange<Double>) -> Result? {
        let t = text.filter { !$0.isWhitespace && $0 != "\u{00A0}" }.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite, v > 0 else { return nil }
        let units = v * cur.rate
        let c = clamp(units, range.lowerBound, range.upperBound)
        return Result(value: c, clamped: abs(c - units) > 1e-9)
    }

    public static func text(_ price: Double, currency cur: Currency) -> String {
        let v = price / cur.rate
        return abs(v - v.rounded()) < 0.005 ? String(Int(saturating: v.rounded())) : String(format: "%.2f", v)
    }
}
