import Foundation
import GameCore

/// Where the number of real players in a country comes from. The server supplies it; until then `StandInPlayerCounts` stands in.
public protocol PlayerCountProvider: Sendable {
    func playerCount(country: String) -> Int
}

/// A fixed stand-in: a count per country, with a default for the rest.
public struct StandInPlayerCounts: PlayerCountProvider {
    public var counts: [String: Int]
    public var fallback: Int
    public init(counts: [String: Int] = [:], fallback: Int = PlayerDemand.referenceCount) { self.counts = counts; self.fallback = fallback }
    public func playerCount(country: String) -> Int { counts[country] ?? fallback }
}

/// Country demand driven by how many real players are there. The effect is a gentle, bounded multiplier on customers, so an empty
/// country or a huge one cannot break the economy.
public enum PlayerDemand {
    /// The player count that gives no change.
    public static let referenceCount = 200
    /// Softens small counts: a country with 0 players is not dead, and 1 player is not a boom.
    static let softening = 50.0
    static let exponent = 0.25
    public static let lowest = 0.85
    public static let highest = 1.30

    /// The provider in use. Nil means no effect (the factor is 1 everywhere).
    nonisolated(unsafe) public static var provider: PlayerCountProvider?

    /// Multiplier on customers for a player count. Monotonic, bounded to `lowest...highest`, 1 at the reference count.
    public static func factor(playerCount: Int) -> Double {
        let n = Double(max(0, playerCount))
        let ref = Double(referenceCount)
        let f = pow((n + softening) / (ref + softening), exponent)
        return clamp(f.isFinite ? f : 1, lowest, highest)
    }

    /// The factor for a country from the provider in use (1 without one).
    public static func factor(country: String) -> Double {
        guard let p = provider else { return 1 }
        return factor(playerCount: p.playerCount(country: country))
    }
}
