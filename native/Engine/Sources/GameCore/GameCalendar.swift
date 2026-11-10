import Foundation

public enum GameCalendar {
    public static let startDay: Int = daysFromCivil(year: 2026, month: 10, day: 5)

    public static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public struct Date: Equatable, Sendable {
        public var year: Int
        public var month: Int
        public var day: Int
        public var weekday: Int
    }

    public static func date(week: Int, dayOffset: Int = 0) -> Date {
        let d = startDay + week * 7 + dayOffset
        let c = civilFromDays(d)
        let wd = ((d % 7) + 7 + 3) % 7
        return Date(year: c.year, month: c.month - 1, day: c.day, weekday: wd)
    }

    public static func month(week: Int) -> Int { date(week: week).month }
    public static func year(week: Int) -> Int { date(week: week).year }

    public static func monthIndex(week: Int) -> Int {
        let d = date(week: week)
        return d.year * 12 + d.month
    }

    public static func isMonthEnd(week: Int) -> Bool { monthIndex(week: week + 1) != monthIndex(week: week) }
    public static func isYearEnd(week: Int) -> Bool { year(week: week + 1) != year(week: week) }

    public static func isMonthEnd(week: Int, day: Int) -> Bool {
        date(week: week, dayOffset: day + 1).month != date(week: week, dayOffset: day).month
    }
    public static func isYearEnd(week: Int, day: Int) -> Bool {
        date(week: week, dayOffset: day + 1).year != date(week: week, dayOffset: day).year
    }

    public static func slot(ofCompany id: Int) -> Int { ((id % 7) + 7) % 7 }

    public static func cycle(companyID: Int, week: Int, day: Int) -> Int { week - (day < slot(ofCompany: companyID) ? 1 : 0) }

    public static func weeksIntoYear(week: Int) -> Int {
        let day = startDay + week * 7
        let jan1 = daysFromCivil(year: year(week: week), month: 1, day: 1)
        return max(1, (day - jan1) / 7 + 1)
    }

    public static func dateString(week: Int, dayOffset: Int = 0) -> String {
        let d = date(week: week, dayOffset: dayOffset)
        return "\(d.day) \(monthNames[d.month]) \(d.year)"
    }

    public static func monthString(week: Int) -> String {
        let d = date(week: week)
        return "\(monthNames[d.month]) \(d.year)"
    }

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
