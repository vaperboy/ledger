import Foundation
import GameCore

public struct SeasonDef: Equatable, Sendable, Identifiable {
    public var number: Int
    public var name: String
    public var theme: String
    public var founderEdition: Bool
    public var months: Int
    public var rewards: [SeasonReward]
    public var id: Int { number }
    public var days: Int { SeasonCatalog.days(months: months) }
}

public enum SeasonCatalog {
    public static let monthsPerSeason = 6
    public static let maxSeasons = 60

    public static func days(months: Int) -> Int { months * 365 / 12 }

    public static let all: [SeasonDef] = {
        var out: [SeasonDef] = []
        for n in 1...maxSeasons {
            let f: JSONValue = ContentFile.load("season", "season_\(n)")
            if f.isNull { break }
            let theme: String = ItemThemes.id(f)
            let founder: Bool = f["founderEdition"].bool
            let rewards: [SeasonReward] = f["rewards"].array.map { (e: JSONValue) -> SeasonReward in SeasonRewards.parse(e, season: n, theme: theme, founder: founder) }
            out.append(SeasonDef(number: n, name: f["name"].string, theme: theme, founderEdition: founder,
                                 months: f["months"].isNull ? monthsPerSeason : f["months"].int, rewards: rewards))
        }
        return out
    }()

    public static func eraDay(year: Int, month: Int, day: Int) -> Int {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return 0 }
        return cal.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    public static func eraDay(_ iso: String) -> Int? {
        let parts: [Int] = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return eraDay(year: parts[0], month: parts[1], day: parts[2])
    }

    public static let firstSeasonStart: Int? = eraDay(ContentFile.load("season", "season_1")["starts"].string)

    public static func startDay(of number: Int) -> Int? {
        guard let first = firstSeasonStart, number >= 1 else { return nil }
        return first + (number - 1) * SeasonPass.seasonDays
    }

    public static func number(onDay day: Int) -> Int? {
        guard let first = firstSeasonStart else { return nil }
        return max(1, (day - first) / SeasonPass.seasonDays + 1)
    }

    public static func def(_ number: Int) -> SeasonDef? { all.first { $0.number == number } }

    public static func active(_ number: Int) -> SeasonDef? {
        def(number) ?? all.last { !$0.founderEdition } ?? all.last
    }

    public static func season(ofReward id: String) -> SeasonDef? { all.first { s in s.rewards.contains { $0.id == id } } }
}
