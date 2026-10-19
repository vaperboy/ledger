import Foundation

/// Game time. One game week is 7 days; the game starts on Monday 5 October 2026 (original: `START`).
/// Dates are computed with plain calendar arithmetic in UTC, with no time zones or Foundation calendars,
/// so they are identical on every device and in tests.
public enum GameCalendar {
    /// Days from 1970-01-01 to the first game day (2026-10-05).
    public static let startDay: Int = daysFromCivil(year: 2026, month: 10, day: 5)

    public static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public struct Date: Equatable, Sendable {
        public var year: Int
        public var month: Int   // 0...11, like the original's getUTCMonth
        public var day: Int     // 1...31
        public var weekday: Int // 0 = Monday ... 6 = Sunday
    }

    /// Calendar date of the first day of game week `week` plus `dayOffset` days.
    public static func date(week: Int, dayOffset: Int = 0) -> Date {
        let d = startDay + week * 7 + dayOffset
        let c = civilFromDays(d)
        // 1970-01-01 was a Thursday (weekday 3 when Monday = 0).
        let wd = ((d % 7) + 7 + 3) % 7
        return Date(year: c.year, month: c.month - 1, day: c.day, weekday: wd)
    }

    public static func month(week: Int) -> Int { date(week: week).month }
    public static func year(week: Int) -> Int { date(week: week).year }

    /// A counter that grows by one every calendar month. Original: `monthIdx`.
    public static func monthIndex(week: Int) -> Int {
        let d = date(week: week)
        return d.year * 12 + d.month
    }

    /// True when the next game week falls in a new month. Original: `isMonthEnd`.
    public static func isMonthEnd(week: Int) -> Bool { monthIndex(week: week + 1) != monthIndex(week: week) }
    /// Original: `isYearEnd`.
    public static func isYearEnd(week: Int) -> Bool { year(week: week + 1) != year(week: week) }

    /// "5 Oct 2026". Original: `dateStr`.
    public static func dateString(week: Int, dayOffset: Int = 0) -> String {
        let d = date(week: week, dayOffset: dayOffset)
        return "\(d.day) \(monthNames[d.month]) \(d.year)"
    }

    /// "Oct 2026". Original: `monthStr`.
    public static func monthString(week: Int) -> String {
        let d = date(week: week)
        return "\(monthNames[d.month]) \(d.year)"
    }

    // Howard Hinnant's civil-date algorithms (public domain), integer only.
    public static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public static func civilFromDays(_ z0: Int) -> (year: Int, month: Int, day: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}
