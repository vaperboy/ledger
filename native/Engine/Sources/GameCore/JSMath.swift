import Foundation

// Small numeric helpers that behave exactly like their JavaScript originals, so the Swift game and the
// HTML game agree to the last digit. Swift's own `.rounded()` differs from JavaScript for halves of negative numbers.

/// JavaScript `Math.round`: halves round up (toward +infinity), so -2.5 becomes -2 and 2.5 becomes 3.
@inlinable public func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

/// Original: `clamp(x, a, b)`.
@inlinable public func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { x < a ? a : (x > b ? b : x) }

/// Original: `rnd(x, step)`: round to the nearest multiple of `step`.
@inlinable public func roundTo(_ x: Double, step: Double = 1) -> Double { jsRound(x / step) * step }

/// Original: `sum(array, fn)`.
@inlinable public func sum<T>(_ items: [T], _ f: (T) -> Double) -> Double {
    var t = 0.0
    for i in items { t += f(i) }
    return t
}

extension Double {
    /// A finite number or zero. Original code guards against NaN in many places (`isFinite`).
    public var finiteOrZero: Double { isFinite ? self : 0 }
}
