import Foundation
import GameCore
import Countries
import Finance

extension ManagerTargets {
    public struct Status: Equatable, Sendable {
        public struct Budget: Equatable, Sendable {
            public var year: Int
            public var rev: Double
            public var profit: Double
            public var doneRev: Double
            public var doneProfit: Double
            public var approved: Bool
            public var by: String
        }
        public struct LogLine: Equatable, Sendable { public var month: Int; public var met: Int }
        public var setter: Setter
        public var hasManager: Bool
        public var direction: String?
        public var standing: [Standing]
        public var budget: Budget?
        public var log: [LogLine]
    }

    @discardableResult
    public static func approveBudget(_ s: inout GameState, companyID: Int, year: Int? = nil) -> Bool {
        guard let ci = s.companyIndex(companyID) else { return false }
        var t = record(s.companies[ci])
        var y = t["y"]
        if y.isNull || (year != nil && y["yr"].int != year) { return false }
        y["ok"] = .number(1)
        t["y"] = y
        put(&s, ci, t)
        return true
    }

    public static func status(_ s: GameState, companyID: Int, data: GameData) -> Status? {
        guard let co = s.company(companyID), eligible(co, data: data) else { return nil }
        let t = record(co), y = t["y"], se = setter(s, co, data: data), a = yearToDate(co, week: s.week)
        var budget: Status.Budget? = nil
        if !y.isNull {
            budget = Status.Budget(year: y["yr"].int, rev: y["rev"].double, profit: y["profit"].double, doneRev: a?.rev ?? 0, doneProfit: a?.profit ?? 0,
                                   approved: y["ok"].bool, by: y["by"].string)
        }
        let log = t["log"].array.suffix(6).map { Status.LogLine(month: $0["mi"].int, met: $0["n"].int) }
        return Status(setter: se, hasManager: co.managerID != nil, direction: OwnerMeetings.directive(co), standing: standing(co, week: s.week), budget: budget, log: log)
    }
}
