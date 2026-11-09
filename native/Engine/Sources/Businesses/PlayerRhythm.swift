import Foundation
import Countries

/// When a player is awake and how quickly they answer. Computer players use the same rhythm as everyone else: they reply after minutes or
/// hours, only inside their own waking hours, never at once. Pure and deterministic from the player's id, so tests and every device agree.
public enum PlayerRhythm {
    public struct Profile: Equatable, Sendable {
        /// Local hours (0...24) between which the player answers.
        public var startHour: Int, endHour: Int
        /// Shortest and longest wait before they look at a request, in seconds.
        public var minDelay: Int, maxDelay: Int
    }

    /// Hours from UTC for a country (standard time, from the country data).
    static func utcOffset(_ countryCode: String) -> Int { CountryTraits.utcOffset(countryCode) }

    static func hash(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    public static func profile(id: String) -> Profile {
        let h = hash("rhythm:" + id)
        let start = 7 + Int(h % 4)                 // wakes between 07 and 10
        let end = 21 + Int((h >> 8) % 3)           // answers until 21 to 23
        let quick = Int((h >> 16) % 3)             // some answer within the hour, some take most of a day
        let minDelay = [10, 25, 45][quick] * 60
        let maxDelay = [3, 7, 11][quick] * 3600
        return Profile(startHour: start, endHour: end, minDelay: minDelay, maxDelay: maxDelay)
    }

    /// When a player answers a request sent at `sentAt`: after their own delay, moved to the next time they are awake.
    public static func replyTime(id: String, countryCode: String, sentAt: Date) -> Date {
        let p = profile(id: id)
        let h = hash("reply:" + id + ":" + String(Int(sentAt.timeIntervalSince1970 / 60)))
        let span = max(1, p.maxDelay - p.minDelay)
        let offset = utcOffset(countryCode) * 3600
        var local = Int(sentAt.timeIntervalSince1970) + p.minDelay + Int(h % UInt64(span)) + offset
        let day = Int((Double(local) / 86400).rounded(.down)) * 86400
        let second = local - day
        let jitter = Int((h >> 20) % 2400)        // up to 40 minutes after waking
        if second < p.startHour * 3600 { local = day + p.startHour * 3600 + jitter }
        else if second >= p.endHour * 3600 { local = day + 86400 + p.startHour * 3600 + jitter }
        return Date(timeIntervalSince1970: TimeInterval(local - offset))
    }
}
