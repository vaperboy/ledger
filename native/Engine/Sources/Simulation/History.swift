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
    public static let limit = 140

    public init() {}
    public init(_ v: JSONValue) {
        func arr(_ k: String) -> [Double] { v[k].array.map { $0.double } }
        netWorth = arr("nw"); cash = arr("cash"); invested = arr("inv"); companies = arr("co")
    }
    var json: JSONValue {
        .object(["nw": .array(netWorth.map { .number($0) }), "cash": .array(cash.map { .number($0) }),
                 "inv": .array(invested.map { .number($0) }), "co": .array(companies.map { .number($0) })])
    }
    mutating func append(_ nw: NetWorth, cash c: Double) {
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

    /// Record today's figures. Called after each day.
    mutating func recordDay() {
        var h = dayHistory
        h.append(netWorth, cash: state.cash + state.savings)
        let json = h.json
        update { s, _, _ in s.rest["dayHist"] = json }
    }
}
