import Foundation
import GameCore
import Finance
import Businesses

/// Daily history for the dashboard's change indicators and sparklines. Real numbers, recorded once per day;
/// stored under `rest["dayHist"]`, so it travels with the save. Native addition (the original only kept weekly net worth).
public struct DayHistory: Equatable, Sendable {
    public var netWorth: [Double] = []
    public var cash: [Double] = []
    public var invested: [Double] = []
    public var companies: [Double] = []
    /// Net worth at the start of every week, for the long view (up to ten years).
    public var weeklyNetWorth: [Double] = []
    public static let limit = 140
    public static let weekLimit = 520

    public init() {}
    public init(_ v: JSONValue) {
        func arr(_ k: String) -> [Double] { v[k].array.map { $0.double } }
        netWorth = arr("nw"); cash = arr("cash"); invested = arr("inv"); companies = arr("co"); weeklyNetWorth = arr("nwW")
    }
    var json: JSONValue {
        .object(["nw": .array(netWorth.map { .number($0) }), "cash": .array(cash.map { .number($0) }),
                 "inv": .array(invested.map { .number($0) }), "co": .array(companies.map { .number($0) }),
                 "nwW": .array(weeklyNetWorth.map { .number($0) })])
    }
    mutating func append(_ nw: NetWorth, cash c: Double, newWeek: Bool) {
        if newWeek || weeklyNetWorth.isEmpty {
            weeklyNetWorth.append(jsRound(nw.total))
            if weeklyNetWorth.count > Self.weekLimit { weeklyNetWorth.removeFirst() }
        }
        netWorth.append(jsRound(nw.total)); cash.append(jsRound(c)); invested.append(jsRound(nw.investments)); companies.append(jsRound(nw.companies))
        if netWorth.count > Self.limit { netWorth.removeFirst(); cash.removeFirst(); invested.removeFirst(); companies.removeFirst() }
    }

    /// Change between now and `days` entries ago (or the oldest entry), as an amount and as a share of the earlier value.
    public static func change(_ series: [Double], days: Int) -> (amount: Double, share: Double?)? {
        guard series.count >= 2, let last = series.last else { return nil }
        let ref = series[max(0, series.count - 1 - days)]
        let d = last - ref
        return (d, abs(ref) > 1 ? d / abs(ref) : nil)
    }
}

public extension GameEngine {
    var dayHistory: DayHistory { DayHistory(state.rest["dayHist"] ?? .null) }

    /// Forget the recorded history (used when a demo game is set up, so its charts do not start with the set-up money).
    mutating func resetHistory() {
        update { s, _, _ in s.rest["dayHist"] = nil }
        recordDay()
    }

    /// Net worth for a chart over the last `days` days: daily figures while they reach back that far, weekly ones beyond.
    func netWorthSeries(days: Int) -> [Double] {
        let h = dayHistory
        if days <= h.netWorth.count || h.weeklyNetWorth.count < 3 { return Array(h.netWorth.suffix(days)) }
        return Array(h.weeklyNetWorth.suffix(max(2, days / 7))) + [h.netWorth.last ?? 0]
    }

    /// Record today's figures. Called after each day.
    mutating func recordDay() {
        var h = dayHistory
        h.append(netWorth, cash: state.cash + state.savings, newWeek: state.day == 0)
        let json = h.json
        update { s, _, _ in s.rest["dayHist"] = json }
    }
}
