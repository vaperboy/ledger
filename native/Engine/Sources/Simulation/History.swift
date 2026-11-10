import Foundation
import GameCore
import Finance
import Businesses

public struct DayHistory: Equatable, Sendable {
    public var netWorth: [Double] = []
    public var cash: [Double] = []
    public var invested: [Double] = []
    public var companies: [Double] = []
    public var perCompany: [Int: [Double]] = [:]
    public var companyCash: [Double] = []
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
                 "coEach": .object(Dictionary(perCompany.map { (String($0.key), JSONValue.array($0.value.map { .number($0) })) }, uniquingKeysWith: { (a, _) in a }))])
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
        for id in Array(perCompany.keys) where companyValues[id] == nil { perCompany[id] = nil }
    }

    public static func change(_ series: [Double], days: Int) -> (amount: Double, share: Double?)? {
        guard series.count >= 2, let last = series.last else { return nil }
        let ref = series[max(0, series.count - 1 - days)]
        let d = last - ref
        return (d, abs(ref) > 1 ? d / abs(ref) : nil)
    }
}

public extension GameEngine {
    var dayHistory: DayHistory { DayHistory(state.rest["dayHist"] ?? .null) }

    mutating func resetHistory() {
        update { s, _, _ in s.rest["dayHist"] = nil }
        recordDay()
    }

    var groupCash: Double { state.companies.filter { $0.status.isLive && $0.type != "hold" }.reduce(0) { $0 + $1.cash } }

    func groupCashChange(days: Int) -> (amount: Double, share: Double?)? { DayHistory.change(dayHistory.companyCash, days: days) }

    func companyValueChange(companyID: Int, days: Int) -> (amount: Double, share: Double?)? {
        DayHistory.change(dayHistory.perCompany[companyID] ?? [], days: days)
    }

    func netWorthSeries(days: Int) -> [Double] {
        let h = dayHistory
        if days <= h.netWorth.count || h.weeklyNetWorth.count < 3 { return Array(h.netWorth.suffix(days)) }
        return Array(h.weeklyNetWorth.suffix(max(2, days / 7))) + [h.netWorth.last ?? 0]
    }

    mutating func recordDay() {
        var h = dayHistory
        var values: [Int: Double] = [:]
        for co in state.companies where co.status.isLive { values[co.id] = Valuation.companyValue(co, state: state, trades: data.catalog) }
        h.append(netWorth, cash: state.cash, newWeek: state.day == 0, companyValues: values, companyCash: groupCash)
        let json = h.json
        update { s, _, _ in s.rest["dayHist"] = json }
    }
}
