import Foundation
import GameCore

public enum FriendTies {
    public static let discount = 0.03
    public static let pickWeight = 1.6

    public static var discountPercent: Int { Int(saturating: (discount * 100).rounded()) }

    public static func price(_ factor: Double, friend: Bool) -> Double { friend ? factor * (1 - discount) : factor }

    public static func weight(_ base: Double, friend: Bool) -> Double { friend ? base * pickWeight : base }

    public static func tag(friend: Bool) -> String? { friend ? "Friend, \(discountPercent)% off" : nil }
}
