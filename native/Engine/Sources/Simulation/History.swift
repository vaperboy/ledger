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
    /// Each live company's own value per day (company id -> series), for the change shown next to it on the Group tab.
    public var perCompany: [Int: [Double]] = [:]
    /// The cash held inside the live companies together, per day (the Group tab's "Group cash").
    public var companyCash: [Double] = []
    /// Net worth at the start of every week, for the long view (up to ten years).
    public var weeklyNetWorth: [Double] = []
    public static let limit = 140
    public static let weekLimit = 520

    public init() {}
    public init(_ v: JSONValue) {
        func arr(_ k: String) -> [Double] { v[k].array.map { $0.double } }
        netWorth = arr("nw"); cash = arr("cash"); invested = arr("inv"); companies = arr("co"); weeklyNetWorth = arr("nwW"); companyCash = arr("coCash")
        for (k, series) in v["coEach"].object { if let id = Int(k) { perCompany[id] = series.array.map { $0.double } } }
    }
    var json: JSONValue {
        .object(["nw": .array(netWorth.map { .number($0) }), "cash": .array(cash.map { .number($0) }),
                 "inv": .array(invested.map { .number($0) }), "co": .array(companies.map { .number($0) }),
                 "nwW": .array(weeklyNetWorth.map { .number($0) }), "coCash": .array(companyCash.map { .number($0) }),
                 "coEach": .object(Dictionary(uniqueKeysWithValues: perCompany.map { (String($0.key), JSONValue.array($0.value.map { .number($0) })) }))])
    }
    mutating func append(_ nw: NetWorth, cash c: Double, newWeek: Bool, companyValues: [Int: Double] = [:], companyCash cc: Double = 0) {
        if newWeek || weeklyNetWorth.isEmpty {
            weeklyNetWorth.append(jsRound(nw.total))
            if weeklyNetWorth.count > Self.weekLimit { weeklyNetWorth.removeFirst() }
        }
        netWorth.append(jsRound(nw.total)); cash.append(jsRound(c)); invested.append(jsRound(nw.investments)); companies.append(jsRound(nw.companies))
        if netWorth.count > Self.limit { netWorth.removeFirst(); cash.removeFirst(); invested.removeFirst(); companies.removeFirst() }
        companyCash.append(jsRound(cc))
        if companyCash.count > Self.limit { companyCash.removeFirst() }
        for (id, v) in companyValues {
            var series = perCompany[id] ?? []
            series.append(jsRound(v))
            if series.count > Self.limit { series.removeFirst(series.count - Self.limit) }
            perCompany[id] = series
        }
        // A company that is gone (sold, closed) keeps no series.
        for id in Array(perCompany.keys) where companyValues[id] == nil { perCompany[id] = nil }
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

    /// The cash held inside the live companies together (holdings excluded: they hold no trading cash of their own).
    var groupCash: Double { state.companies.filter { $0.status.isLive && $0.type != "hold" }.reduce(0) { $0 + $1.cash } }

    /// How the group's company cash moved over the last `days` recorded days.
    func groupCashChange(days: Int) -> (amount: Double, share: Double?)? { DayHistory.change(dayHistory.companyCash, days: days) }

    /// How a company's value moved over the last `days` recorded days (amount and share of the earlier value); nil with under two days of history.
    func companyValueChange(companyID: Int, days: Int) -> (amount: Double, share: Double?)? {
        DayHistory.change(dayHistory.perCompany[companyID] ?? [], days: days)
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
        var values: [Int: Double] = [:]
        for co in state.companies where co.status.isLive { values[co.id] = Valuation.companyValue(co, state: state, trades: data.catalog) }
        h.append(netWorth, cash: state.cash + state.savings, newWeek: state.day == 0, companyValues: values, companyCash: groupCash)
        let json = h.json
        update { s, _, _ in s.rest["dayHist"] = json }
    }
}
