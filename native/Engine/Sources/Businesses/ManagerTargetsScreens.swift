import Foundation
import GameCore
import Countries
import Finance

/// What the screens and actions use of the targets: the preview and the setting of targets (`ACT.tg58set`, `tg58f`, `tg58go`), the budget
/// approval, and the card (`T.card`). Model: `ManagerTargets` (original: features/people/targets_and_budgets.js).
extension ManagerTargets {
    public struct Preview: Equatable, Sendable {
        public struct Row: Equatable, Sendable { public var key: String; public var target: Double }
        public var month: Int
        public var rows: [Row]
        /// What one target met pays, for the three bonus levels (none, standard, high).
        public var bonusPerTarget: [Double]
        public var hasManager: Bool
    }

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
        public struct LogLine: Equatable, Sendable { public var month: Int; public var met: Int; public var bonus: Double }
        public var setter: Setter
        public var hasManager: Bool
        /// This month's targets and where they stand (empty before the first targets are set).
        public var standing: [Standing]
        public var bonusLevel: Int
        public var budget: Budget?
        public var log: [LogLine]
        public var canSet: Bool
    }

    /// The targets you would set for this month at this strictness (0 easy, 1 realistic, 2 stretch); nothing is saved. Original: `ACT.tg58set` / `tg58f`.
    public static func preview(_ s: GameState, companyID: Int, mode: Int, data: GameData) -> Preview? {
        guard let co = s.company(companyID), eligible(co, data: data), let v = compute(s, co, month: mi(s), mode: mode, data: data) else { return nil }
        let wage = co.managerMonthlyWage, k3 = v["k3"].string
        let rows = ["rev", "profit", k3].map { Preview.Row(key: $0, target: v["T"][$0].double) }
        return Preview(month: mi(s), rows: rows, bonusPerTarget: bonusLevels.map { $0.rate * wage }, hasManager: co.managerID != nil)
    }

    /// Set this month's targets and the manager's bonus level, and approve the year's budget. Only where you are the one who sets them;
    /// a company you run yourself gets targets of your own. Original: `ACT.tg58go`.
    @discardableResult
    public static func apply(_ s: inout GameState, companyID: Int, mode: Int, bonus: Int, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), eligible(s.companies[ci], data: data), lastYear(s.companies[ci]) != nil,
              setter(s, s.companies[ci], data: data).isOwner else { return false }
        let yr = GameCalendar.year(week: s.week), md = min(2, max(0, mode))
        var t = record(s.companies[ci])
        if t["y"].isNull || t["y"]["yr"].int != yr {
            makeBudget(&s, ci, year: yr, data: data)
            t = record(s.companies[ci])
        }
        if !t["y"].isNull { var y = t["y"]; y["ok"] = .number(1); t["y"] = y }
        t["bo"] = .number(Double(min(2, max(0, bonus))))
        if s.companies[ci].managerID == nil { t["own"] = .number(1); t["ownMode"] = .number(Double(md)) }
        put(&s, ci, t)
        return setTargets(&s, ci, month: mi(s), mode: md, data: data)
    }

    /// Approve next year's budget as the manager drafted it. Original: the approval inside `tg58go`.
    @discardableResult
    public static func approveBudget(_ s: inout GameState, companyID: Int) -> Bool {
        guard let ci = s.companyIndex(companyID) else { return false }
        var t = record(s.companies[ci])
        var y = t["y"]
        if y.isNull { return false }
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
        let log = t["log"].array.suffix(6).map { Status.LogLine(month: $0["mi"].int, met: $0["n"].int, bonus: $0["bonus"].double) }
        return Status(setter: se, hasManager: co.managerID != nil, standing: standing(co, week: s.week), bonusLevel: t["bo"].isNull ? 1 : t["bo"].int,
                      budget: budget, log: log, canSet: se.isOwner && lastYear(co) != nil)
    }
}
