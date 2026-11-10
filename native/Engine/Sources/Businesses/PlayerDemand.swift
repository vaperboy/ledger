import Foundation
import GameCore

public protocol PlayerCountProvider: Sendable {
    func playerCount(country: String) -> Int
}

public struct StandInPlayerCounts: PlayerCountProvider {
    public var counts: [String: Int]
    public var fallback: Int
    public init(counts: [String: Int] = [:], fallback: Int = PlayerDemand.referenceCount) { self.counts = counts; self.fallback = fallback }
    public func playerCount(country: String) -> Int { counts[country] ?? fallback }
}

public enum PlayerDemand {
    public static let referenceCount = 200
    static let softening = 50.0
    static let exponent = 0.25
    public static let lowest = 0.85
    public static let highest = 1.30

    nonisolated(unsafe) public static var provider: PlayerCountProvider?

    public static func factor(playerCount: Int) -> Double {
        let n = Double(max(0, playerCount))
        let ref = Double(referenceCount)
        let f = pow((n + softening) / (ref + softening), exponent)
        return clamp(f.isFinite ? f : 1, lowest, highest)
    }

    public static func factor(country: String) -> Double {
        guard let p = provider else { return 1 }
        return factor(playerCount: p.playerCount(country: country))
    }
}
