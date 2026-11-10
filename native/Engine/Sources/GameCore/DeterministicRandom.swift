import Foundation

public struct DeterministicRandom: Sendable, Equatable {
    public private(set) var state: Int32

    public init(state: Int32) { self.state = state }

    public init(seed: Int) { self.state = Int32(truncatingIfNeeded: seed) }

    public mutating func next() -> Double {
        state = state &+ 0x6D2B79F5
        var t = UInt32(bitPattern: state)
        t = (t ^ (t >> 15)) &* (t | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }

    public mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }

    public mutating func int(_ a: Int, _ b: Int) -> Int {
        Int(saturating: (Double(a) + next() * Double(b - a + 1)).rounded(.down))
    }

    public mutating func chance(_ p: Double) -> Bool { next() < p }

    public mutating func pick<T>(_ items: [T]) -> T {
        items[Int(saturating: (next() * Double(items.count)).rounded(.down))]
    }

    public mutating func gauss() -> Double {
        var u = 0.0, v = 0.0
        while u == 0 { u = next() }
        while v == 0 { v = next() }
        return (-2 * Foundation.log(u)).squareRoot() * Foundation.cos(2 * Double.pi * v)
    }

    public mutating func poisson(_ l: Double) -> Int {
        if l <= 0 { return 0 }
        if l > 30 { return max(0, Int(saturating: jsRound(l + gauss() * l.squareRoot()))) }
        var k = 0
        var p = 1.0
        let e = Foundation.exp(-l)
        repeat {
            k += 1
            p *= next()
        } while p > e
        return k - 1
    }

    public mutating func weightedPick<T>(_ items: [T], weight: (T) -> Double) -> T? {
        let ws = items.map { max(0, weight($0)) }
        let total = ws.reduce(0, +)
        if total <= 0 { return nil }
        var r = next() * total
        for (i, w) in ws.enumerated() {
            r -= w
            if r <= 0 { return items[i] }
        }
        return items.last
    }

    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        var i = a.count - 1
        while i > 0 {
            let j = Int(saturating: (next() * Double(i + 1)).rounded(.down))
            a.swapAt(i, j)
            i -= 1
        }
        return a
    }
}
