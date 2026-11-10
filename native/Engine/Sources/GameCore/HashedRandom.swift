import Foundation

public struct HashedRandom: Sendable {
    private var h: UInt32

    public init(_ text: String) {
        var hash: UInt32 = 2166136261
        for unit in text.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16777619
        }
        h = hash
    }

    public mutating func next() -> Double {
        h = h &+ 0x6D2B79F5
        var t = (h ^ (h >> 15)) &* (h | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }

    public static func first(_ text: String) -> Double {
        var r = HashedRandom(text)
        return r.next()
    }
}
