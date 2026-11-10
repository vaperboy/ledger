import Foundation

@inlinable public func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

@inlinable public func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { x < a ? a : (x > b ? b : x) }

@inlinable public func roundTo(_ x: Double, step: Double = 1) -> Double { jsRound(x / step) * step }

@inlinable public func sum<T>(_ items: [T], _ f: (T) -> Double) -> Double {
    var t = 0.0
    for i in items { t += f(i) }
    return t
}

extension Double {
    public var finiteOrZero: Double { isFinite ? self : 0 }
}

extension Int {
    public init(saturating d: Double) {
        if d.isNaN { self = 0 }
        else if d >= 9.2e18 { self = Int.max }
        else if d <= -9.2e18 { self = Int.min }
        else { self = Int(d) }
    }
    public init(saturating d: CGFloat) { self.init(saturating: Double(d)) }
    public init(saturating d: Float) { self.init(saturating: Double(d)) }
}
